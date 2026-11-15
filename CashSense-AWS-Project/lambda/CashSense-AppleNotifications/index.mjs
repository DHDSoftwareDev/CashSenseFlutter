import { refresh } from './runtime.mjs';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { Environment, SignedDataVerifier } from '@apple/app-store-server-library';

const USERS = process.env.USERS_TABLE;
const CLAIMS = process.env.PURCHASE_CLAIMS_TABLE;
const EVENTS = process.env.APPLE_NOTIFICATION_EVENTS_TABLE;
const BUNDLE = process.env.APPLE_BUNDLE_ID;
const APP_ID = Number(process.env.APPLE_APP_ID);
const PRODUCTS = new Set(['cashsense.app.premium.monthly', 'cashsense.app.premium.annual', 'cashsense.app.premium.lifetime']);
const SUBS = new Set(['cashsense.app.premium.monthly', 'cashsense.app.premium.annual']);
const db = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
const roots = ['AppleIncRootCertificate.cer', 'AppleRootCA-G2.cer', 'AppleRootCA-G3.cer'].map(name => readFileSync(new URL(`./apple-certificates/${name}`, import.meta.url)));
const verifiers = new Map();

function response(statusCode, body) {
  return { statusCode, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }, body: JSON.stringify(body) };
}
function verifier(environment) {
  if (!verifiers.has(environment)) {
    verifiers.set(environment, new SignedDataVerifier(roots, true, environment, BUNDLE, environment === Environment.PRODUCTION ? APP_ID : undefined));
  }
  return verifiers.get(environment);
}
function claimId(originalId) { return `apple#${createHash('sha256').update(String(originalId)).digest('hex')}`; }
function validMs(n) { const v = Number(n); return Number.isSafeInteger(v) && v > 0 ? v : 0; }
function requiredConfig() {
  if (![USERS, CLAIMS, EVENTS, BUNDLE].every(x => typeof x === 'string' && x.length > 0) || !Number.isSafeInteger(APP_ID) || APP_ID <= 0) {
    throw new Error('Apple notification Lambda configuration incomplete');
  }
}
async function verifyPayload(signedPayload) {
  let lastError;
  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const v = verifier(environment);
      const notification = await v.verifyAndDecodeNotification(signedPayload);
      if (notification.data?.bundleId && notification.data.bundleId !== BUNDLE) throw new Error('Bundle ID mismatch');
      if (notification.data?.environment && notification.data.environment !== environment) throw new Error('Environment mismatch');
      let tx = null;
      if (notification.data?.signedTransactionInfo) {
        tx = await v.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
        if (tx.bundleId !== BUNDLE || (tx.environment && tx.environment !== environment)) throw new Error('Transaction app mismatch');
      }
      return { notification, tx, environment };
    } catch (error) { lastError = error; }
  }
  // A verifier failure can also be caused by network/certificate validation.
  // Do not misclassify an unknown verifier failure as a permanent 400.
  throw new Error(`Apple signature verification failed: ${lastError?.message || 'unknown'}`);
}

async function acquireEvent(uuid, notification) {
  const now = Date.now();
  try {
    await db.send(new PutCommand({ TableName: EVENTS,
      Item: { notificationUUID: uuid, status: 'processing', leaseUntil: now + 120000, createdAt: new Date(now).toISOString(), notificationType: notification.notificationType || 'UNKNOWN' },
      ConditionExpression: 'attribute_not_exists(notificationUUID)' }));
    return 'acquired';
  } catch (error) {
    if (error.name !== 'ConditionalCheckFailedException') throw error;
  }
  const old = (await db.send(new GetCommand({ TableName: EVENTS, Key: { notificationUUID: uuid }, ConsistentRead: true }))).Item;
  if (old?.status === 'processed' || old?.status === 'ignored') return 'complete';
  if (old?.leaseUntil > now) return 'busy';
  try {
    await db.send(new UpdateCommand({ TableName: EVENTS, Key: { notificationUUID: uuid },
      UpdateExpression: 'SET #s = :processing, leaseUntil = :lease, retryAt = :now',
      ConditionExpression: '#s <> :processed AND #s <> :ignored AND (attribute_not_exists(leaseUntil) OR leaseUntil <= :now)',
      ExpressionAttributeNames: { '#s': 'status' },
      ExpressionAttributeValues: { ':processing': 'processing', ':processed': 'processed', ':ignored': 'ignored', ':lease': now + 120000, ':now': now } }));
    return 'acquired';
  } catch (error) {
    if (error.name === 'ConditionalCheckFailedException') return 'busy';
    throw error;
  }
}
async function finish(uuid, status, reason) {
  await db.send(new UpdateCommand({ TableName: EVENTS, Key: { notificationUUID: uuid },
    UpdateExpression: 'SET #s = :status, finishedAt = :now, detail = :detail REMOVE leaseUntil',
    ConditionExpression: '#s = :processing', ExpressionAttributeNames: { '#s': 'status' },
    ExpressionAttributeValues: { ':status': status, ':processing': 'processing', ':now': new Date().toISOString(), ':detail': reason } }));
}
async function release(uuid, reason) {
  await db.send(new UpdateCommand({ TableName: EVENTS, Key: { notificationUUID: uuid },
    UpdateExpression: 'SET #s = :failed, detail = :detail, leaseUntil = :zero',
    ExpressionAttributeNames: { '#s': 'status' }, ExpressionAttributeValues: { ':failed': 'failed', ':detail': reason.slice(0, 300), ':zero': 0 } }));
}

async function processNotification(uuid, notification, tx) {
  if (notification.notificationType === 'TEST') { await finish(uuid,'processed','Test'); return; }
  if (!tx?.originalTransactionId || !PRODUCTS.has(tx.productId)) { await finish(uuid,'ignored','Unsupported transaction'); return; }
  const claim = (await db.send(new GetCommand({TableName:CLAIMS,Key:{claimId:claimId(tx.originalTransactionId)},ConsistentRead:true}))).Item;
  if (!claim?.userId || claim.platform !== 'apple') throw new Error('Purchase owner not linked; retry');
  // Notification dates never grant or revoke access. Fetch the latest signed store status.
  await refresh(claim.userId,'apple',{productId:tx.productId,transactionId:String(tx.transactionId)});
  await finish(uuid,'processed','Current store state reconciled');
}

export const handler = async event => {
  if (event?.requestContext?.http?.method !== 'POST' && event?.httpMethod !== 'POST') return response(405, { ok: false });
  try {
    requiredConfig();
    const raw = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64').toString('utf8') : event.body;
    if (typeof raw !== 'string' || raw.length > 200000) return response(400, { ok: false, error: 'Invalid request body' });
    let parsed;
    try { parsed = JSON.parse(raw); } catch { return response(400, { ok: false, error: 'Invalid JSON' }); }
    if (typeof parsed?.signedPayload !== 'string' || parsed.signedPayload.length > 190000) return response(400, { ok: false, error: 'Missing signedPayload' });
    // Reject structurally malformed JWS before calling the Apple verifier.
    // Cryptographic verification and certificate checks remain the verifier's job.
    const segments = parsed.signedPayload.split('.');
    if (segments.length !== 3 || segments.some(part => !/^[A-Za-z0-9_-]+$/.test(part))) {
      return response(400, { ok: false, error: 'Malformed signedPayload' });
    }
    try {
      const header = JSON.parse(Buffer.from(segments[0], 'base64url').toString('utf8'));
      if (!header || typeof header !== 'object' || header.alg !== 'ES256') {
        return response(400, { ok: false, error: 'Invalid signedPayload header' });
      }
      JSON.parse(Buffer.from(segments[1], 'base64url').toString('utf8'));
    } catch {
      return response(400, { ok: false, error: 'Malformed signedPayload' });
    }
    const { notification, tx } = await verifyPayload(parsed.signedPayload);
    const uuid = notification.notificationUUID;
    if (typeof uuid !== 'string' || !/^[0-9a-f-]{20,80}$/i.test(uuid)) throw new Error('Invalid Apple notification UUID');
    const acquired = await acquireEvent(uuid, notification);
    if (acquired === 'complete') return response(200, { ok: true, duplicate: true });
    if (acquired === 'busy') return response(503, { ok: false, retry: true });
    try { await processNotification(uuid, notification, tx); }
    catch (error) { await release(uuid, error.message || 'processing error'); throw error; }
    return response(200, { ok: true });
  } catch (error) {
    console.error('Apple notification processing failed', { message: error.message, name: error.name });
    return response(503, { ok: false, retry: true });
  }
};
