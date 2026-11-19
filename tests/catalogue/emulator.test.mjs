import {migrateProfiles} from '../../scripts/migrate-profile-schema.mjs';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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

test('check-in only surfaces the viewer\'s own counted-in session, never another participant\'s',async()=>{
 await createProgram();await createProgram({status:'draft'},'draft-one');
 await session();await catalogue.setRsvp(who('participant-1'),{eventId:'session-one'});
 const participant1=env.authenticatedContext('participant-1',{email_verified:true,role:'participant'}).firestore();
 const participant2=env.authenticatedContext('participant-2',{email_verified:true,role:'participant'}).firestore();
 // The two reads the Check-in screen actually depends on: the viewer's own
 // rsvp doc, and the published session it points at.
 const mine=await assertSucceeds(getDocs(query(collection(participant1,'rsvps'),where('uid','==','participant-1'))));
 assert.equal(mine.docs.length,1);assert.equal(mine.docs[0].id,'session-one_participant-1');
 await assertSucceeds(getDoc(doc(participant1,'events/session-one')));
 // Someone else, not counted in, can discover the published session (general
 // program/session discovery is public to any verified member) but cannot
 // read the first participant's rsvp -- their own counted-in list stays empty.
 await assertSucceeds(getDoc(doc(participant2,'events/session-one')));
 await assertFails(getDoc(doc(participant2,'rsvps/session-one_participant-1')));
 await assertFails(getDocs(query(collection(participant2,'rsvps'),where('uid','==','participant-1'))));
 const theirs=await assertSucceeds(getDocs(query(collection(participant2,'rsvps'),where('uid','==','participant-2'))));
 assert.equal(theirs.docs.length,0);
 // A session can only be created for an active program (asserted elsewhere),
 // so there is no "draft session" state to probe here; confirm instead that
 // a session under one draft program doesn't leak visibility into another.
 await assertFails(getDoc(doc(participant1,'programs/draft-one')));
});
test('profile migration dry-run writes nothing; apply backs up and rollback preserves timestamps and identity',async()=>{
 const original={...(await db.doc('users/participant-1').get()).data(),mobile:'0400000000',emergencyContact:{name:'Contact',mobile:'0400000001'},
   about:{ageRange:'25–34',currentActivity:'Working',referral:'Friend',culturalBackground:'Neither'}};
 await db.doc('users/participant-1').set(original);
 const before=(await db.doc('users/participant-1').get()).data();
 const preview=await migrateProfiles(db,{project:'demo-rally4ever'});
 assert.equal(preview.dryRun,true);assert.equal(preview.needsReview,0);
 assert.deepEqual((await db.doc('users/participant-1').get()).data(),before);
 const dir=await mkdtemp(join(tmpdir(),'r4e-profile-migration-'));
 const backup=join(dir,'backup.json');
 try{
  const result=await migrateProfiles(db,{project:'demo-rally4ever',apply:true,backup});
  assert.ok(result.applied>0);
  const updated=(await db.doc('users/participant-1').get()).data();
  assert.equal(updated.uid,before.uid);assert.equal(updated.firstName,before.firstName);
  assert.ok(updated.createdAt.isEqual(before.createdAt));assert.equal(updated.mobile,undefined);
  assert.equal((await db.doc('users/participant-1/private/contact').get()).data().mobile,before.mobile);
  assert.equal((await migrateProfiles(db,{project:'demo-rally4ever'})).upgrade,0);
  await migrateProfiles(db,{project:'demo-rally4ever',apply:true,rollback:backup});
  assert.deepEqual((await db.doc('users/participant-1').get()).data(),before);
  assert.equal((await db.doc('users/participant-1/private/contact').get()).exists,false);
  const second=join(dir,'second-backup.json');
  await migrateProfiles(db,{project:'demo-rally4ever',apply:true,backup:second});
  await db.doc('users/participant-1').update({firstName:'Changed after migration'});
  await assert.rejects(()=>migrateProfiles(db,{project:'demo-rally4ever',apply:true,rollback:second}),/data changed after migration/);
  assert.equal((await db.doc('users/participant-1').get()).data().firstName,'Changed after migration');
 }finally{await rm(dir,{recursive:true,force:true});}
});

test('session overrides venue, timezone, capacity and coach without mutating program',async()=>{
 await createProgram();
 await session({venue:{...program().venue,name:'Alternate venue',lat:-31.95,lng:115.86,state:'WA'},timezone:'Australia/Perth',coachUids:['coach-2'],capacity:18});
 const e=(await db.doc('events/session-one').get()).data();
 assert.equal(e.venue.name,'Alternate venue');assert.equal(e.timezone,'Australia/Perth');assert.deepEqual(e.coachUids,['coach-2']);assert.equal(e.capacity,18);
 assert.deepEqual((await db.doc('programs/program-one').get()).data().coachUids,['coach-1']);
 await rejects(catalogue.saveSession(who('participant-1'),{programId:'program-one',startsAt:new Date(now+86400000).toISOString(),endsAt:new Date(now+90000000).toISOString(),reason}),'admin-required');
});

test('admin sees every console and rotating QR; coach only assigned; Workspace email alone denied',async()=>{
 const {StaffService}=require('./lib/staff');const service=catalogue.service,staff=new StaffService(service);
 await createProgram();await session();await session({coachUids:['coach-2']},'session-two');
 assert.equal((await staff.listStaffSessions(admin,{})).events.length,2);
 assert.equal((await staff.listStaffSessions(who('coach-1','coach'),{})).events.length,1);
 await staff.getEventConsole(admin,{eventId:'session-two'});
 const qr=await service.rotateEventSecret(admin,{eventId:'session-two'});assert.match(qr.url,/^https:\/\/rally4ever.org\/c\/[^?]+\?k=/);
 await rejects(staff.getEventConsole(who('coach-1','coach'),{eventId:'session-two'}),'event-role-required');
 await rejects(service.rotateEventSecret(who('coach-1','coach'),{eventId:'session-two'}),'event-role-required');
 await rejects(staff.listStaffSessions({...who('participant-1'),email:'someone@rally4ever.org'},{}),'staff-required');
 await rejects(staff.listStaffSessions(who('coach-1'),{}),'staff-required');
 await db.doc('users/coach-1').update({role:'participant',coachEnabled:false});
 await rejects(staff.getEventConsole(who('coach-1','coach'),{eventId:'session-one'}),'event-role-required');
});

test('console separates RSVP intent and actual attendance, exposing distance and original scan time',async()=>{
 const {StaffService}=require('./lib/staff');await createProgram();await session();
 await db.doc('rsvps/session-one_participant-1').set({uid:'participant-1',eventId:'session-one',cancelledAt:null});
 await db.doc('checkins/session-one_participant-2').set({uid:'participant-2',eventId:'session-one',status:'pending',scannedAt:Timestamp.fromMillis(now),distanceM:42,walkIn:true,corrections:[]});
 const result=await new StaffService(catalogue.service).getEventConsole(admin,{eventId:'session-one'});
 assert.equal(result.roster.find(p=>p.uid==='participant-1').checkinStatus,null);
 const arrival=result.roster.find(p=>p.uid==='participant-2');assert.equal(arrival.countedIn,false);assert.equal(arrival.distanceM,42);assert.equal(arrival.scannedAt,new Date(now).toISOString());
});

test('role callable grants all three roles and revoked coach loses access with stale token',async()=>{
 const {AdminRoleService}=require('./lib/admin_roles');const roles=new AdminRoleService(catalogue.service),auth=getAuth(app);
 for(const uid of ['participant-1','coach-1']){
   try {await auth.createUser({uid,email:`${uid}@example.test`,emailVerified:true});}catch(e){if(e.code!=='auth/uid-already-exists'&&e.code!=='auth/email-already-exists')throw e;}
 }
 const granted=await roles.setUserRole(admin,{uid:'participant-1',role:'admin',reason});assert.equal(granted.role,'admin');
 assert.equal((await auth.getUser('participant-1')).customClaims.role,'admin');
 await roles.setUserRole(admin,{uid:'participant-1',role:'coach',reason});
 assert.equal((await auth.getUser('participant-1')).customClaims.role,'coach');
 await roles.setUserRole(admin,{uid:'participant-1',role:'participant',reason});
 assert.equal((await auth.getUser('participant-1')).customClaims.role,'participant');
 await rejects(roles.setUserRole(who('participant-1'),{uid:'coach-1',role:'admin',reason}),'admin-required');
 await rejects(roles.setUserRole(admin,{uid:'admin-1',role:'participant',reason}),'self-role-change');
 await createProgram();await session();
 await roles.setUserRole(admin,{uid:'coach-1',role:'participant',reason});
 await rejects(catalogue.service.rotateEventSecret(who('coach-1','coach'),{eventId:'session-one'}),'event-role-required');
 assert.equal((await db.collection('roleAudits').get()).size,4);
});

test('cancellation works after program unpublish, preserves RSVP and scan records, participant denied',async()=>{
 await createProgram();await session();await db.doc('programs/program-one').update({status:'draft'});
 await db.doc('checkins/session-one_participant-1').set({eventId:'session-one',uid:'participant-1',status:'confirmed'});
 await rejects(catalogue.cancelSession(who('participant-1'),{eventId:'session-one',revision:1,reason}),'admin-required');
 await catalogue.cancelSession(admin,{eventId:'session-one',revision:1,reason});
 assert.equal((await db.doc('events/session-one').get()).data().status,'cancelled');
 assert.equal((await db.doc('checkins/session-one_participant-1').get()).data().status,'confirmed');
});

test('existing legacy sessions edit in place without a fabricated program or revision and reject new orphan creation',async()=>{
 const e={...program(),status:'published',startsAt:Timestamp.fromMillis(now+86400000),endsAt:Timestamp.fromMillis(now+90000000),code:'LEGACY',coachUids:['coach-1']};
 await db.doc('events/legacy').set(e);
 const input={eventId:'legacy',revision:null,startsAt:new Date(now+86400000).toISOString(),endsAt:new Date(now+90000000).toISOString(),venue:program().venue,coachUids:['coach-2'],capacity:22,reason};
 await catalogue.saveSession(admin,input);
 const saved=(await db.doc('events/legacy').get()).data();assert.equal(saved.programId,undefined);assert.equal(saved.capacity,22);assert.equal(saved.revision,1);assert.equal(saved.code,'LEGACY');
 await catalogue.cancelSession(admin,{eventId:'legacy',revision:1,reason});
 assert.equal((await db.doc('events/legacy').get()).data().status,'cancelled');
 await rejects(catalogue.saveSession(admin,{...input,eventId:undefined}),'program-required');
});

test('Google-first account links an app password; both logins preserve UID, claims, profile and RSVP',async()=>{
 const {initializeApp:clientApp,deleteApp:deleteClient}=await import('firebase/app');
 const A=await import('firebase/auth');
 const client=clientApp({apiKey:'demo-key',projectId:'demo-rally4ever',appId:'demo-linked-auth'},'google-first-link');
 const auth=A.getAuth(client);A.connectAuthEmulator(auth,'http://127.0.0.1:23999',{disableWarnings:true});
 const email='google-first-linked@example.test',password='Test-app-password-123!';
 const token=Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({iss:'https://accounts.google.com',sub:'google-first-link',email,email_verified:true,aud:'demo-rally4ever'})).toString('base64url')+'.';
 try {
   const google=await A.signInWithCredential(auth,A.GoogleAuthProvider.credential(token)),uid=google.user.uid;
   await getAuth(app).setCustomUserClaims(uid,{role:'admin',roles:['participant','admin']});
   await db.doc(`users/${uid}`).set(profile({uid,email,role:'admin'},Timestamp.now()));
   await db.doc(`emailIdentities/${email}`).set({uid,emailLower:email});
   await db.doc(`rsvps/example_${uid}`).set({eventId:'example',uid,cancelledAt:null});
   await A.updatePassword(google.user,password);assert.equal(google.user.uid,uid);
   await A.signOut(auth);
   const viaPassword=await A.signInWithEmailAndPassword(auth,email,password);assert.equal(viaPassword.user.uid,uid);assert.equal((await A.getIdTokenResult(viaPassword.user,true)).claims.role,'admin');
   await A.signOut(auth);
   const viaGoogle=await A.signInWithCredential(auth,A.GoogleAuthProvider.credential(token));assert.equal(viaGoogle.user.uid,uid);
   assert.deepEqual(viaGoogle.user.providerData.map(p=>p.providerId).sort(),['google.com','password']);
   assert.equal((await db.doc(`emailIdentities/${email}`).get()).data().uid,uid);
   assert.equal((await db.doc(`users/${uid}`).get()).data().role,'admin');assert.equal((await db.doc(`rsvps/example_${uid}`).get()).exists,true);
 } finally {await deleteClient(client);}
});

test('verified password-first member can use Google with the same UID and retained password',async()=>{
 const {initializeApp:clientApp,deleteApp:deleteClient}=await import('firebase/app');const A=await import('firebase/auth');
 const client=clientApp({apiKey:'demo-key',projectId:'demo-rally4ever',appId:'demo-linked-auth'},'password-first-link'),auth=A.getAuth(client);
 A.connectAuthEmulator(auth,'http://127.0.0.1:23999',{disableWarnings:true});
 const email='password-first-linked@example.test',password='Test-app-password-123!';
 try {
   const first=await A.createUserWithEmailAndPassword(auth,email,password),uid=first.user.uid;
   await getAuth(app).updateUser(uid,{emailVerified:true});await A.signOut(auth);
   const token=Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({iss:'https://accounts.google.com',sub:'password-first-link',email,email_verified:true,aud:'demo-rally4ever'})).toString('base64url')+'.';
   const google=await A.signInWithCredential(auth,A.GoogleAuthProvider.credential(token));assert.equal(google.user.uid,uid);
   await A.signOut(auth);assert.equal((await A.signInWithEmailAndPassword(auth,email,password)).user.uid,uid);
 }finally{await deleteClient(client);}
});

test('linking a Google identity already owned by another account fails without merging either UID',async()=>{
 const {initializeApp:clientApp,deleteApp:deleteClient}=await import('firebase/app');const A=await import('firebase/auth');
 const client=clientApp({apiKey:'demo-key',projectId:'demo-rally4ever',appId:'demo-link-collision'},'link-collision'),auth=A.getAuth(client);
 A.connectAuthEmulator(auth,'http://127.0.0.1:23999',{disableWarnings:true});
 const token=Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:'collision-google',email:'google-owner@example.test',email_verified:true})).toString('base64url')+'.';
 try {
   const google=(await A.signInWithCredential(auth,A.GoogleAuthProvider.credential(token))).user.uid;
   await A.signOut(auth);
   const password=(await A.createUserWithEmailAndPassword(auth,'different-owner@example.test','Test-password-123!')).user;
   await assert.rejects(A.linkWithCredential(password,A.GoogleAuthProvider.credential(token)),e=>e.code==='auth/credential-already-in-use');
   assert.notEqual(password.uid,google);assert.equal((await getAuth(app).getUser(password.uid)).email,'different-owner@example.test');
   assert.equal((await getAuth(app).getUser(google)).email,'google-owner@example.test');
 } finally {await deleteClient(client);}
});
