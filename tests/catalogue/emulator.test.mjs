import {before,after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,getDoc,getDocs,collection,query,where,setDoc,serverTimestamp} from 'firebase/firestore';
import {accounts,profile} from '../../scripts/fixtures.mjs';
const require=createRequire(new URL('../../functions/package.json',import.meta.url));
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {AttendanceService}=require('./lib/service');
const {CatalogueService,validateProgram,parseSessionTime}=require('./lib/catalogue');
let app,db,catalogue,env;
const who=(uid,role='participant')=>({uid,email:`${uid}@example.test`,role});
const admin=who('admin-1','admin');
const now=Date.now();
const program=(extra={})=>({name:'Community tennis',sport:'tennis',status:'active',venue:{name:'Waverley courts',address:'Park Parade',suburb:'Bondi Junction',postcode:'2022',state:'NSW',lat:-33.8926,lng:151.2511},timezone:'Australia/Sydney',scheduleText:'Tuesdays during confirmed term dates',coachUids:['coach-1'],coachNames:['Dan'],notes:'Bring water',photoUrl:'https://example.test/courts.jpg',capacity:1,registrationStatus:'open',...extra});
const reason='Catalogue emulator test';
async function createProgram(extra={},id='program-one'){
 await catalogue.saveProgram(admin,{programId:id,program:program(extra),reason});return id;
}
async function session(extra={},eventId='session-one'){
 await catalogue.saveSession(admin,{programId:'program-one',eventId,startsAt:new Date(now+86400000).toISOString(),endsAt:new Date(now+90000000).toISOString(),reason,...extra});return eventId;
}
async function rejects(task,reason){await assert.rejects(task,e=>e.details?.reason===reason);}
before(async()=>{
 if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:23880'||process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:23999')throw new Error('Isolated catalogue emulator ports required; never use the development instance');
 app=initializeApp({projectId:'demo-rally4ever'},'catalogue-tests');db=getFirestore(app);
 catalogue=new CatalogueService(new AttendanceService({db,auth:getAuth(app),now:()=>now}));
 env=await initializeTestEnvironment({projectId:'demo-rally4ever',firestore:{host:'127.0.0.1',port:23880,rules:await readFile('firestore.rules','utf8')}});
});
after(async()=>{await env?.cleanup();if(app)await deleteApp(app);});
beforeEach(async()=>{await env.clearFirestore();await Promise.all(accounts.map(a=>db.doc(`users/${a.uid}`).set(profile(a,Timestamp.now()))));});

test('program validation rejects malformed coordinates, photo protocols, capacities and dates',()=>{
 for(const p of [program({capacity:-1}),program({capacity:1.5}),program({photoUrl:'javascript:alert(1)'}),program({timezone:'not/a-zone'}),program({venue:{...program().venue,lng:null}})])assert.throws(()=>validateProgram(p));
 assert.equal(validateProgram(program({capacity:null})).capacity,null);
 for(const time of ['2026-02-30T10:00:00Z','2026-11-20 10:00','2026-11-20T25:00:00Z'])assert.throws(()=>parseSessionTime(time));
 assert.equal(parseSessionTime('2026-11-20T10:00:00+11:00').toMillis(),Date.parse('2026-11-20T10:00:00+11:00'));
});
test('only admin callables edit programs; revisions and audits preserve history',async()=>{
 await rejects(()=>catalogue.saveProgram(who('participant-1'),{program:program(),reason}),'admin-required');
 await rejects(()=>catalogue.saveProgram(who('coach-1','coach'),{program:program(),reason}),'admin-required');
 await createProgram();await rejects(()=>catalogue.saveProgram(admin,{programId:'program-one',revision:0,program:program(),reason}),'stale-program');
 await catalogue.saveProgram(admin,{programId:'program-one',revision:1,program:program({status:'archived'}),reason});
 assert.equal((await db.doc('programs/program-one').get()).data().revision,2);
 assert.equal((await db.collection('catalogueAudits').get()).size,2);
});
test('rules expose active and archived programs, hide drafts and reject client writes',async()=>{
 await createProgram();await createProgram({status:'draft'},'draft-one');await createProgram({status:'archived'},'archived-one');
 const member=env.authenticatedContext('participant-1',{email_verified:true,role:'participant'}).firestore();
 await assertSucceeds(getDocs(query(collection(member,'programs'),where('status','in',['active','archived']))));
 await assertFails(getDoc(doc(member,'programs/draft-one')));
 await assertFails(setDoc(doc(member,'programs/new-one'),program()));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'programs/program-one')));
 const adminDb=env.authenticatedContext('admin-1',{email_verified:true,role:'admin'}).firestore();
 await assertSucceeds(getDoc(doc(adminDb,'programs/draft-one')));
 await assertFails(setDoc(doc(adminDb,'programs/program-one'),program()));
});
test('dated sessions require a verified venue, active coaches and valid future times',async()=>{
 await createProgram({venue:{...program().venue,lat:null,lng:null}});
 await rejects(()=>session(),'missing-location');
 await catalogue.saveProgram(admin,{programId:'program-one',revision:1,program:program(),reason});
 await db.doc('users/coach-1').update({coachEnabled:false});await rejects(()=>session(),'invalid-coach');
 await db.doc('users/coach-1').update({coachEnabled:true});await session();
 const e=(await db.doc('events/session-one').get()).data();assert.equal(e.programId,'program-one');assert.equal(e.notes,'Bring water');assert.equal(e.bookedCount,0);
 await rejects(()=>catalogue.saveSession(admin,{programId:'program-one',startsAt:new Date(now-1).toISOString(),endsAt:new Date(now+10000).toISOString(),reason}),'past-session');
});
test('concurrent last-spot requests are serialized; duplicate intent does not become attendance',async()=>{
 await createProgram();await session();
 const results=await Promise.allSettled(['participant-1','participant-2'].map(uid=>catalogue.setRsvp(who(uid),{eventId:'session-one'})));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(results.find(r=>r.status==='rejected').reason.details.reason,'session-full');
 const records=await db.collection('rsvps').get(),winner=records.docs[0].data().uid,other=winner==='participant-1'?'participant-2':'participant-1';
 await catalogue.setRsvp(who(winner),{eventId:'session-one'});assert.equal((await db.collection('rsvps').get()).size,1);
 assert.equal((await db.collection('checkins').get()).size,0);
 await catalogue.setRsvp(who(winner),{eventId:'session-one',cancel:true});await catalogue.setRsvp(who(other),{eventId:'session-one'});
 assert.equal((await db.doc('events/session-one').get()).data().bookedCount,1);
});
test('managed reservations cannot bypass the callable; full/closed/archived states refuse new intent',async()=>{
 await createProgram();await session();
 const member=env.authenticatedContext('participant-1',{email_verified:true,role:'participant'}).firestore();
 await assertFails(setDoc(doc(member,'rsvps/session-one_participant-1'),{uid:'participant-1',eventId:'session-one',createdAt:serverTimestamp(),cancelledAt:null,source:'app'}));
 await db.doc('events/session-one').update({registrationStatus:'closed'});await rejects(()=>catalogue.setRsvp(who('participant-1'),{eventId:'session-one'}),'registration-closed');
 await db.doc('events/session-one').update({registrationStatus:'open'});await catalogue.setRsvp(who('participant-1'),{eventId:'session-one'});
 await catalogue.saveProgram(admin,{programId:'program-one',revision:1,program:program({status:'archived'}),reason});
 await rejects(()=>catalogue.setRsvp(who('participant-2'),{eventId:'session-one'}),'registration-closed');
 await catalogue.setRsvp(who('participant-1'),{eventId:'session-one',cancel:true});assert.equal((await db.doc('events/session-one').get()).data().bookedCount,0);
 assert.equal((await db.collection('rsvps').get()).size,1);
});
test('reservation reconciliation repairs coach/merge counts and is idempotent',async()=>{
 await createProgram({capacity:5});await session();await db.doc('rsvps/session-one_participant-3').set({eventId:'session-one',uid:'participant-3',cancelledAt:null,source:'coach-added'});
 await catalogue.reconcileAvailability('session-one');await catalogue.reconcileAvailability('session-one');assert.equal((await db.doc('events/session-one').get()).data().bookedCount,1);
 await db.doc('rsvps/session-one_participant-3').update({cancelledAt:Timestamp.now()});await catalogue.reconcileAvailability('session-one');assert.equal((await db.doc('events/session-one').get()).data().bookedCount,0);
});

test('session-specific capacity, cancellation and revision checks are audited without deleting intent',async()=>{
 await createProgram({capacity:8});await session({capacity:2,notes:'Bring a water bottle'});
 await catalogue.setRsvp(who('participant-1'),{eventId:'session-one'});
 await catalogue.setRsvp(who('participant-2'),{eventId:'session-one'});
 await rejects(()=>session({revision:1,capacity:1}),'capacity-below-reservations');
 await session({revision:1,capacity:2,status:'cancelled'});
 await rejects(()=>catalogue.setRsvp(who('participant-3'),{eventId:'session-one'}),'registration-closed');
 const row=(await db.doc('events/session-one').get()).data();assert.equal(row.status,'cancelled');assert.equal(row.bookedCount,2);assert.equal(row.revision,2);
 const participant=env.authenticatedContext('participant-1',{email_verified:true,role:'participant'}).firestore();
 await assertSucceeds(getDoc(doc(participant,'events/session-one')));
 assert.equal((await db.collection('rsvps').get()).size,2);
 assert.ok((await db.collection('catalogueAudits').get()).size>=3);
 await db.doc('checkins/session-one_participant-1').set({eventId:'session-one',uid:'participant-1',status:'pending'});
 await rejects(()=>session({revision:2,capacity:2}),'session-started');
});
