import {planProfileUpgrade} from '../../scripts/profile-schema.mjs';
import {before, after, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, getDocs, collection, query, where, updateDoc, deleteDoc, serverTimestamp, Timestamp} from 'firebase/firestore';
import {profile, accounts, event} from '../../scripts/fixtures.mjs';
import {requireEmulators, projectId} from '../../scripts/emulator-env.mjs';

let env;
const now = Timestamp.now();
const past = Timestamp.fromMillis(now.toMillis() - 3600000);
const future = Timestamp.fromMillis(now.toMillis() + 3600000);
const user = (uid, claims = {}) => env.authenticatedContext(uid, {email_verified: true, role: accounts.find(a=>a.uid===uid)?.role ?? 'participant', ...claims}).firestore();
const ownDb = () => user('participant-1');
const rsvp = (extra = {}) => ({uid:'participant-1', eventId:'event-1', createdAt:serverTimestamp(), cancelledAt:null, source:'app', ...extra});
const feedback = (extra = {}) => ({uid:'participant-1', eventId:'event-3', rating:4, tags:['people'], comment:'Good session', createdAt:serverTimestamp(), ...extra});
async function trusted(path, data) {
  await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), path), data));
}
before(async () => {
  requireEmulators();
  env = await initializeTestEnvironment({projectId, firestore:{host:'127.0.0.1',port:8080,rules:await readFile('firestore.rules','utf8')}});
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await Promise.all([
      ...accounts.map(a => setDoc(doc(db,`users/${a.uid}`), profile(a, now))),
      setDoc(doc(db,'events/event-1'), event('event-1','coach-1',past,future)),
      setDoc(doc(db,'events/event-2'), event('event-2','coach-2',past,future)),
      setDoc(doc(db,'events/event-3'), event('event-3','coach-1',past,past)),
      setDoc(doc(db,'events/draft'), {...event('draft','coach-1',past,future),status:'draft'}),
      setDoc(doc(db,'forms/waiver'),{formType:'waiver',version:2,publishedAt:Timestamp.now(),body:'Rule test'}),
      setDoc(doc(db,'forms/conduct'),{formType:'conduct',version:1,publishedAt:Timestamp.now(),body:'Rule test'}),
      setDoc(doc(db,'checkins/event-3_participant-1'),{uid:'participant-1',eventId:'event-3',status:'confirmed'}),
      setDoc(doc(db,'checkins/event-1_participant-1'),{uid:'participant-1',eventId:'event-1',status:'pending'}),
      setDoc(doc(db,'notifications/scan_event-1_participant-1'),{uid:'participant-1',eventId:'event-1',type:'scan',readAt:null,createdAt:now}),
      setDoc(doc(db,'emailIdentities/private'),{uid:'participant-1',emailLower:'member1@example.test'}),
      setDoc(doc(db,'eventSecrets/event-1'),{secretHash:'secret'}),
    ]);
  });
});

test('anonymous and unverified users cannot access app data',async () => {
  for (const db of [env.unauthenticatedContext().firestore(), env.authenticatedContext('participant-1',{email_verified:false}).firestore()]) {
    for (const path of ['users/participant-1','events/event-1','forms/waiver','checkins/event-1_participant-1']) await assertFails(getDoc(doc(db,path)));
  }
});
test('profile read/update is owner-only; preserve identity, timestamps, merge and roles',async () => {
  const db = ownDb();
  await assertSucceeds(getDoc(doc(db,'users/participant-1')));
  await assertFails(getDoc(doc(db,'users/participant-2')));
  await assertFails(getDocs(collection(db,'users')));
  await assertSucceeds(updateDoc(doc(db,'users/participant-1'),{firstName:'Priya', updatedAt:serverTimestamp()}));
  for (const change of [{role:'admin'},{uid:'participant-2'},{emailLower:'other@example.test'},{email:'other@example.test'},{mergedInto:'participant-2'},{createdAt:future},{surprise:true},{firstName:42},{preferences:{marketingEmails:true}},{emergencyContact:{name:3,mobile:4}}]) {
    await assertFails(updateDoc(doc(db,'users/participant-1'),{...change,updatedAt:serverTimestamp()}));
  }
  await assertFails(deleteDoc(doc(db,'users/participant-1')));
});
test('client cannot create a duplicate profile or reserve email identities',async () => {
  const db = user('new-user');
  await assertFails(setDoc(doc(db,'users/new-user'),profile({uid:'new-user',email:'MEMBER1@example.test',role:'participant'},now)));
  await assertFails(setDoc(doc(ownDb(),'emailIdentities/private'),{uid:'participant-2'}));
  await assertFails(getDoc(doc(ownDb(),'emailIdentities/private')));
});
test('merged profiles and missing profiles have no active access',async () => {
  await trusted('users/participant-1',{...profile(accounts[3],now),mergedInto:'participant-2'});
  await assertFails(getDoc(doc(ownDb(),'events/event-1')));
  await assertFails(getDoc(doc(user('not-provisioned'),'events/event-1')));
});
test('protected role field overrides stale admin/coach claims',async () => {
  await assertFails(setDoc(doc(user('participant-1',{role:'admin'}),'events/new'),{}));
  await assertFails(getDoc(doc(user('participant-1',{role:'coach'}),'checkins/event-3_participant-1-does-not-exist')));
  await assertSucceeds(setDoc(doc(user('admin-1'),'events/new'),{name:'Admin managed'}));
});
test('role claim works when trusted profile has no role field',async () => {
  const p = profile(accounts[1],now); delete p.role;
  await trusted('users/coach-1',p);
  await assertSucceeds(getDoc(doc(user('coach-1',{role:'coach'}),'checkins/event-1_participant-1')));
  await assertFails(getDoc(doc(env.authenticatedContext('coach-1',{email_verified:true}).firestore(),'checkins/event-1_participant-1')));
});
test('published event queries work; drafts require assigned coach or admin',async () => {
  await assertSucceeds(getDocs(query(collection(ownDb(),'events'),where('status','==','published'))));
  await assertFails(getDoc(doc(ownDb(),'events/draft')));
  await assertSucceeds(getDoc(doc(user('coach-1'),'events/draft')));
  await assertFails(getDoc(doc(user('coach-2'),'events/draft')));
  await assertFails(updateDoc(doc(user('coach-1'),'events/event-1'),{coachUids:['coach-2']}));
});
test('intent is separate; deterministic owner RSVP, cancel/rejoin, no attendance write',async () => {
  const ref = doc(ownDb(),'rsvps/event-1_participant-1');
  await assertSucceeds(setDoc(ref,rsvp()));
  await assertSucceeds(updateDoc(ref,{cancelledAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(ref,{cancelledAt:null}));
  await assertFails(updateDoc(ref,{source:'coach-added'}));
  await assertFails(updateDoc(ref,{uid:'participant-2'}));
  await assertFails(deleteDoc(ref));
  await assertFails(setDoc(doc(ownDb(),'rsvps/random-id'),rsvp()));
  await assertFails(setDoc(doc(ownDb(),'rsvps/event-2_participant-2'),rsvp({uid:'participant-2',eventId:'event-2'})));
  await assertFails(setDoc(doc(ownDb(),'rsvps/event-2_participant-1'),rsvp({eventId:'event-2',source:'coach-added'})));
  await assertFails(setDoc(doc(ownDb(),'rsvps/event-3_participant-1'),rsvp({eventId:'event-3'})));
  await assertFails(setDoc(doc(ownDb(),'rsvps/draft_participant-1'),rsvp({eventId:'draft'})));
  await assertFails(setDoc(doc(ownDb(),'rsvps/missing_participant-1'),rsvp({eventId:'missing'})));
});
test('coach-added intent is visible to the canonical participant UID; queries are scoped',async () => {
  await trusted('rsvps/event-1_participant-1',{...rsvp(),createdAt:now,source:'coach-added'});
  const result = await assertSucceeds(getDocs(query(collection(ownDb(),'rsvps'),where('uid','==','participant-1'))));
  assert.equal(result.docs.length,1); assert.equal(result.docs[0].data().source,'coach-added');
  await assertFails(getDocs(collection(ownDb(),'rsvps')));
  await assertSucceeds(getDocs(query(collection(user('coach-1'),'rsvps'),where('eventId','==','event-1'))));
  await assertFails(getDoc(doc(user('coach-2'),'rsvps/event-1_participant-1')));
});
test('attendance readable only to owner, assigned coach, admin; every client write denied',async () => {
  for (const uid of ['participant-1','coach-1','admin-1']) {
    const ref=doc(user(uid),'checkins/event-1_participant-1');
    await assertSucceeds(getDoc(ref));
    await assertFails(updateDoc(ref,{status:'confirmed',confirmedBy:uid}));
    await assertFails(updateDoc(ref,{corrections:[{reason:'correction'}]}));
    await assertFails(deleteDoc(ref));
    await assertFails(setDoc(doc(user(uid),'checkins/event-2_participant-1'),{uid:'participant-1',eventId:'event-2'}));
  }
  for (const uid of ['participant-2','coach-2']) await assertFails(getDoc(doc(user(uid),'checkins/event-1_participant-1')));
  await assertSucceeds(getDocs(query(collection(user('coach-1'),'checkins'),where('eventId','==','event-1'))));
});
test('QR secrets never accessible by client including admin',async () => {
  for(const uid of ['participant-1','coach-1','admin-1']) {
    await assertFails(getDoc(doc(user(uid),'eventSecrets/event-1')));
    await assertFails(setDoc(doc(user(uid),'eventSecrets/event-1'),{secretHash:'changed'}));
  }
});
test('consent accepts only owner/current matching form, version and server timestamp',async () => {
  const data={uid:'participant-1',formId:'waiver',formType:'waiver',version:2,signedAt:serverTimestamp()};
  const ref=doc(ownDb(),'consents/participant-1_waiver');
  for (const extra of [{version:1},{formType:'conduct'},{signedAt:past},{extra:1},{uid:'participant-2'},{formId:'missing'}]) await assertFails(setDoc(ref,{...data,...extra}));
  await assertSucceeds(setDoc(ref,data));
  await assertFails(setDoc(ref,data)); // preserve signature for the same version
  await assertFails(getDoc(doc(user('participant-2'),'consents/participant-1_waiver')));
  await assertFails(deleteDoc(ref));
  await trusted('forms/waiver',{formType:'waiver',version:3,publishedAt:Timestamp.now(),body:'Rule test'});
  await assertFails(setDoc(ref,data));
  await assertSucceeds(setDoc(ref,{...data,version:3}));
});
test('only confirmed attendees can submit valid feedback after end; no overwrite',async () => {
  const ref=doc(ownDb(),'feedback/event-3_participant-1');
  for (const extra of [{rating:0},{rating:6},{rating:2.5},{tags:['unknown']},{comment:3},{createdAt:past},{extra:1}]) await assertFails(setDoc(ref,feedback(extra)));
  await assertFails(setDoc(doc(ownDb(),'feedback/event-1_participant-1'),feedback({eventId:'event-1'})));
  await trusted('checkins/event-1_participant-1',{uid:'participant-1',eventId:'event-1',status:'confirmed'});
  await assertFails(setDoc(doc(ownDb(),'feedback/event-1_participant-1'),feedback({eventId:'event-1'})));
  await assertSucceeds(setDoc(ref,feedback()));
  await assertFails(updateDoc(ref,{rating:1}));
  await assertFails(getDoc(doc(user('participant-2'),'feedback/event-3_participant-1')));
  await assertSucceeds(getDoc(doc(user('coach-1'),'feedback/event-3_participant-1')));
  await assertFails(getDoc(doc(user('coach-2'),'feedback/event-3_participant-1')));
});
test('devices and inbox are private; only mark own notification read',async () => {
  const ref=doc(ownDb(),'users/participant-1/devices/browser');
  await assertSucceeds(setDoc(ref,{token:'test-token',platform:'web',updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(user('coach-1'),'users/participant-1/devices/browser')));
  await assertFails(setDoc(ref,{token:42,platform:'web',updatedAt:serverTimestamp()}));
  const note=doc(ownDb(),'notifications/scan_event-1_participant-1');
  await assertSucceeds(updateDoc(note,{readAt:serverTimestamp()}));
  await assertFails(updateDoc(note,{uid:'participant-2'}));
  await assertFails(setDoc(doc(ownDb(),'notifications/forged'),{uid:'participant-1'}));
  await assertFails(getDoc(doc(user('participant-2'),'notifications/scan_event-1_participant-1')));
});
test('unknown collections denied; admin can manage forms, profiles and merge audits',async () => {
  await assertFails(setDoc(doc(user('admin-1'),'unknown/doc'),{}));
  for (const path of ['forms/new','users/managed','mergeAudits/merge-1']) {
    await assertSucceeds(setDoc(doc(user('admin-1'),path),{managed:true}));
    if (!path.startsWith('forms/')) await assertFails(getDoc(doc(ownDb(),path)));
    await assertFails(setDoc(doc(ownDb(),path),{managed:false}));
  }
});

test('phone/emergency contact are visible only to the owner, admin, and a coach actually granted access',async()=>{
  await trusted('users/participant-1/private/contact',{mobile:'0400000000',mobileVerified:false,emergencyContact:{name:'Pat',mobile:'0400000001'},visibleToCoachUids:['coach-1'],updatedAt:now});
  await assertSucceeds(getDoc(doc(ownDb(),'users/participant-1/private/contact')));
  await assertSucceeds(getDoc(doc(user('coach-1'),'users/participant-1/private/contact')));
  // coach-2 runs no event participant-1 is involved in -- not in visibleToCoachUids.
  await assertFails(getDoc(doc(user('coach-2'),'users/participant-1/private/contact')));
  // Another participant can never read this, regardless of visibleToCoachUids.
  await assertFails(getDoc(doc(user('participant-2'),'users/participant-1/private/contact')));
  await assertSucceeds(getDoc(doc(user('admin-1'),'users/participant-1/private/contact')));
  // The owner can edit their own mobile/emergency contact...
  await assertSucceeds(updateDoc(doc(ownDb(),'users/participant-1/private/contact'),{mobile:'0400000099',updatedAt:serverTimestamp()}));
  // ...but can never set or widen visibleToCoachUids themselves -- only
  // trusted server code (service.ts's syncContactVisibility) may.
  await assertFails(updateDoc(doc(ownDb(),'users/participant-1/private/contact'),{visibleToCoachUids:['coach-1','coach-2'],updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(ownDb(),'users/participant-1/private/contact'),{mobileVerified:true,updatedAt:serverTimestamp()}));
});
test('Workspace email without a coach claim cannot read coach data; stale claims fail after revocation',async()=>{
  const noClaim=env.authenticatedContext('coach-1',{email_verified:true,email:'dan@rally4ever.org',firebase:{sign_in_provider:'google.com'}}).firestore();
  await assertFails(getDoc(doc(noClaim,'checkins/event-1_participant-1')));
  await assertFails(getDoc(doc(noClaim,'rsvps/event-1_participant-1')));
  await assertSucceeds(getDoc(doc(user('coach-1'),'checkins/event-1_participant-1')));
  await env.withSecurityRulesDisabled(async ctx=>updateDoc(doc(ctx.firestore(),'users/coach-1'),{coachEnabled:false,role:'participant'}));
  await assertFails(getDoc(doc(user('coach-1'),'checkins/event-1_participant-1')));
});


test('prefilled first-page save works after upgrading legacy profile/contact schema',async()=>{
  const original={...profile(accounts[3],now),mobile:'0400000000',emergencyContact:{name:'Contact',mobile:'0400000001'},
    about:{ageRange:'25–34',currentActivity:'Working',referral:'Friend',culturalBackground:'Neither'}};
  await trusted('users/participant-1',original);
  const plan=planProfileUpgrade(original);
  const changes={firstName:original.firstName,postcode:original.postcode,about:plan.profile.about,updatedAt:serverTimestamp()};
  // Even current rules cannot accept the legacy top-level phone fields.
  await assertFails(updateDoc(doc(ownDb(),'users/participant-1'),changes));
  // A coordinated trusted migration preserves details, moves private contact,
  // and normalizes the old single-choice answers; no identity/role changes.
  await trusted('users/participant-1',plan.profile);
  await trusted('users/participant-1/private/contact',plan.contact);
  await assertSucceeds(updateDoc(doc(ownDb(),'users/participant-1'),changes));
  const saved=(await getDoc(doc(ownDb(),'users/participant-1'))).data();
  assert.equal(saved.firstName,original.firstName);
  assert.equal(saved.postcode,original.postcode);
  assert.equal(saved.about.ageRange,original.about.ageRange);
  await assertSucceeds(updateDoc(doc(ownDb(),'users/participant-1/private/contact'),{mobile:'0400000099',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(user('participant-2'),'users/participant-1'),changes));
  await assertFails(updateDoc(doc(ownDb(),'users/participant-1'),{role:'admin',updatedAt:serverTimestamp()}));
});

test('date-version forms and optional releases accept only the published current version',async()=>{
 for(const formId of ['conduct','waiver','photo-release','data-collection']){
  await trusted('forms/'+formId,{id:formId,formType:formId,version:'2026-11-20',body:'Legal fixture',publishedAt:past});
  const receipt={uid:'participant-1',formId,formType:formId,version:'2026-11-20',signedAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(ownDb(),'consents/participant-1_'+formId),receipt));
  await assertFails(setDoc(doc(ownDb(),'consents/participant-2_'+formId),{...receipt,uid:'participant-2'}));
  await trusted('forms/'+formId,{id:formId,formType:formId,version:'2026-11-21',body:'Legal fixture',publishedAt:past,published:false});
  await assertFails(setDoc(doc(ownDb(),'consents/participant-1_'+formId),{...receipt,version:'2026-11-21'}));
 }
});
