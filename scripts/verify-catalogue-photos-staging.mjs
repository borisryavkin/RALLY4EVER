// Isolated real-project QA account/photo probe. Never changes existing users.
// The new QA account has its temporary admin role revoked and is disabled in finally; nothing is deleted.
import{initializeApp,applicationDefault,deleteApp}from'firebase-admin/app';
import{getAuth}from'firebase-admin/auth';import{getFirestore}from'firebase-admin/firestore';
import{readFile,writeFile,mkdir}from'node:fs/promises';import{createHash,randomBytes}from'node:crypto';
import{requireRealStagingProject,projectId}from'./seed-staging.mjs';
requireRealStagingProject();const app=initializeApp({projectId,credential:applicationDefault(),serviceAccountId:'firebase-adminsdk-fbsvc@rally4ever-3adaf.iam.gserviceaccount.com'},'photo-proof');
const db=getFirestore(app),auth=getAuth(app),config=JSON.parse(await readFile('config/staging.web.json','utf8')),apiKey=config.apiKey??config.FIREBASE_API_KEY;
if((config.projectId??config.FIREBASE_PROJECT_ID)!==projectId)throw Error('Config project mismatch');
const bucket='rally4ever-3adaf.firebasestorage.app',stamp=Date.now(),venueId='photo-proof-'+stamp,path='venues/'+venueId+'/'+stamp+'.jpg';
const objectUrl='https://firebasestorage.googleapis.com/v0/b/'+bucket+'/o/'+encodeURIComponent(path)+'?alt=media';
async function account(role){const docs=(await db.collection('users').where('role','==',role).get()).docs;for(const d of docs){if(d.data().mergedInto)continue;try{const u=await auth.getUser(d.id);if(u.disabled||!u.emailVerified||(role==='admin'&&u.customClaims?.role!=='admin'))continue;return {profile:d,auth:u};}catch{}}throw Error('No eligible existing '+role+' account');}
async function signIn(u){const r=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key='+apiKey,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:u.auth.email,password:qaPassword,returnSecureToken:true})});const j=await r.json();if(!r.ok)throw Error('Verification sign-in failed '+r.status);return j.idToken;}
async function call(name,data,token){const r=await fetch('https://australia-southeast1-'+projectId+'.cloudfunctions.net/'+name,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify({data})});const j=await r.json();return {http:r.status,body:j};}
const qaPassword=randomBytes(32).toString('base64url');let qaUid=null;let originalBackup;
try{
 const owner=await account('admin');
 originalBackup='backups/photo-probe-initial-'+stamp+'.json';await mkdir('backups',{recursive:true});await writeFile(originalBackup,JSON.stringify({projectId,createdAt:new Date().toISOString(),newQaEmail:'photo-probe-'+stamp+'@example.test',existingAuth:null,existingProfile:null,newVenuePath:'venues/'+venueId,newObjectPath:path},null,2),{mode:0o600});
 const qa=await auth.createUser({email:'photo-probe-'+stamp+'@example.test',password:qaPassword,emailVerified:true,displayName:'[QA] Photo permission verification'});qaUid=qa.uid;
 await auth.setCustomUserClaims(qaUid,{role:'participant'});
 await db.doc('users/'+qaUid).set({uid:qaUid,email:qa.email,emailLower:qa.email,firstName:'[QA] Photo permission verification',role:'participant',mergedInto:null,isDemo:true,createdAt:new Date(),updatedAt:new Date()});
 const participant={auth:await auth.getUser(qaUid),profile:await db.doc('users/'+qaUid).get()};
 const participantToken=await signIn(participant);
 const beforeRole='backups/photo-probe-role-before-'+stamp+'.json';await writeFile(beforeRole,JSON.stringify({projectId,uid:qaUid,profile:participant.profile.data(),auth:{customClaims:participant.auth.customClaims,disabled:participant.auth.disabled}},null,2),{mode:0o600});
 // Only this newly-created QA account receives a temporary test role.
 await auth.setCustomUserClaims(qaUid,{role:'admin'});await db.doc('users/'+qaUid).update({role:'admin',updatedAt:new Date()});
 await db.collection('roleAudits').add({uid:qaUid,actorUid:owner.auth.uid,oldRole:'participant',newRole:'admin',reason:'Isolated photo permission probe; revoked in finally',createdAt:new Date()});
 const admin={auth:await auth.getUser(qaUid),profile:await db.doc('users/'+qaUid).get()};
 const backup='backups/photo-proof-'+stamp+'.json';await mkdir('backups',{recursive:true});await writeFile(backup,JSON.stringify({projectId,createdAt:new Date().toISOString(),newVenuePath:'venues/'+venueId,newObjectPath:path,existingVenue:null,existingObject:null,accounts:[admin,participant].map(a=>({uid:a.auth.uid,profile:a.profile.data(),auth:{email:a.auth.email,emailVerified:a.auth.emailVerified,disabled:a.auth.disabled,customClaims:a.auth.customClaims,metadata:a.auth.metadata}}))},null,2),{mode:0o600});
 const adminToken=await signIn(admin),jpeg=await readFile('/tmp/demo-tennis-manly-morning.jpg');
 const upload=async token=>fetch('https://firebasestorage.googleapis.com/v0/b/'+bucket+'/o?uploadType=media&name='+encodeURIComponent(path),{method:'POST',headers:{authorization:'Firebase '+token,'content-type':'image/jpeg'},body:jpeg});
 const a=await upload(adminToken);if(!a.ok)throw Error('Admin upload failed '+a.status+' '+(await a.text()).slice(0,300));
 const denied=await upload(participantToken);if(denied.status!==403)throw Error('Expected participant upload 403, got '+denied.status);
 const pub=await fetch(objectUrl);if(!pub.ok)throw Error('Public image read failed '+pub.status);const bytes=Buffer.from(await pub.arrayBuffer());if(createHash('sha256').update(bytes).digest('hex')!==createHash('sha256').update(jpeg).digest('hex'))throw Error('Photo bytes changed after denied write');
 const venue={name:'Photo upload verification (demo)',code:'PHOTO-'+stamp,address:'Synthetic verification record',suburb:'Test',postcode:'2000',state:'NSW',lat:0,lng:0,photoUrl:'',isDemo:true};
 const create=await call('adminSaveVenue',{venueId,revision:0,venue},adminToken);if(create.http!==200)throw Error('Create QA venue failed '+JSON.stringify(create));
 const save=await call('adminSetPhoto',{kind:'venue',id:venueId,revision:1,mode:'override',photoUrl:objectUrl},adminToken);if(save.http!==200)throw Error('Save QA photo failed '+JSON.stringify(save));
 const reject=await call('adminSetPhoto',{kind:'venue',id:venueId,revision:2,mode:'none'},participantToken);if(reject.http!==403)throw Error('Participant callable unexpectedly allowed '+JSON.stringify(reject));
 const stored=(await db.doc('venues/'+venueId).get()).data();if(stored.photoUrl!==objectUrl||stored.revision!==2)throw Error('Photo/revision not persisted');
 const result={projectId,bucket,region:'australia-southeast1',backup,venueId,objectPath:path,adminUploadHttp:a.status,participantUploadHttp:denied.status,publicReadHttp:pub.status,adminSavePhotoHttp:save.http,participantSavePhotoHttp:reject.http,participantSavePhotoReason:reject.body.error?.details?.reason,revision:stored.revision,qaUid,qaAccountCreated:true,noExistingProfileOrAuthUserChanged:true,noProfileOrAuthUserDeleted:true};
 await writeFile('docs/verification/catalogue-photo-staging.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
 }finally{
 if(qaUid){
  const u=await auth.getUser(qaUid),p=await db.doc('users/'+qaUid).get();await writeFile('backups/photo-probe-before-revoke-'+stamp+'.json',JSON.stringify({projectId,uid:qaUid,profile:p.data(),auth:{customClaims:u.customClaims,disabled:u.disabled}},null,2),{mode:0o600});
  await auth.setCustomUserClaims(qaUid,{role:'participant'});await db.doc('users/'+qaUid).update({role:'participant',qaDisabled:true,updatedAt:new Date()});await auth.revokeRefreshTokens(qaUid);await auth.updateUser(qaUid,{disabled:true});
  await db.collection('roleAudits').add({uid:qaUid,oldRole:'admin',newRole:'participant',reason:'Photo probe complete; QA account disabled, retained for audit',createdAt:new Date()});
  console.log('QA account returned to participant, tokens revoked, account disabled; no deletion.');
 }
 await deleteApp(app);
}
