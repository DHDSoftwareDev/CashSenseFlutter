import { createReconciler } from './entitlements.mjs';
import { verifyApple, verifyGoogle, googleRequest, productPlan } from './store.mjs';
export async function fetchPurchase(platform,input) {
  productPlan(input.productId);
  if ((platform==='apple') !== input.productId.startsWith('cashsense.app.')) throw Object.assign(new Error('Product/store mismatch'),{status:400});
  return platform==='apple' ? verifyApple(input.productId,input.transactionId) : verifyGoogle(input.productId,input.purchaseToken);
}
export const reconcile = createReconciler({fetchPurchase});
export async function refresh(userId,platform,input,options) {
  const result = await reconcile(userId,platform,input,options);
  if (platform==='google' && result.premiumUntil>Math.floor(Date.now()/1000) && result.acknowledgementRequired) await googleRequest(result.acknowledgementUrl,'POST',{});
  return result;
}
