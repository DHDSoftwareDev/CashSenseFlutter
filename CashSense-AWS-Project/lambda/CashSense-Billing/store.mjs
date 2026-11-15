import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { GoogleAuth } from 'google-auth-library';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import {
  AppStoreServerAPIClient, Environment, SignedDataVerifier,
} from '@apple/app-store-server-library';

const USERS_TABLE = process.env.USERS_TABLE || 'CashSense-Users';
const CLAIMS_TABLE = process.env.PURCHASE_CLAIMS_TABLE || 'CashSense-PurchaseClaims';
const APPLE_BUNDLE = process.env.APPLE_BUNDLE_ID || 'name.dhdsoftware.cashsense.CashSenseMM';
const GOOGLE_APP = process.env.GOOGLE_PACKAGE_NAME || 'com.dhdsoftware.cashsense';
const secrets = new SecretsManagerClient({});
const secretCache = new Map();
async function getSecret(id) {
  if (!id) throw new Error('Missing secret reference');
  if (!secretCache.has(id)) {
    const result = await secrets.send(new GetSecretValueCommand({ SecretId: id }));
    if (!result.SecretString) throw new Error('Secret must contain a JSON string');
    secretCache.set(id, JSON.parse(result.SecretString));
  }
  return secretCache.get(id);
}

const APPLE_BUNDLE_ID = APPLE_BUNDLE;
const GOOGLE_PACKAGE = GOOGLE_APP;
const PRODUCTS = Object.freeze({
  'cashsense.app.premium.monthly': 'Monthly',
  'cashsense.app.premium.annual': 'Annual',
  'cashsense.app.premium.lifetime': 'Lifetime',
  'cashsense_premium_monthly': 'Monthly',
  'cashsense_premium_annual': 'Annual',
  'cashsense_premium_lifetime': 'Lifetime',
});
const SUBSCRIPTIONS = new Set(['cashsense.app.premium.monthly', 'cashsense.app.premium.annual', 'cashsense_premium_monthly', 'cashsense_premium_annual']);
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
let googleAuth;
async function getGoogleAuth() {
  if (!googleAuth) {
    const credentials = await getSecret(process.env.GOOGLE_SECRET_ID);
    if (credentials.type !== 'service_account' || !credentials.client_email || !credentials.private_key) {
      throw new Error('Google service account secret is incomplete');
    }
    googleAuth = new GoogleAuth({
      credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });
  }
  return googleAuth;
}

function reply(statusCode, payload) {
  return { statusCode, headers: {
    'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  }, body: JSON.stringify(payload) };
}
function requireUser(event) {
  const claims = event?.requestContext?.authorizer?.jwt?.claims || event?.requestContext?.authorizer?.claims;
  const userId = typeof claims?.sub === 'string' ? claims.sub.trim() : '';
  if (!userId) throw Object.assign(new Error('Authenticated Cognito JWT required'), { status: 401 });
  return userId;
}
function text(value, max = 4096) {
  return typeof value === 'string' && value.length > 0 && value.length <= max ? value : '';
}
function unixMs(value) {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : 0;
}
function productPlan(productId) {
  if (!Object.hasOwn(PRODUCTS, productId)) {
    throw Object.assign(new Error('Unknown product'), { status: 400 });
  }
  return PRODUCTS[productId];
}
function hashedClaim(platform, identifier) {
  return `${platform}#${createHash('sha256').update(identifier).digest('hex')}`;
}
function storeError(message) {
  return Object.assign(new Error(message), { status: 422 });
}

async function googleRequest(url, method = 'GET', data) {
  const client = await (await getGoogleAuth()).getClient();
  const response = await client.request({ url, method, timeout:15000, retryConfig:{retry:1}, ...(data === undefined ? {} : { data }) });
  return response.data;
}

async function verifyGoogle(productId, purchaseToken) {
  const token = text(purchaseToken, 8192);
  if (!token) throw Object.assign(new Error('Missing purchase token'), { status: 400 });
  const encoded = encodeURIComponent(token);
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(GOOGLE_PACKAGE)}/purchases`;
  if (SUBSCRIPTIONS.has(productId)) {
    const purchase = await googleRequest(`${base}/subscriptionsv2/tokens/${encoded}`);
    const matching = (purchase.lineItems || []).filter(item => ['cashsense_premium_monthly','cashsense_premium_annual'].includes(item.productId));
    if (!matching.length) throw storeError('Product mismatch');
    const validState = ['SUBSCRIPTION_STATE_ACTIVE','SUBSCRIPTION_STATE_IN_GRACE_PERIOD','SUBSCRIPTION_STATE_CANCELED'].includes(purchase.subscriptionState);
    const expiryMs = Math.max(0, ...matching.map(item => Date.parse(item.expiryTime || '')).filter(Number.isFinite));
    matching.sort((a,b) => Date.parse(b.expiryTime || '')-Date.parse(a.expiryTime || ''));
    const currentProduct = matching[0].productId;
    return {
      claimId: hashedClaim('google', token), productId:currentProduct,
      premiumUntil: validState ? Math.floor(expiryMs / 1000) : 0,
      orderId: text(purchase.latestOrderId || '', 512),
      isLifetime: false,
      linkedPurchaseToken: purchase.linkedPurchaseToken,
      acknowledgementRequired: purchase.acknowledgementState !== 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
      acknowledgementUrl: `${base}/subscriptions/${encodeURIComponent(currentProduct)}/tokens/${encoded}:acknowledge`,
    };
  }
  const purchase = await googleRequest(`${base}/products/${encodeURIComponent(productId)}/tokens/${encoded}`);
  if (purchase.purchaseState === 0 && !purchase.orderId) throw storeError('Missing store order ID');
  return {
    claimId: hashedClaim('google', token), productId,
    premiumUntil: purchase.purchaseState === 0 ? 253402300799 : 0, orderId: String(purchase.orderId || ''), isLifetime: true,
    acknowledgementRequired: purchase.acknowledgementState === 0,
    acknowledgementUrl: `${base}/products/${encodeURIComponent(productId)}/tokens/${encoded}:acknowledge`,
  };
}

async function appleClient(environment) {
  const secret = await getSecret(process.env.APPLE_SECRET_ID);
  const storedKey = secret.privateKey?.trim();

const key = storedKey
  ? storedKey.includes('-----BEGIN')
    ? storedKey.replace(/\\n/g, '\n')
    : `-----BEGIN PRIVATE KEY-----\n${storedKey.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----`
  : undefined;
  const keyId = secret.keyId;
  const issuerId = secret.issuerId;
  if (!key || !keyId || !issuerId) {
    throw new Error('Apple App Store Server API configuration is incomplete');
  }
  return new AppStoreServerAPIClient(key, keyId, issuerId, APPLE_BUNDLE_ID, environment);
}
function appleVerifier(environment) {
  // Apple public root certificates are bundled as DER .cer files.
  // No private keys or certificate JSON environment variables are required.
  const roots = [
    'AppleIncRootCertificate.cer',
    'AppleRootCA-G2.cer',
    'AppleRootCA-G3.cer',
  ].map(name => readFileSync(new URL(`./apple-certificates/${name}`, import.meta.url)));
  const appAppleId = Number(process.env.APPLE_APP_ID);
  if (environment === Environment.PRODUCTION && (!Number.isSafeInteger(appAppleId) || appAppleId <= 0)) {
    throw new Error('APPLE_APP_ID must be the numeric CashSense Apple App ID');
  }
  return new SignedDataVerifier(roots, true, environment, APPLE_BUNDLE_ID,
    environment === Environment.PRODUCTION ? appAppleId : undefined);
}
async function verifyApple(productId, transactionId) {
  const id = text(transactionId, 128);
  if (!/^\d{8,30}$/.test(id)) throw Object.assign(new Error('Invalid Apple transaction ID'), { status: 400 });
  let lastError;
  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const result = await (await appleClient(environment)).getTransactionInfo(id);
      const signed = result.signedTransactionInfo;
      if (!signed) throw storeError('Apple transaction data missing');
      const tx = await appleVerifier(environment).verifyAndDecodeTransaction(signed);
      if (tx.bundleId !== APPLE_BUNDLE_ID || tx.productId !== productId ||
          !tx.originalTransactionId || tx.transactionId !== id) {
        throw storeError('Apple transaction mismatch');
      }

      if (tx.type === 'Consumable') throw storeError('Consumable products cannot grant Premium');
      const lifetime = productId === 'cashsense.app.premium.lifetime';
      let current = tx;
      let expiryMs = unixMs(tx.expiresDate);
      if (lifetime && tx.type !== 'Non-Consumable') throw storeError('Lifetime must be non-consumable');
      if (!lifetime) {
        if (tx.type !== 'Auto-Renewable Subscription') throw storeError('Unexpected Apple product type');
        const statuses = await (await appleClient(environment)).getAllSubscriptionStatuses(id);
        const candidates = [];
        for (const group of statuses.data || []) for (const last of group.lastTransactions || []) {
          if (String(last.originalTransactionId) !== String(tx.originalTransactionId)) continue;
          const latest = await appleVerifier(environment).verifyAndDecodeTransaction(last.signedTransactionInfo);
          if (latest.bundleId !== APPLE_BUNDLE_ID || String(latest.originalTransactionId) !== String(tx.originalTransactionId) || !latest.productId?.startsWith('cashsense.app.') || !SUBSCRIPTIONS.has(latest.productId)) throw storeError('Invalid Apple status transaction');
          const renewal = last.signedRenewalInfo ? await appleVerifier(environment).verifyAndDecodeRenewalInfo(last.signedRenewalInfo) : null;
          if (renewal && String(renewal.originalTransactionId) !== String(tx.originalTransactionId)) throw storeError('Renewal mismatch');
          const until = Number(last.status) === 4 ? unixMs(renewal?.gracePeriodExpiresDate) : unixMs(latest.expiresDate);
          candidates.push({ tx: latest, until: !latest.revocationDate && [1,4].includes(Number(last.status)) ? until : 0 });
        }
        if (!candidates.length) throw new Error('Apple subscription status missing original transaction');
        candidates.sort((a,b) => Number(b.tx.purchaseDate || 0)-Number(a.tx.purchaseDate || 0));
        current = candidates[0].tx; expiryMs = candidates[0].until;
      }
      return {
        claimId: hashedClaim('apple', String(tx.originalTransactionId)), productId: current.productId,
        premiumUntil: lifetime ? (tx.revocationDate ? 0 : 253402300799) : Math.floor(expiryMs / 1000),
        orderId: String(current.transactionId), isLifetime: lifetime, environment,
        transactionId: String(tx.originalTransactionId),
      };
    } catch (error) {
      lastError = error;
      if (error?.status === 422) throw error;
    }
  }
  console.error('Apple verification failed', {
  errorName: lastError?.name,
  message: lastError?.message || String(lastError),
  statusCode: lastError?.httpStatusCode ?? lastError?.statusCode,
  apiError: lastError?.apiError
});
  throw storeError('Apple verification could not be completed');
}


export { verifyApple, verifyGoogle, googleRequest, productPlan, PRODUCTS, SUBSCRIPTIONS, hashedClaim, reply, requireUser, text };
