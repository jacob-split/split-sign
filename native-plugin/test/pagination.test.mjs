import test from 'node:test';
import assert from 'node:assert/strict';
import {cleanPacket,signatureList} from '../api.mjs';
test('archive state takes precedence while preserving source signing status',()=>{assert.equal(cleanPacket({id:1,status:'completed',archived_at:'2026-01-01'}).status,'archived');assert.equal(cleanPacket({id:1,status:'completed',archived_at:'2026-01-01'}).sourceStatus,'completed');});
test('terminal pages do not expose a continuation',async()=>{const old=globalThis.fetch,key=process.env.SPLIT_SIGN_API_KEY;process.env.SPLIT_SIGN_API_KEY='fixture';try{for(const pagination of [{next:1},{next:1,has_more:false}]){globalThis.fetch=async()=>({ok:true,json:async()=>({data:[{id:1}],pagination})});const result=await signatureList('packets',{limit:2});assert.equal(result.hasMore,false);assert.equal(result.nextPage,null);}}finally{globalThis.fetch=old;if(key===undefined)delete process.env.SPLIT_SIGN_API_KEY;else process.env.SPLIT_SIGN_API_KEY=key;}});
