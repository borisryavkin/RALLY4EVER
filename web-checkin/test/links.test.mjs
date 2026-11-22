import{test}from'node:test';import assert from'node:assert/strict';import{readLink,versionMap,friendlyError,origin}from'../src/links.mjs';const qr=origin+'/c/session-one?k='+'a'.repeat(43);
test('strict QR and nested email link parsing retain request capability but never trust a different origin',()=>{assert.equal(readLink(qr).eventCode,'session-one');const action=origin+'/auth?mode=signIn&oobCode=one-use&continueUrl='+encodeURIComponent(qr+'&noAppRequest=request-one');assert.equal(readLink(action).oobCode,'one-use');assert.equal(readLink(action).requestId,'request-one');assert.throws(()=>readLink(qr.replace('/c/','/other/')));assert.throws(()=>readLink(origin+'/auth?continueUrl='+encodeURIComponent('https://evil.test/c/session-one?k='+'a'.repeat(43))));assert.throws(()=>readLink(origin+'/c/session?k=random-barcode'));});
test('current versions and actionable server failures',()=>{assert.deepEqual(versionMap([{id:'conduct',version:2}]),{conduct:2});assert.match(friendlyError({details:{reason:'invalid-secret'}}),/expired/);assert.match(friendlyError({details:{reason:'too-far'}}),/too far/);});

test('anonymous retry token still works when browser storage access is denied',async()=>{
 const {anonymousTokenFor}=await import('../src/links.mjs');const previous=Object.getOwnPropertyDescriptor(globalThis,'localStorage');
 try{Object.defineProperty(globalThis,'localStorage',{configurable:true,get(){throw Error('Storage denied');}});const token=anonymousTokenFor('storage-denied-session');assert.match(token,/^[A-Za-z0-9_-]{43}$/);assert.equal(anonymousTokenFor('storage-denied-session'),token);assert.notEqual(anonymousTokenFor('other-storage-denied-session'),token);}
 finally{if(previous)Object.defineProperty(globalThis,'localStorage',previous);else delete globalThis.localStorage;}
});

test('three mandatory groups preserve all four approved bodies and receipt versions',async()=>{
 const {agreementGroups,versionMap}=await import('../src/links.mjs');const raw=['conduct','waiver','data-collection','photo-release'].map(id=>({id,body:id+' verbatim  \n',version:'2026-11-20'}));const groups=agreementGroups(raw);
 assert.deepEqual(groups.map(f=>f.title),['Code of Conduct','Data Collection','Photo Release']);assert.ok(groups.every(f=>f.required));assert.equal(groups[0].body,'conduct verbatim  \n\n\nwaiver verbatim  \n');assert.equal(Object.keys(versionMap(groups)).length,4);assert.throws(()=>agreementGroups(raw.slice(0,3)),/missing/);
});
