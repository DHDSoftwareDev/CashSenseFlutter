import { refresh } from './runtime.mjs';
import { createHash } from 'node:crypto';
import { OAuth2Client, GoogleAuth } from 'google-auth-library';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const env = (key) => { const value = process.env[key]; if (!value) throw new Error(`Missing ${key}`); return value; };
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
const secrets = new SecretsManagerClient({});
const verifier = new OAuth2Client();
let googleAuth;
const respond = (statusCode, message) => ({ statusCode, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }, body: JSON.stringify({ message }) });
const sha = (s) => createHash('sha256').update(s).digest('hex');

async function authenticate(event) {
  const headers = Object.fromEntries(Object.entries(event.headers || {}).map(([k,v]) => [k.toLowerCase(), v]));
  const match = /^Bearer\s+(\S+)$/i.exec(headers.authorization || '');
  if (!match) throw Object.assign(new Error('Missing bearer token'), { statusCode: 401 });
  const ticket = await verifier.verifyIdToken({ idToken: match[1], audience: env('GOOGLE_PUBSUB_AUDIENCE') });
  const claims = ticket.getPayload();
  if (!claims || !['accounts.google.com','https://accounts.google.com'].includes(claims.iss) ||
      claims.email !== env('GOOGLE_PUBSUB_PUSH_EMAIL') || claims.email_verified !== true) {
    throw Object.assign(new Error('Unexpected Google identity'), { statusCode: 403 });
  }
}
async function playRequest(url) {
  if (!googleAuth) {
    const secret = await secrets.send(new GetSecretValueCommand({ SecretId: env('GOOGLE_SECRET_ID') }));
    const credentials = JSON.parse(secret.SecretString || '{}');
    if (credentials.type !== 'service_account' || !credentials.client_email || !credentials.private_key) throw new Error('Google Play credentials are invalid');
    googleAuth = new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  }
  const client = await googleAuth.getClient();
  const result = await client.request({ url });
  return result.data;
}
function decodeMessage(event) {
  if (event.isBase64Encoded) event = {...event, body:Buffer.from(event.body || '', 'base64').toString('utf8')};
  if (typeof event.body !== 'string' || event.body.length > 200000) throw Object.assign(new Error('Invalid body'), { statusCode: 400 });
  const envelope = JSON.parse(event.body);
  const message = envelope?.message;
  if (!message || typeof message.data !== 'string' || message.data.length > 150000) throw Object.assign(new Error('Missing Pub/Sub data'), { statusCode: 400 });
  const decoded = Buffer.from(message.data, 'base64').toString('utf8');
  if (decoded.length > 100000) throw Object.assign(new Error('Notification too large'), { statusCode: 400 });
  const notification = JSON.parse(decoded);
  if (notification.packageName !== env('GOOGLE_PACKAGE_NAME')) throw Object.assign(new Error('Package mismatch'), { statusCode: 400 });
  return notification;
}
async function reconcile(token, options={}) {
  if (typeof token !== 'string' || !token || token.length>8192) throw new Error('Invalid purchase token');
  const claim=(await ddb.send(new GetCommand({TableName:env('PURCHASE_CLAIMS_TABLE'),Key:{claimId:`google#${sha(token)}`},ConsistentRead:true}))).Item;
  if (!claim?.userId || claim.platform!=='google') throw new Error('Purchase owner not linked; retry');
  await refresh(claim.userId,'google',{productId:claim.productId,purchaseToken:token},options);
  return 'Current store state reconciled';
}
async function reconcileVoidedPurchase(notice) {
  return reconcile(notice.purchaseToken, Number(notice.productType)===2 ? {voidedOrderId:notice.orderId} : {});
}
export const handler = async (event) => {
  if ((event.requestContext?.http?.method || event.httpMethod) !== 'POST') return respond(405, 'Method not allowed');
  try { await authenticate(event); } catch (error) { console.warn('Pub/Sub authentication rejected:', error.message); return respond(error.statusCode || 401, 'Unauthorized'); }
  try {
    const notice = decodeMessage(event);
    if (notice.testNotification) return respond(200, 'Test notification received');
    if (notice.subscriptionNotification?.purchaseToken) {
      const outcome = await reconcile(notice.subscriptionNotification.purchaseToken);
      console.info('Google subscription reconciled:', outcome);
      return respond(200, 'Processed');
    }
    if (notice.oneTimeProductNotification) {
      await reconcile(notice.oneTimeProductNotification.purchaseToken);
      return respond(200, 'Acknowledged');
    }
    if (notice.voidedPurchaseNotification) {
      const outcome = await reconcileVoidedPurchase(notice.voidedPurchaseNotification);
      console.info('Google voided purchase:', outcome);
      return respond(200, outcome);
    }
    return respond(200, 'Ignored');
  } catch (error) {
    console.error('Google Play notification processing failed:', { name: error.name, message: error.message });
    return respond(error.statusCode || 503, error.statusCode ? 'Invalid notification' : 'Temporary processing failure');
  }
};
