// Shared Premium authorization. premiumUntil is Unix seconds.
const nowSeconds = () => Math.floor(Date.now()/1000);
export function resolve(user, now = nowSeconds()) {
  const entries = Object.values(user.billingEntitlements || {});
  const best = entries.filter(x => x?.storeVerified === true && ['apple','google'].includes(x.platform) && typeof x.claimId === 'string' && Number.isSafeInteger(x.premiumUntil) && x.premiumUntil > now).sort((a,b) => b.premiumUntil-a.premiumUntil || a.claimId.localeCompare(b.claimId))[0];
  const out = { ...user, isPremium: false, tier: 'free', premiumStatus: 'inactive' };
  if (user.devOverride === true || user.testerOverride === true) return { ...out, isPremium: true, tier:'premium', premiumStatus:'active', premiumSource: user.devOverride ? 'dev' : 'tester' };
  if (best) return { ...out, isPremium:true, tier:'premium', premiumStatus:'active', premiumSource:best.platform, premiumUntil:best.premiumUntil, premiumClaimId:best.claimId };
  return { ...out, premiumSource:null, premiumUntil:0, premiumClaimId:null };
}
