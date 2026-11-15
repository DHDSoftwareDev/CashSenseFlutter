import {test, mock} from 'node:test';
import assert from 'node:assert/strict';
import {createReconciler,resolve} from '../source/CashSense-Billing/entitlements.mjs';
const future=()=>Math.floor(Date.now()/1000)+3600;
const failure=()=>Object.assign(new Error('conflict'),{name:'TransactionCanceledException'});
function harness() {
 const users=new Map([['u',{userId:'u',devOverride:false,testerOverride:false}]]),claims=new Map(),states=new Map();let conflict=false;
 const send=async c=>{const p=c.input;
  if(c.constructor.name==='GetCommand') return {Item:structuredClone((p.Key.userId?users:claims).get(p.Key.userId || p.Key.claimId))};
  const cp=p.TransactItems.filter(x=>x.Put).at(-1),up=p.TransactItems.find(x=>x.Update);const current=users.get(up.Update.Key.userId),v=up.Update.ExpressionAttributeValues;
  if(conflict){conflict=false;current.billingRevision=(current.billingRevision || 0)+1;throw failure();}
  if((current.billingRevision || 0)!==v[':rev'] || (current.devOverride ?? false)!==v[':dev'] || (current.testerOverride ?? false)!==v[':tester'])throw failure();
  const prior=claims.get(cp.Put.Item.claimId);if(prior?.userId && prior.userId!==cp.Put.Item.userId)throw failure();
  const next={...current};for(const [name,key] of Object.entries(up.Update.ExpressionAttributeNames))next[key]=structuredClone(v[':v'+name.slice(2)]);
  for(const item of p.TransactItems)if(item.Put)claims.set(item.Put.Item.claimId,structuredClone(item.Put.Item));users.set(next.userId,next);return {};
 };
 let reads=0;
 const refresh=createReconciler({send,fetchPurchase:async(p,i)=>{reads++;const s=states.get(i.id);return {claimId:i.id,platform:p,productId:p==='apple'?'cashsense.app.premium.monthly':'cashsense_premium_monthly',orderId:'order',transactionId:'123456789',...structuredClone(s)};}});
 return {users,claims,states,refresh,conflict:()=>{conflict=true;},reads:()=>reads};
}
test('cancel retains paid term, expiration removes access',async()=>{const h=harness();h.states.set('a',{premiumUntil:future(),isLifetime:false});await h.refresh('u','apple',{id:'a'});assert.equal(h.users.get('u').isPremium,true);h.states.set('a',{premiumUntil:1,isLifetime:false});await h.refresh('u','apple',{id:'a'});assert.equal(h.users.get('u').isPremium,false);});
test('multiple Apple and Google purchases: refund falls back to other store',async()=>{const h=harness();h.states.set('a',{premiumUntil:future()+1000,isLifetime:false});h.states.set('g',{premiumUntil:future(),isLifetime:false});await h.refresh('u','apple',{id:'a'});await h.refresh('u','google',{id:'g',purchaseToken:'token'});h.states.set('a',{premiumUntil:0,isLifetime:false});await h.refresh('u','apple',{id:'a'});assert.equal(h.users.get('u').premiumClaimId,'g');assert.equal(h.claims.size,2);});
test('Lifetime refund removes only matching Lifetime; subscription fallback survives',async()=>{const h=harness();h.states.set('l',{premiumUntil:253402300799,isLifetime:true});h.states.set('s',{premiumUntil:future(),isLifetime:false});await h.refresh('u','google',{id:'l',purchaseToken:'l'});await h.refresh('u','apple',{id:'s'});await h.refresh('u','google',{id:'l',purchaseToken:'l'},{voidedOrderId:'order'});assert.equal(h.users.get('u').premiumClaimId,'s');await h.refresh('u','google',{id:'l',purchaseToken:'l'});assert.equal(h.users.get('u').premiumClaimId,'s');});
test('older voided order does not void new Lifetime order',async()=>{const h=harness();h.states.set('l',{premiumUntil:253402300799,isLifetime:true,orderId:'new'});await h.refresh('u','google',{id:'l',purchaseToken:'l'},{voidedOrderId:'old'});assert.equal(h.users.get('u').isPremium,true);});
test('renewal recovers from historical subscription void flag',async()=>{const h=harness();h.claims.set('g',{claimId:'g',userId:'u',platform:'google',googleVoided:true});h.states.set('g',{premiumUntil:future(),isLifetime:false});await h.refresh('u','google',{id:'g',purchaseToken:'g'});assert.equal(h.users.get('u').isPremium,true);});
for(const override of ['devOverride','testerOverride'])test(override+' preserved while purchases are still recorded',async()=>{const h=harness();h.users.get('u')[override]=true;h.states.set('a',{premiumUntil:0,isLifetime:false});await h.refresh('u','apple',{id:'a'});assert.equal(h.users.get('u').isPremium,true);assert.equal(h.claims.size,1);h.users.get('u')[override]=false;assert.equal(resolve(h.users.get('u')).isPremium,false);});
test('duplicate/out of order calls fetch current state and cannot resurrect revoked purchase',async()=>{const h=harness();h.states.set('a',{premiumUntil:future(),isLifetime:false});await h.refresh('u','apple',{id:'a'});h.states.set('a',{premiumUntil:0,isLifetime:false});await h.refresh('u','apple',{id:'a'});await h.refresh('u','apple',{id:'a'});assert.equal(h.users.get('u').isPremium,false);});
test('revision conflict refetches store snapshot',async()=>{const h=harness();h.states.set('a',{premiumUntil:future(),isLifetime:false});h.conflict();await h.refresh('u','apple',{id:'a'});assert.equal(h.reads(),2);});
test('concurrent purchases converge without losing ledger entries',async()=>{const h=harness();h.states.set('a',{premiumUntil:future(),isLifetime:false});h.states.set('g',{premiumUntil:future()+100,isLifetime:false});await Promise.all([h.refresh('u','apple',{id:'a'}),h.refresh('u','google',{id:'g',purchaseToken:'g'})]);assert.equal(Object.keys(h.users.get('u').billingEntitlements).length,2);});
test('cross account ownership denied',async()=>{const h=harness();h.claims.set('a',{userId:'someone',platform:'apple'});h.states.set('a',{premiumUntil:future()});await assert.rejects(h.refresh('u','apple',{id:'a'}),{status:409});});
test('standalone trial and legacy membership never grant store Premium',()=>{
 for(const u of [
  {trialEndsAt:200},
  {tier:'premium',isPremium:true},
  {premiumSource:'apple',premiumUntil:200,premiumClaimId:'legacy'},
  {billingEntitlements:{legacy:{claimId:'legacy',platform:'apple',premiumUntil:200}}},
  {billingMigrationComplete:false,tier:'premium',premiumSource:'manual',premiumUntil:0},
 ])assert.equal(resolve(u,100).isPremium,false);
 assert.equal(resolve({testerOverride:true},100).premiumSource,'tester');
});
test('only verified store ledger entries with valid expiry grant access',()=>{
 const entry={claimId:'a',platform:'apple',premiumUntil:200,storeVerified:true};
 assert.equal(resolve({billingEntitlements:{a:entry}},100).isPremium,true);
 assert.equal(resolve({billingEntitlements:{a:entry}},200).isPremium,false);
 for(const patch of [{storeVerified:false},{storeVerified:'true'},{platform:'manual'},{premiumUntil:'200'},{premiumUntil:Infinity}])
  assert.equal(resolve({billingEntitlements:{a:{...entry,...patch}}},100).isPremium,false);
});
test('new verified purchase cannot import an unverified legacy Lifetime fallback',async()=>{
 const h=harness();Object.assign(h.users.get('u'),{premiumClaimId:'legacy',premiumUntil:253402300799,premiumSource:'apple'});
 h.states.set('g',{premiumUntil:future(),isLifetime:false});await h.refresh('u','google',{id:'g',purchaseToken:'g'});
 assert.equal(h.users.get('u').premiumClaimId,'g');assert.equal(h.users.get('u').billingEntitlements.legacy,undefined);
 assert.equal(h.users.get('u').billingEntitlements.g.storeVerified,true);
 h.states.set('g',{premiumUntil:0,isLifetime:false});await h.refresh('u','google',{id:'g',purchaseToken:'g'});
 assert.equal(h.users.get('u').isPremium,false);
});
test('store outage leaves entitlement unchanged',async()=>{const h=harness();h.states.set('a',{premiumUntil:future()});await h.refresh('u','apple',{id:'a'});const previous=structuredClone(h.users.get('u'));const r=createReconciler({send:async c=>({Item:previous}),fetchPurchase:async()=>{throw new Error('store offline');}});await assert.rejects(r('u','apple',{}));assert.deepEqual(h.users.get('u'),previous);});
test('Google replacement token permanently retires linked entitlement',async()=>{const h=harness();h.states.set('new',{premiumUntil:future(),isLifetime:false,linkedPurchaseToken:'old'});await h.refresh('u','google',{id:'new',purchaseToken:'new'});const old=[...h.claims.values()].find(x=>x.supersededBy);assert.equal(old.supersededBy,'new');h.states.set(old.claimId,{premiumUntil:future()+100,isLifetime:false});await h.refresh('u','google',{id:old.claimId,purchaseToken:'old'});assert.equal(h.users.get('u').billingEntitlements[old.claimId].premiumUntil,0);});
