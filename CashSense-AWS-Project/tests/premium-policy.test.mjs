import { test } from 'node:test';
import assert from 'node:assert/strict';
const packages=['CashSense-Billing','CashSense-Users','CashSense-AppleNotifications','CashSense-GoogleNotifications','CashSense-RegisterDevice','CashSense-BackupInit','CashSense-BackupLatest','CashSense-BackupComplete'];
for(const name of packages) {
 const {resolve}=await import('../source/'+name+'/premium-policy.mjs');
 test(name+' shares strict Premium policy',()=>{
  const now=1000;
  for(const u of [{tier:'premium'}, {isPremium:true}, {trialEndsAt:2000}, {premiumSource:'apple',premiumUntil:2000}, {isPremium:true,premiumExpiresAt:'2099-01-01T00:00:00Z'}]) assert.equal(resolve(u,now).isPremium,false);
  const entry={claimId:'a',platform:'apple',storeVerified:true,premiumUntil:2000};
  assert.equal(resolve({billingEntitlements:{a:entry}},now).isPremium,true);
  assert.equal(resolve({billingEntitlements:{a:entry}},2000).isPremium,false);
  for(const flag of ['devOverride','testerOverride'])assert.equal(resolve({[flag]:true},now).isPremium,true);
 });
}
