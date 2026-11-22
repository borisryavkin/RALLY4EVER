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
 const qr=await service.rotateEventSecret(admin,{eventId:'session-two'});assert.match(qr.url,/^https:\/\/rally4ever-checkin-3adaf.web.app\/c\/[^?]+\?k=/);
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

test('session save and cancel need no typed reason and still record actor/time/before/after',async()=>{
 await createProgram();
 await catalogue.saveSession(admin,{programId:'program-one',eventId:'automatic-audit',startsAt:new Date(now+86400000).toISOString(),endsAt:new Date(now+90000000).toISOString()});
 await catalogue.cancelSession(admin,{eventId:'automatic-audit',revision:1});
 const audits=(await db.collection('catalogueAudits').where('eventId','==','automatic-audit').get()).docs.map(d=>d.data());
 assert.equal(audits.length,2);assert.ok(audits.every(a=>a.actorUid==='admin-1'&&a.createdAt));assert.ok(audits.some(a=>a.after?.status==='published'));
});

const {AdminConsoleService,venueId}=require('./lib/admin_console');
const consoleService=()=>new AdminConsoleService(catalogue.service);
const adminSession=()=>({...Object.fromEntries(Object.entries(program()).filter(([k])=>k!=='scheduleText')),status:'draft',code:'test-session-code',startsAt:new Date(now+86400000).toISOString(),endsAt:new Date(now+90000000).toISOString(),geofenceRadiusM:150,requiredFormIds:[],isDemo:true,seedBatch:'admin-tests',programId:null});
test('web admin requires admin claim AND active profile for every endpoint',async()=>{
 const c=consoleService();for(const fn of [()=>c.catalogue(who('participant-1'),{}),()=>c.saveSession(who('participant-1'),{changes:{}}),()=>c.saveVenue(who('participant-1'),{}),()=>c.demo(who('participant-1'),{})])await rejects(fn,'admin-claim-required');
 await rejects(()=>c.catalogue(who('admin-1'),{}),'admin-claim-required');
 await db.doc('users/admin-1').update({role:'participant'});await rejects(()=>c.catalogue(admin,{}),'admin-required');
});
test('admin session fields, derived counts, revisions and before/after audit are server controlled',async()=>{
 const c=consoleService();await c.saveSession(admin,{eventId:'web-session',changes:adminSession()});
 await c.saveSession(admin,{eventId:'web-session',revision:1,changes:{notes:'Updated without reason',status:'published'}});
 const d=(await db.doc('events/web-session').get()).data();assert.equal(d.revision,2);assert.equal(d.bookedCount,0);assert.equal(d.coachNames[0],'coach-1');assert.equal(d.updatedBy,'admin-1');assert.ok(d.updatedAt instanceof Timestamp);
 await rejects(()=>c.saveSession(admin,{eventId:'web-session',revision:1,changes:{notes:'Stale'}}),'stale-session');
 await rejects(()=>c.saveSession(admin,{eventId:'web-session',revision:2,changes:{bookedCount:999}}),'unknown-field');
 assert.equal((await db.collection('catalogueAudits').where('kind','==','admin-session').get()).size,2);
});
test('session validation protects capacity, forms, duplicate codes and original scan context',async()=>{
 const c=consoleService();await c.saveSession(admin,{eventId:'web-session',changes:adminSession()});
 await db.doc('rsvps/web-session_participant-1').set({eventId:'web-session',uid:'participant-1',cancelledAt:null});
 await db.doc('rsvps/web-session_participant-2').set({eventId:'web-session',uid:'participant-2',cancelledAt:null});
 await rejects(()=>c.saveSession(admin,{eventId:'web-session',revision:1,changes:{capacity:1}}),'capacity-below-reservations');
 await rejects(()=>c.saveSession(admin,{changes:{...adminSession(),code:'test-session-code'}}),'duplicate-code');
 await rejects(()=>c.saveSession(admin,{changes:{...adminSession(),code:'another',requiredFormIds:['missing']}}),'invalid-forms');
 await db.doc('checkins/web-session_participant-1').set({eventId:'web-session',uid:'participant-1',status:'confirmed',scannedAt:Timestamp.now()});
 await rejects(()=>c.saveSession(admin,{eventId:'web-session',revision:1,changes:{geofenceRadiusM:200}}),'attendance-started');
 await c.saveSession(admin,{eventId:'web-session',revision:1,changes:{notes:'Original scan preserved',capacity:3}});
 assert.equal((await db.doc('checkins/web-session_participant-1').get()).data().status,'confirmed');
});
test('venue catalogue includes legacy courts and uploaded photos propagate without moving original scans',async()=>{
 await createProgram();await session();const c=consoleService(),key=venueId(program().venue);const data=await c.catalogue(admin,{});assert.equal(data.venues.length,1);
 await db.doc('events/started').set({...adminSession(),venue:program().venue,startsAt:Timestamp.fromMillis(now-60000),endsAt:Timestamp.fromMillis(now+60000)});
 const photoUrl=`gs://rally4ever-3adaf.firebasestorage.app/venues/${key}/test.jpg`;
 await c.saveVenue(admin,{venueId:key,revision:0,venue:{...program().venue,code:'COURT-ONE',lat:-33.89,photoUrl}});
 assert.equal((await db.doc('programs/program-one').get()).data().photoUrl,program().photoUrl);
 assert.equal((await db.doc('programs/program-one').get()).data().venue.photoUrl,photoUrl);
 assert.equal((await db.doc('events/session-one').get()).data().venue.lat,-33.89);
 assert.equal((await db.doc('events/started').get()).data().venue.lat,program().venue.lat);
 assert.equal((await db.doc('events/started').get()).data().photoUrl,program().photoUrl);
 assert.equal((await db.doc('events/started').get()).data().venue.photoUrl,photoUrl);
 await rejects(()=>c.saveVenue(admin,{venueId:key,revision:0,venue:{...program().venue,code:'COURT-ONE'}}),'stale-venue');
});
test('demo removal previews exact IDs, detects changes and backs up before deleting only demo sessions',async()=>{
 const c=consoleService();await c.saveSession(admin,{eventId:'demo-one',changes:adminSession()});await c.saveSession(admin,{eventId:'real-one',changes:{...adminSession(),code:'real-one',isDemo:false}});
 const preview=await c.demo(admin,{});assert.deepEqual(preview.eventIds,['demo-one']);
 await rejects(()=>c.demo(admin,{apply:true,expectedIds:[]}), 'demo-changed');
 const result=await c.demo(admin,{apply:true,expectedIds:preview.eventIds});assert.equal(result.removed,1);assert.equal((await db.doc('events/real-one').get()).exists,true);assert.equal((await db.collection('demoRemovalBackups').get()).size,1);assert.equal((await db.collection('users').get()).size,accounts.length);
});
test('rules deny stale or missing admin claim on private admin records and drafts',async()=>{
 await createProgram({status:'draft'},'private-draft');
 const missing=env.authenticatedContext('admin-1',{email_verified:true}).firestore();
 await assertFails(getDoc(doc(missing,'programs/private-draft')));
 const valid=env.authenticatedContext('admin-1',{email_verified:true,role:'admin'}).firestore();await assertSucceeds(getDoc(doc(valid,'programs/private-draft')));
 await db.doc('users/admin-1').update({role:'participant'});await assertFails(getDoc(doc(valid,'programs/private-draft')));
});

test('notes-only edits preserve legacy coach references; assigning new staff still validates roles',async()=>{
 const c=consoleService();await c.saveSession(admin,{eventId:'legacy-staff',changes:adminSession()});
 await db.doc('events/legacy-staff').update({coachUids:['retired-seed-coach'],coachNames:['Historic coach'],requiredFormIds:['legacy-missing-form']});
 await c.saveSession(admin,{eventId:'legacy-staff',revision:1,changes:{notes:'Administrative note'}});
 assert.deepEqual((await db.doc('events/legacy-staff').get()).data().coachNames,['Historic coach']);
 await rejects(()=>c.saveSession(admin,{eventId:'legacy-staff',revision:2,changes:{coachUids:['retired-seed-coach']}}),'invalid-coach');
});
test('demo cleanup includes marked programs/venues and refuses to orphan non-demo records',async()=>{
 const c=consoleService();await createProgram({},'demo-parent');await db.doc('programs/demo-parent').update({isDemo:true});
 await c.saveSession(admin,{eventId:'real-child',changes:{...adminSession(),programId:'demo-parent',isDemo:false}});
 const preview=await c.demo(admin,{});assert.equal(preview.counts.programs,1);
 await rejects(()=>c.demo(admin,{apply:true,expectedPaths:preview.paths}),'demo-in-use');
 await db.doc('events/real-child').update({isDemo:true});
 await db.doc('venues/demo-venue').set({isDemo:true,name:'Test only'});
 const next=await c.demo(admin,{});assert.equal(next.count,3);await c.demo(admin,{apply:true,expectedPaths:next.paths});assert.equal((await db.collection('demoRemovalBackups').get()).size,3);
});

test('program quick edits preserve historic staff references while new assignments are validated',async()=>{
 await createProgram();await db.doc('programs/program-one').update({coachUids:['historic-coach'],coachNames:['Former coach']});
 const old=(await db.doc('programs/program-one').get()).data();
 const value=Object.fromEntries(Object.entries(old).filter(([k])=>['name','sport','status','venue','timezone','scheduleText','coachUids','coachNames','notes','photoUrl','capacity','registrationStatus'].includes(k)));
 await catalogue.saveProgram(admin,{programId:'program-one',revision:1,program:{...value,notes:'New program note'}});
 await rejects(()=>catalogue.saveProgram(admin,{programId:'program-one',revision:2,program:{...value,coachUids:['unknown-staff']}}),'invalid-coach');
});

test('editing a standalone legacy session preserves its older-install RSVP policy',async()=>{
 const c=consoleService();await c.saveSession(admin,{eventId:'legacy-policy',changes:adminSession()});
 await db.doc('events/legacy-policy').update({catalogueManaged:false});
 await c.saveSession(admin,{eventId:'legacy-policy',revision:1,changes:{notes:'An ordinary edit'}});
 assert.equal((await db.doc('events/legacy-policy').get()).data().catalogueManaged,false);
});

test('Google-created member can set a password through the reset email on the same UID',async()=>{
 const {initializeApp:clientApp,deleteApp:deleteClient}=await import('firebase/app'),A=await import('firebase/auth');
 const client=clientApp({apiKey:'demo-key',projectId:'demo-rally4ever',appId:'demo-reset-auth'},'google-reset-link'),auth=A.getAuth(client);A.connectAuthEmulator(auth,'http://127.0.0.1:23999',{disableWarnings:true});
 const email='google-reset@example.test',password='Reset-app-password-123!';
 const token=Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:'google-reset',email,email_verified:true})).toString('base64url')+'.';
 try{const first=await A.signInWithCredential(auth,A.GoogleAuthProvider.credential(token)),uid=first.user.uid;await db.doc(`users/${uid}`).set(profile({uid,email,role:'participant'},Timestamp.now()));await db.doc(`rsvps/preserved_${uid}`).set({uid,eventId:'preserved',cancelledAt:null});await A.signOut(auth);await A.sendPasswordResetEmail(auth,email);
 const codes=await(await fetch('http://127.0.0.1:23999/emulator/v1/projects/demo-rally4ever/oobCodes')).json(),code=codes.oobCodes.filter(c=>c.email===email&&c.requestType==='PASSWORD_RESET').at(-1);assert.ok(code);await A.confirmPasswordReset(auth,code.oobCode,password);assert.equal((await A.signInWithEmailAndPassword(auth,email,password)).user.uid,uid);await A.signOut(auth);assert.equal((await A.signInWithCredential(auth,A.GoogleAuthProvider.credential(token))).user.uid,uid);assert.equal((await db.doc(`rsvps/preserved_${uid}`).get()).exists,true);
 }finally{await deleteClient(client);}
});

test('photo edits use revision, allow started sessions, retain venue inheritance and require admin',async()=>{
 const c=consoleService();await c.saveSession(admin,{eventId:'photo-session',changes:adminSession()});
 const ref=db.doc('events/photo-session');await ref.update({startsAt:Timestamp.fromMillis(now-3600000),venueId:'photo-venue'});
 await rejects(()=>c.setPhoto(who('participant-1'),{kind:'session',id:ref.id,revision:1,mode:'none'}),'admin-claim-required');
 const result=await c.setPhoto(admin,{kind:'session',id:ref.id,revision:1,mode:'none'});assert.equal(result.revision,2);assert.equal((await ref.get()).data().photoMode,'none');
 await rejects(()=>c.setPhoto(admin,{kind:'session',id:ref.id,revision:1,mode:'venue'}),'stale-session');
 await c.setPhoto(admin,{kind:'session',id:ref.id,revision:2,mode:'venue'});assert.equal((await ref.get()).data().photoMode,'venue');
 const url='https://firebasestorage.googleapis.com/v0/b/rally4ever-3adaf.firebasestorage.app/o/sessions%2Fphoto-session%2F123.jpg?alt=media';
 await c.setPhoto(admin,{kind:'session',id:ref.id,revision:3,mode:'override',photoUrl:url});assert.equal((await ref.get()).data().photoUrl,url);
 await rejects(()=>c.setPhoto(admin,{kind:'session',id:ref.id,revision:4,mode:'override',photoUrl:url.replace('photo-session','someone-else')}),'photo-path');
 await db.doc('events/inherited-photo').set({...adminSession(),venueId:'photo-venue',photoUrl:'old-venue',venue:{...adminSession().venue,photoUrl:'old-venue'},startsAt:Timestamp.fromMillis(now-1000)});
 const venue={...adminSession().venue,code:'photo-venue',photoUrl:'https://example.test/venue.jpg',isDemo:false};
 await c.saveVenue(admin,{venueId:'photo-venue',revision:0,venue});
 assert.equal((await ref.get()).data().photoUrl,url,'Venue edits preserve explicit session photos');
 assert.equal((await ref.get()).data().venue.photoUrl,venue.photoUrl);
 const inherited=(await db.doc('events/inherited-photo').get()).data();assert.equal(inherited.photoUrl,'');assert.equal(inherited.photoMode,'venue');assert.equal(inherited.venue.photoUrl,venue.photoUrl);
 const audits=await db.collection('catalogueAudits').where('kind','==','session-photo').get();assert.equal(audits.size,3);
});

const {AdminManagementService}=require('./lib/admin_management');
const management=()=>new AdminManagementService(consoleService());
async function deletionFixture(){
 await createProgram();
 const base={programId:'program-one',name:'Community tennis',sport:'tennis',venue:program().venue,timezone:'Australia/Sydney',status:'published',registrationStatus:'open',capacity:null,coachUids:['coach-1'],bookedCount:0,revision:1};
 for(const [key,offset]of [['g-program-one-future',86400000],['gen-program-one-past',-86400000],['manual-future',172800000]])await db.doc('events/'+key).set({...base,startsAt:Timestamp.fromMillis(now+offset),endsAt:Timestamp.fromMillis(now+offset+3600000)});
}
const deletionRequest={programId:'program-one',operation:'delete',confirmation:'Community tennis',revision:1};
test('program soft delete previews counts, preserves data, hides legacy coach queries and restores',async()=>{
 await deletionFixture();const m=management(),beforeProfiles=(await db.collection('users').get()).docs.map(d=>d.data());
 const preview=await m.programDeletion(admin,{programId:'program-one',operation:'preview'});assert.equal(preview.futureGenerated,1);assert.equal(preview.retainedSessions,2);assert.equal(preview.allowed,true);
 await rejects(()=>m.programDeletion(admin,{...deletionRequest,confirmation:'Wrong name'}),'confirmation-mismatch');
 await m.programDeletion(admin,deletionRequest);
 const p=(await db.doc('programs/program-one').get()).data();assert.equal(p.status,'deleted');assert.equal(p.deletedBy,'admin-1');assert.ok(p.deletedAt instanceof Timestamp);
 const future=(await db.doc('events/g-program-one-future').get()).data(),past=(await db.doc('events/gen-program-one-past').get()).data();assert.ok(future.deletedAt);assert.ok(past.hiddenAt);assert.equal(past.deletedAt,undefined);assert.deepEqual(future.coachUids,[]);
 assert.equal((await consoleService().catalogue(admin,{})).programs.length,0);assert.equal((await consoleService().catalogue(admin,{includeDeleted:true})).programs.length,1);
 const {StaffService}=require('./lib/staff');assert.equal((await new StaffService(catalogue.service).listStaffSessions(who('coach-1','coach'),{})).events.length,0);
 const member=env.authenticatedContext('participant-1',{email_verified:true,role:'participant'}).firestore(),coach=env.authenticatedContext('coach-1',{email_verified:true,role:'coach'}).firestore();
 await assertFails(getDoc(doc(member,'programs/program-one')));await assertFails(getDoc(doc(coach,'events/g-program-one-future')));
 await assertSucceeds(getDocs(query(collection(coach,'events'),where('coachUids','array-contains','coach-1'))));
 await rejects(()=>catalogue.saveProgram(admin,{programId:'program-one',revision:2,program:program()}),'program-deleted');
 await m.programDeletion(admin,{programId:'program-one',operation:'restore',revision:2});
 assert.equal((await db.doc('programs/program-one').get()).data().status,'active');assert.equal((await db.doc('events/g-program-one-future').get()).data().deletedAt,null);assert.deepEqual((await db.doc('events/manual-future').get()).data().coachUids,['coach-1']);
 assert.deepEqual((await db.collection('users').get()).docs.map(d=>d.data()),beforeProfiles);assert.equal((await db.collection('catalogueAudits').where('kind','in',['program-soft-delete','program-restore']).get()).size,2);
});
for(const [collectionName,fields]of [['rsvps',{cancelledAt:Timestamp.now()}],['checkins',{status:'rejected'}],['attendance',{status:'confirmed'}],['feedback',{rating:4}]])test('delete is blocked by any '+collectionName+' history, including cancelled/rejected',async()=>{
 await deletionFixture();await db.doc(`${collectionName}/history`).set({eventId:'gen-program-one-past',uid:'participant-1',...fields});
 const preview=await management().programDeletion(admin,{programId:'program-one',operation:'preview'});assert.equal(preview.allowed,false);
 await rejects(()=>management().programDeletion(admin,deletionRequest),'program-has-attendance');assert.equal((await db.doc('programs/program-one').get()).data().deletedAt,undefined);assert.equal((await db.doc(`${collectionName}/history`).get()).exists,true);
});
test('deletion requires admin claim and protected admin profile; stale revisions do not write',async()=>{
 await deletionFixture();for(const role of ['participant','coach'])await rejects(()=>management().programDeletion(who('participant-1',role),deletionRequest),'admin-claim-required');
 await rejects(()=>management().programDeletion(who('participant-1','admin'),deletionRequest),'admin-required');await rejects(()=>management().programDeletion(admin,{...deletionRequest,revision:0}),'stale-program');
 const anonymous=env.unauthenticatedContext().firestore();await assertFails(setDoc(doc(anonymous,'programs/program-one'),{deletedAt:serverTimestamp()},{merge:true}));
});
test('concurrent reservation and deletion cannot orphan an RSVP',async()=>{
 await deletionFixture();const results=await Promise.allSettled([management().programDeletion(admin,deletionRequest),catalogue.setRsvp(who('participant-1'),{eventId:'g-program-one-future'})]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);const p=(await db.doc('programs/program-one').get()).data(),r=await db.doc('rsvps/g-program-one-future_participant-1').get();assert.equal(!!p.deletedAt,r.exists===false);
});
test('automatic venue codes are deterministic and append a unique suffix, including concurrent creates',async()=>{
 const v={...program().venue,name:'Armidale Tennis Centre',state:'NSW',code:'',photoUrl:'',isDemo:true},c=consoleService();
 const first=await c.saveVenue(admin,{venueId:'venue-auto-1',revision:0,venue:v});assert.equal(first.code,'armidale-tennis-centre-nsw');
 const rest=await Promise.all(['venue-auto-2','venue-auto-3'].map(venueId=>c.saveVenue(admin,{venueId,revision:0,venue:v})));assert.deepEqual(rest.map(r=>r.code).sort(),['armidale-tennis-centre-nsw-2','armidale-tennis-centre-nsw-3']);
});
test('person history combines RSVPs and scans, paginates without duplicates, and requires admin',async()=>{
 const writes=[];for(let i=0;i<60;i++){const eventId='history-'+String(i).padStart(3,'0');writes.push(db.doc('events/'+eventId).set({name:'Program '+i,venue:program().venue,timezone:'Australia/Sydney',startsAt:Timestamp.fromMillis(now+i*3600000)}),db.doc(`rsvps/${eventId}_participant-1`).set({uid:'participant-1',eventId,cancelledAt:null}));if(i<3)writes.push(db.doc(`checkins/${eventId}_participant-1`).set({uid:'participant-1',eventId,status:'confirmed',scannedAt:Timestamp.now(),distanceM:42,confirmedBy:'coach-1'}));}await Promise.all(writes);
 const a=await management().personAttendance(admin,{uid:'participant-1'}),b=await management().personAttendance(admin,{uid:'participant-1',cursor:a.cursor});assert.equal(a.rows.length,50);assert.equal(b.rows.length,10);assert.equal(b.cursor,null);assert.equal(new Set([...a.rows,...b.rows].map(r=>r.eventId)).size,60);assert.equal(a.rows[0].confirmedBy,'coach-1');
 const counts=await management().attendanceCounts(admin,{eventIds:['history-000']});assert.deepEqual(counts.counts['history-000'],{registered:1,checkedIn:1,limited:false});
 await rejects(()=>management().personAttendance(who('participant-1'),{uid:'participant-1'}),'admin-claim-required');
});
test('name/email search has bounded pages, includes guests and excludes merged profiles',async()=>{
 await db.doc('users/priya-search').set({firstName:'Priya',lastName:'Lal',emailLower:'priya@example.test',mergedInto:null});await db.doc('users/merged-search').set({firstName:'Priya',mergedInto:'priya-search'});await db.doc('guests/guest-priya').set({firstName:'Priya',emailLower:'visitor@example.test'});
 const page=await management().findPeople(admin,{search:'PRIYA'});assert.equal(page.people.length,1);assert.equal(page.people[0].uid,'priya-search');assert.equal(page.cursor.collection,'guests');const guests=await management().findPeople(admin,{search:'priya',cursor:page.cursor});assert.equal(guests.people[0].guest,true);assert.equal(guests.cursor,null);
});
test('venue geocoding identifies application, caches results and denies parallel or non-admin lookups',async()=>{
 let requestCount=0,release,started;const onStarted=new Promise(r=>started=r),hold=new Promise(r=>release=r);
 const m=new AdminManagementService(consoleService(),async(url,options)=>{requestCount++;assert.match(options.headers['User-Agent'],/Rally4Ever/);assert.equal(url.searchParams.get('countrycodes'),'au');started();await hold;return new Response(JSON.stringify([{lat:'-33.88',lon:'151.196',display_name:'Ultimo, NSW'}]),{headers:{'content-type':'application/json'}});});
 const address={address:'40 William Henry Street',suburb:'Ultimo',state:'NSW',postcode:'2007'};
 await rejects(()=>m.coordinates(who('participant-1'),address),'admin-claim-required');const first=m.coordinates(admin,address);await onStarted;await rejects(()=>m.coordinates(admin,{...address,address:'Another address'}),'geocoder-busy');release();const result=await first;assert.equal(result.results[0].lat,-33.88);assert.equal((await m.coordinates(admin,address)).cached,true);assert.equal(requestCount,1);
});
