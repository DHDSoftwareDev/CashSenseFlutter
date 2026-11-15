import {test,mock} from 'node:test';
import assert from 'node:assert/strict';
process.env.USERS_TABLE='Users';process.env.PURCHASE_CLAIMS_TABLE='Claims';process.env.GOOGLE_SECRET_ID='google';
process.env.GOOGLE_PACKAGE_NAME='com.dhdsoftware.cashsense';process.env.GOOGLE_PUBSUB_AUDIENCE='https://example.invalid/push';process.env.GOOGLE_PUBSUB_PUSH_EMAIL='push@example.invalid';
process.env.APPLE_BUNDLE_ID='name.dhdsoftware.cashsense.CashSenseMM';process.env.APPLE_APP_ID='1234';process.env.APPLE_NOTIFICATION_EVENTS_TABLE='Events';
import {DynamoDBDocumentClient} from '../source/CashSense-Billing/node_modules/@aws-sdk/lib-dynamodb/dist-cjs/index.js';
import {SecretsManagerClient} from '../source/CashSense-Billing/node_modules/@aws-sdk/client-secrets-manager/dist-cjs/index.js';
import {GoogleAuth,OAuth2Client} from '../source/CashSense-Billing/node_modules/google-auth-library/build/src/index.js';
import {SignedDataVerifier} from '../source/CashSense-Billing/node_modules/@apple/app-store-server-library/dist/index.js';

const otherPackages=['CashSense-Users','CashSense-AppleNotifications','CashSense-GoogleNotifications'];
const extraDynamo=[],extraSecrets=[],extraGoogle=[],extraOAuth=[],extraApple=[];
for(const pkg of otherPackages) {
 const base='../source/'+pkg+'/node_modules/';
 extraDynamo.push((await import(base+'@aws-sdk/lib-dynamodb/dist-cjs/index.js')).DynamoDBDocumentClient);
 extraSecrets.push((await import(base+'@aws-sdk/client-secrets-manager/dist-cjs/index.js')).SecretsManagerClient);
 const g=await import(base+'google-auth-library/build/src/index.js');extraGoogle.push(g.GoogleAuth);extraOAuth.push(g.OAuth2Client);
 extraApple.push((await import(base+'@apple/app-store-server-library/dist/index.js')).SignedDataVerifier);
}

let voids=[];
let user={userId:'u',devOverride:false,testerOverride:false},claim,ackFail=false,authFail=false,storeState=0,notice={testNotification:{},packageName:process.env.GOOGLE_PACKAGE_NAME};
const writes=[];
for(const C of [DynamoDBDocumentClient,...extraDynamo]) mock.method(C.prototype,'send',async c=>{const p=c.input;writes.push(c.constructor.name);if(c.constructor.name==='GetCommand')return {Item:p.TableName==='Users'?structuredClone(user):p.TableName==='Claims'?claim:undefined};if(c.constructor.name==='TransactWriteCommand'){for(const x of p.TransactItems){if(x.Put)claim=x.Put.Item;if(x.Update){for(const [n,key]of Object.entries(x.Update.ExpressionAttributeNames))user[key]=x.Update.ExpressionAttributeValues[':v'+n.slice(2)];}}}return {};});
for(const C of [SecretsManagerClient,...extraSecrets]) mock.method(C.prototype,'send',async()=>({SecretString:JSON.stringify({type:'service_account',client_email:'x@y',private_key:'fixture'})}));
for(const C of [GoogleAuth,...extraGoogle]) mock.method(C.prototype,'getClient',async()=>({request:async req=>{if(req.method==='POST'){if(ackFail)throw new Error('ack offline');return {data:{}};}if(req.url.includes('/voidedpurchases'))return {data:{voidedPurchases:voids}};return {data:{purchaseState:storeState,orderId:'order',acknowledgementState:0}};}}));
for(const C of [OAuth2Client,...extraOAuth]) mock.method(C.prototype,'verifyIdToken',async()=>{if(authFail)throw new Error('bad token');return {getPayload:()=>({iss:'https://accounts.google.com',email:process.env.GOOGLE_PUBSUB_PUSH_EMAIL,email_verified:true})};});
for(const C of [SignedDataVerifier,...extraApple]) mock.method(C.prototype,'verifyAndDecodeNotification',async()=>({notificationUUID:'12345678-abcd-1234-abcd-123456789012',notificationType:'TEST',data:{bundleId:process.env.APPLE_BUNDLE_ID}}));
const billing=await import('../source/CashSense-Billing/index.mjs'),users=await import('../source/CashSense-Users/index.mjs'),google=await import('../source/CashSense-GoogleNotifications/index.mjs'),apple=await import('../source/CashSense-AppleNotifications/index.mjs');
const event=()=>({httpMethod:'POST',path:'/billing/google-play/verify',requestContext:{authorizer:{jwt:{claims:{sub:'u'}}}},body:JSON.stringify({productId:'cashsense_premium_lifetime',purchaseToken:'token'})});
test('Billing HTTP validation and existing route shape',async()=>{assert.equal((await billing.handler({httpMethod:'OPTIONS'})).statusCode,200);assert.equal((await billing.handler({httpMethod:'GET'})).statusCode,405);assert.equal((await billing.handler({httpMethod:'POST',body:'{}'})).statusCode,401);const e=event();e.body='{';assert.equal((await billing.handler(e)).statusCode,400);});
test('Billing grant commits before ack and ack failure retries safely',async()=>{ackFail=true;const r=await billing.handler(event());assert.equal(r.statusCode,503);assert.equal(user.isPremium,true);assert.equal(claim.userId,'u');ackFail=false;const ok=await billing.handler(event());assert.equal(ok.statusCode,200);assert.equal(JSON.parse(ok.body).plan,'Lifetime');});
test('Billing refund updates ledger and returns inactive verification',async()=>{storeState=1;const r=await billing.handler(event());assert.equal(r.statusCode,422);assert.equal(user.isPremium,false);});
test('Users GET computes expiry without writing stale membership summary',async()=>{user={userId:'u',billingMigrationComplete:true,billingEntitlements:{a:{claimId:'a',platform:'apple',premiumUntil:1}},isPremium:true,tier:'premium'};writes.length=0;const r=await users.handler({httpMethod:'GET',requestContext:{authorizer:{jwt:{claims:{sub:'u'}}}}});assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).user.isPremium,false);assert.deepEqual(writes,['GetCommand']);});
function push(){return {httpMethod:'POST',headers:{authorization:'Bearer fixture'},body:JSON.stringify({message:{data:Buffer.from(JSON.stringify(notice)).toString('base64')}})};}
test('Google validates OIDC identity and accepts authenticated test',async()=>{authFail=true;assert.equal((await google.handler(push())).statusCode,401);authFail=false;assert.equal((await google.handler(push())).statusCode,200);});
test('Google validates package name',async()=>{notice={packageName:'wrong',testNotification:{}};assert.equal((await google.handler(push())).statusCode,400);});
test('Apple test notification verifies JWS and commits event',async()=>{const payload=Buffer.from(JSON.stringify({alg:'ES256'})).toString('base64url')+'.e30.c2ln';const r=await apple.handler({httpMethod:'POST',body:JSON.stringify({signedPayload:payload})});assert.equal(r.statusCode,200);});
test('Apple malformed signed payload rejected',async()=>{assert.equal((await apple.handler({httpMethod:'POST',body:JSON.stringify({signedPayload:'bad'})})).statusCode,400);});
test('Google one-time notification restores current Lifetime state',async()=>{storeState=0;notice={packageName:process.env.GOOGLE_PACKAGE_NAME,oneTimeProductNotification:{purchaseToken:'token'}};assert.equal((await google.handler(push())).statusCode,200);assert.equal(user.isPremium,true);});
test('Google voided Lifetime notification falls back to current ledger',async()=>{storeState=1;notice={packageName:process.env.GOOGLE_PACKAGE_NAME,voidedPurchaseNotification:{purchaseToken:'token',productType:2,orderId:'order'}};assert.equal((await google.handler(push())).statusCode,200);assert.equal(user.isPremium,false);});
test('Scheduled void sweep and claim-page paths run without HTTP authorization',async()=>{voids=[{purchaseToken:'token',orderId:'order'}];const result=await billing.handler({source:'aws.events',mode:'voided'});assert.deepEqual(result.failures,[]);assert.equal(user.isPremium,false);const scanned=await billing.handler({source:'aws.events'});assert.deepEqual(scanned.failures,[]);});
test('HTTP request cannot select maintenance by adding source',async()=>{assert.equal((await billing.handler({source:'aws.events',httpMethod:'POST',requestContext:{},body:'{}'})).statusCode,401);});

test('legacy verification routes still require store verification',async()=>{
 user={userId:'u',devOverride:false,testerOverride:false};claim=undefined;storeState=0;
 for(const path of ['/billing/verify','/entitlements/refresh']) {
  const e=event();e.path=path;
  assert.equal((await billing.handler(e)).statusCode,200);
  e.body=JSON.stringify({productId:'cashsense_premium_lifetime',purchaseToken:'token',transactionId:'123456789'});
  assert.equal((await billing.handler(e)).statusCode,400);
 }
 storeState=1;const e=event();e.path='/billing/verify';
 assert.equal((await billing.handler(e)).statusCode,422);
});
test('JSON null and arrays are rejected before store verification',async()=>{
 for(const body of ['null','[]']) {const e=event();e.body=body;assert.equal((await billing.handler(e)).statusCode,400);}
});
