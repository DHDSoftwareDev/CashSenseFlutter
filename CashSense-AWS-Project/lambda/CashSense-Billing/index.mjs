import { reply, requireUser, text, productPlan, googleRequest, hashedClaim } from './store.mjs';
import { refresh } from './runtime.mjs';
import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { db, CLAIMS } from './entitlements.mjs';
import { scanClaims } from './entitlements.mjs';
export async function handler(event) {
  // Only direct EventBridge invocation can select the maintenance path.
  if (event?.source==='aws.events' && !event.requestContext && !event.httpMethod) {
    if (event.mode==='voided') {
      const base=`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(process.env.GOOGLE_PACKAGE_NAME || 'com.dhdsoftware.cashsense')}/purchases/voidedpurchases`;
      const query=new URLSearchParams({type:'0',maxResults:'100'});
      if(event.token)query.set('token',event.token);
      const page=await googleRequest(base+'?'+query);
      const failures=[];
      for(const voided of page.voidedPurchases || []) {
        const claim=(await db.send(new GetCommand({TableName:CLAIMS,Key:{claimId:hashedClaim('google',voided.purchaseToken)},ConsistentRead:true}))).Item;
        if(!claim?.userId)continue;
        try { await refresh(claim.userId,'google',{productId:claim.productId,purchaseToken:voided.purchaseToken},{voidedOrderId:voided.orderId}); }
        catch(e){failures.push({claimId:claim.claimId,error:e.message});}
      }
      console.log(JSON.stringify({maintenance:true,failures}));
      return {failures,nextToken:page.tokenPagination?.nextPageToken};
    }
    const page = await scanClaims(event.startKey);
    const failures=[];
    for (const claim of page.Items || []) {
      if (!claim.userId || !['apple','google'].includes(claim.platform)) continue;
      const input={productId:claim.productId,purchaseToken:claim.purchaseToken,transactionId:claim.transactionId || claim.appleLastTransactionId};
      if ((claim.platform==='google' && !input.purchaseToken) || (claim.platform==='apple' && !input.transactionId)) { failures.push({claimId:claim.claimId,error:'Legacy claim needs authenticated Flutter restore; hashed identifiers cannot be reversed'}); continue; }
      try { await refresh(claim.userId,claim.platform,input); } catch(e) { failures.push({claimId:claim.claimId,error:e.message}); }
    }
    // Invoke with returned startKey until absent (Step Functions configuration documented).
    console.log(JSON.stringify({maintenance:true,failures,nextKey:page.LastEvaluatedKey}));
    return {failures,nextKey:page.LastEvaluatedKey};
  }
  const method=event?.requestContext?.http?.method || event?.httpMethod;
  if(method==='OPTIONS') return reply(200,{ok:true});
  if(method!=='POST') return reply(405,{error:'Method not allowed'});
  try {
    const userId=requireUser(event);
    const path=event.rawPath || event.path || '';
    const legacy = path.endsWith('/billing/verify') || path.endsWith('/entitlements/refresh');
    let platform=path.endsWith('/apple/verify')?'apple':path.endsWith('/google-play/verify')?'google':null;
    if(!platform && !legacy) return reply(404,{error:'Route not found'});
    const raw=event.isBase64Encoded?Buffer.from(event.body || '', 'base64').toString():event.body;
    if(typeof raw!=='string' || raw.length>20000) return reply(400,{error:'Invalid body'});
    let input;try{input=JSON.parse(raw);}catch{return reply(400,{error:'Invalid JSON'});}
    if (!input || typeof input !== 'object' || Array.isArray(input)) return reply(400,{error:'JSON object required'});
    if (legacy) {
      const hasApple=typeof input.transactionId==='string' && input.transactionId.length>0;
      const hasGoogle=typeof input.purchaseToken==='string' && input.purchaseToken.length>0;
      if (hasApple===hasGoogle) return reply(400,{error:'Supply exactly one transactionId or purchaseToken, plus productId'});
      platform=hasApple?'apple':'google';
    }
    input={...input,productId:text(input?.productId,128)};
    const result=await refresh(userId,platform,input);
    if(result.premiumUntil<=Math.floor(Date.now()/1000)) return reply(422,{verified:false,error:'Purchase is expired, pending, or revoked'});
    return reply(200,{ok:true,verified:true,plan:productPlan(result.productId),premiumUntil:result.premiumUntil,platform,isPremium:result.entitlements.isPremium,productId:result.productId,premiumExpiresAt:result.isLifetime?null:new Date(result.premiumUntil*1000).toISOString()});
  }catch(e){console.error('Billing failed',{name:e.name,message:e.message});return reply(e.status || 503,{error:e.status?e.message:'Verification temporarily unavailable; retry'});}
}
