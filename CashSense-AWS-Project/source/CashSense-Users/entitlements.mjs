import { createHash } from 'node:crypto';
// A user revision serializes snapshots across every purchase and both stores.
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, TransactWriteCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';
export const db = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
export const USERS = process.env.USERS_TABLE || 'CashSense-Users';
export const CLAIMS = process.env.PURCHASE_CLAIMS_TABLE || 'CashSense-PurchaseClaims';
export const nowSeconds = () => Math.floor(Date.now()/1000);
import { resolve } from './premium-policy.mjs';
export { resolve } from './premium-policy.mjs';
export function createReconciler({ send = command => db.send(command), fetchPurchase }) {
  const get = async (table,key) => (await send(new GetCommand({TableName:table,Key:key,ConsistentRead:true}))).Item;
  return async function reconcile(userId, platform, input, options = {}) {
    for (let attempt=0; attempt<8; attempt++) {
      const user = await get(USERS,{userId});
      if (!user) throw Object.assign(new Error('User profile missing; call GET /users/me first'),{status:409});
      // Read revision BEFORE asking the store. A conflicted snapshot is always re-fetched.
      const verified = await fetchPurchase(platform,input);
      const claimId = verified.claimId;
      const claim = await get(CLAIMS,{claimId});
      if (claim?.userId && claim.userId !== userId) throw Object.assign(new Error('Purchase belongs to another account'),{status:409});
      if (claim?.platform && claim.platform !== platform) throw new Error('Claim platform mismatch');
      let until = verified.premiumUntil;
      const lifetimeVoided = verified.isLifetime && (claim?.lifetimeVoided === true || claim?.googleVoided === true || (options.voidedOrderId && options.voidedOrderId === verified.orderId));
      if (lifetimeVoided || claim?.supersededBy) until = 0;
      const entry = {storeVerified:true,verifiedAt:new Date().toISOString(),claimId,platform,productId:verified.productId,premiumUntil:until,isLifetime:verified.isLifetime,orderId:verified.orderId};
      const ledger = {...user.billingEntitlements};
      ledger[claimId]=entry;
      let linked;
      if (verified.linkedPurchaseToken && verified.linkedPurchaseToken !== input.purchaseToken) {
        const linkedId='google#'+createHash('sha256').update(verified.linkedPurchaseToken).digest('hex');
        const old=await get(CLAIMS,{claimId:linkedId});
        if (old?.userId && old.userId!==userId) throw Object.assign(new Error('Linked purchase belongs to another account'),{status:409});
        linked={...old,claimId:linkedId,userId,platform:'google',productId:old?.productId || input.productId,purchaseToken:verified.linkedPurchaseToken,supersededBy:claimId,premiumUntil:0};
        ledger[linkedId]={claimId:linkedId,platform:'google',premiumUntil:0};
      }
      if (Buffer.byteLength(JSON.stringify(ledger))>250000) throw new Error('Entitlement ledger capacity exceeded; contact support');
      const resolved = resolve({...user,billingEntitlements:ledger});
      const revision = Number(user.billingRevision || 0);
      const saved = {...claim,...entry,userId,updatedAt:new Date().toISOString(),billingVersion:1,lifetimeVoided:!!lifetimeVoided,
        ...(platform==='google' ? {purchaseToken:input.purchaseToken} : {transactionId:verified.orderId,environment:verified.environment})};
      const fields = {billingEntitlements:ledger,billingRevision:revision+1,isPremium:resolved.isPremium,tier:resolved.tier,premiumStatus:resolved.premiumStatus,premiumSource:resolved.premiumSource ?? null,premiumUntil:resolved.premiumUntil || 0,premiumClaimId:resolved.premiumClaimId ?? null,updatedAt:saved.updatedAt};
      const names={}, values={':rev':revision};
      const sets=Object.entries(fields).map(([k,v],i)=>{names['#f'+i]=k;values[':v'+i]=v;return '#f'+i+' = :v'+i;});
      try {
        const extra = linked ? [{Put:{TableName:CLAIMS,Item:linked,ConditionExpression:'attribute_not_exists(userId) OR userId = :uid',ExpressionAttributeValues:{':uid':userId}}}] : [];
        await send(new TransactWriteCommand({TransactItems:[...extra,
          {Put:{TableName:CLAIMS,Item:saved,ConditionExpression:'attribute_not_exists(userId) OR userId = :uid',ExpressionAttributeValues:{':uid':userId}}},
          {Update:{TableName:USERS,Key:{userId},UpdateExpression:'SET '+sets.join(', '),ConditionExpression:'attribute_exists(userId) AND (billingRevision = :rev OR (attribute_not_exists(billingRevision) AND :rev = :zero)) AND (attribute_not_exists(devOverride) OR devOverride = :dev) AND (attribute_not_exists(testerOverride) OR testerOverride = :tester)',ExpressionAttributeNames:names,ExpressionAttributeValues:{...values,':zero':0,':dev':user.devOverride ?? false,':tester':user.testerOverride ?? false}}}
        ]}));
        return {...verified,premiumUntil:until,entitlements:resolved};
      } catch(error) { if(error.name!=='TransactionCanceledException') throw error; }
    }
    throw new Error('Concurrent billing updates; retry');
  };
}
export async function scanClaims(startKey) {
  return db.send(new ScanCommand({TableName:CLAIMS,ExclusiveStartKey:startKey,Limit:5,ConsistentRead:true}));
}
