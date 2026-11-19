import {requiredForms,optionalForms,publishedForm,formBody} from './forms';
import {claimGuestAttendance} from './guest_claims';
import {authEmulatorOrigin} from './emulator_network';
import {randomBytes} from 'node:crypto';
import {DocumentData,Timestamp,Transaction} from 'firebase-admin/firestore';
import {AttendanceService} from './service';
import {input,normalizeEmail,text,id,coordinate,checkDistance,secretMatches,fail,hash} from './domain';
import {rateLimit} from './rate_limits';

export const CHECKIN_ORIGIN='https://rally4ever-checkin-3adaf.web.app';
export class NoAppService {
 constructor(readonly service:AttendanceService){}
 async validateTx(tx:Transaction,d:DocumentData,infoOnly=false){
  const code=id(d.eventCode,'eventCode'),secret=text(d.secret,'secret',128);
  const q=await tx.get(this.service.db.collection('events').where('code','==',code).limit(2));
  if(q.size!==1)fail('not-found','event-not-found','Session not found');
  const e=q.docs[0].data(),eventId=q.docs[0].id;
  if(!Array.isArray(e.requiredFormIds)||e.requiredFormIds.length>10)fail('failed-precondition','invalid-event','Session agreements are not configured correctly');
  if(e.status!=='published')fail('failed-precondition','event-unavailable','Session is unavailable');
  if(!infoOnly)this.service.window(e);
  const k=(await tx.get(this.service.db.doc(`eventSecrets/${eventId}`))).data();
  if(!k||k.expiresAt.toMillis()<=this.service.now()||!secretMatches(secret,k.currentSecretHash))fail('permission-denied','invalid-secret','This code expired. Scan the current coach QR.');
  if(!infoOnly){checkDistance(coordinate(d.lat,'lat'),coordinate(d.lng,'lng'),coordinate(e.venue?.lat,'lat'),coordinate(e.venue?.lng,'lng'),e.geofenceRadiusM??150);}
  return {e,eventId};
 }
 async validate(d:DocumentData){return this.service.db.runTransaction(tx=>this.validateTx(tx,d));}
 async info(value:unknown,ip:string){const d=input(value,['eventCode','secret','lat','lng']);await this.limit('noapp-info',ip,30,60000);return this.service.db.runTransaction(async tx=>{const {e,eventId}=await this.validateTx(tx,d,true),forms=[];for(const formId of [...requiredForms(e),...optionalForms.filter(f=>!requiredForms(e).includes(f))]){const f=await tx.get(this.service.db.doc(`forms/${id(formId,'formId')}`));if(!publishedForm(f.data(),this.service.now())){if(requiredForms(e).includes(formId))fail('failed-precondition','form-unavailable','A required agreement is missing or unpublished. Ask the coach.');else continue;}const p=f.data()!;forms.push({id:formId,title:p.title??formId,body:formBody(p),content:formBody(p),version:p.version,formType:p.formType??formId,required:requiredForms(e).includes(formId)});}return {eventId,name:e.name,venue:{name:e.venue.name,suburb:e.venue.suburb},startsAt:e.startsAt.toDate().toISOString(),endsAt:e.endsAt.toDate().toISOString(),opensAt:new Date(e.startsAt.toMillis()-600000).toISOString(),timezone:e.timezone,forms};});}
 async limit(type:string,key:string,count:number,window:number){await rateLimit(this.service.db,type,key,count,window,this.service.now());}
 async authAccount(email:string){try{return await this.service.auth.getUserByEmail(email);}catch(e){if((e as {code?:string}).code!=='auth/user-not-found')throw e;return null;}}
 authEndpoint(path:string){if(process.env.FUNCTIONS_EMULATOR==='true')return `${authEmulatorOrigin()}/identitytoolkit.googleapis.com/v1/accounts:${path}?key=demo-api-key`;if(!process.env.NO_APP_API_KEY)fail('failed-precondition','email-link-unconfigured','Ask the coach to check in manually; email verification is not configured');return `https://identitytoolkit.googleapis.com/v1/accounts:${path}?key=${process.env.NO_APP_API_KEY}`;}
 async begin(value:unknown,ip:string){
  const d=input(value,['email','eventCode','secret','lat','lng','firstName','mobile','emergencyContact','injuries','signedVersions','deferCompletion']);
  const email=normalizeEmail(d.email);text(d.firstName,'name',100);await this.limit('noapp-ip',ip,10,60000);await this.limit('noapp-email-start',email,10,3600000);const {e}=await this.validate(d);
  const signedVersions=input(d.signedVersions??{},[...requiredForms(e),...optionalForms]);
  for(const version of Object.values(signedVersions))if(!(Number.isInteger(version)&&Number(version)>0 || typeof version==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(version)))fail('invalid-argument','invalid-form-version','Invalid agreement version');
  const account=await this.authAccount(email),mapping=(await this.service.db.doc(`emailIdentities/${email}`).get()).data();
  if(account?.disabled)fail('permission-denied','account-unavailable','Ask the coach for help with this email');
  // Never attach a typed email to a member UID, or sign forms for that member,
  // without ownership proof. New guests get no Auth user and no users/profile.
  if(mapping && (!account||mapping.uid!==account.uid))fail('failed-precondition','identity-conflict','Ask an admin to review the existing email identity');
  const requestId=randomBytes(24).toString('hex'),secret=d.secret, safe={email,eventCode:d.eventCode,lat:d.lat,lng:d.lng,firstName:text(d.firstName,'name',100),signedVersions};
  await this.service.db.doc(`noAppRequests/${requestId}`).create({email,expectedUid:account?.uid??null,data:safe,secretHash:hash(secret as string),createdAt:this.service.stamp(),expiresAt:Timestamp.fromMillis(this.service.now()+900000),consumed:false});
  if(account){
   await this.limit('noapp-email',email,3,3600000);
   const response=await fetch(this.authEndpoint('sendOobCode'),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({requestType:'EMAIL_SIGNIN',email,continueUrl:`${CHECKIN_ORIGIN}/c/${d.eventCode}?k=${secret}&noAppRequest=${requestId}`,canHandleCodeInApp:true})});
   if(!response.ok)fail('unavailable','email-link-failed','Unable to send a verification link. Ask the coach or try later.');
   return {status:'verification-required',requestId};
  }
  if(d.deferCompletion===true)return {status:'ready',requestId};
  // Preserve the existing native no-app client's one-call contract.
  return this.complete({requestId,secret},ip);
 }
 async complete(value:unknown,ip:string){
  const d=input(value,['requestId','oobCode','secret','lat','lng']);await this.limit('noapp-complete',ip,10,60000);
  const ref=this.service.db.doc(`noAppRequests/${id(d.requestId,'requestId')}`),request=(await ref.get()).data();
  if(!request||request.consumed||request.expiresAt.toMillis()<=this.service.now())fail('failed-precondition','verification-expired','This request expired or was already used. Scan again.');
  const secret=text(d.secret,'secret',128);if(hash(secret)!==request.secretHash)fail('permission-denied','invalid-secret','Use the QR that started this request');
  let verifiedUid:string|undefined;
  if(request.expectedUid){
   await this.limit('noapp-verify',ip,5,60000);
   const account=await this.authAccount(request.email);if(!account||account.disabled||account.uid!==request.expectedUid)fail('failed-precondition','identity-conflict','The account changed; ask the coach for help');
   const response=await fetch(this.authEndpoint('signInWithEmailLink'),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:request.email,oobCode:text(d.oobCode,'oobCode',2048)})});
   if(!response.ok)fail('permission-denied','verification-invalid','This email link is invalid or already used. Request another.');
   const proof=await response.json() as {localId:string,email:string};
   const current=await this.service.auth.getUser(proof.localId);
   if(proof.localId!==request.expectedUid||!current.emailVerified||normalizeEmail(current.email)!==request.email)fail('permission-denied','verification-invalid','Email verification failed');
   verifiedUid=proof.localId;
  }else if(await this.authAccount(request.email))fail('failed-precondition','verification-required','An account now exists for this email. Scan again to verify ownership.');
  if(verifiedUid)await claimGuestAttendance(this.service.db,verifiedUid,request.email,this.service.stamp());
  const data={...request.data,secret,...(d.lat!==undefined?{lat:d.lat,lng:d.lng}:{})};
  return this.service.db.runTransaction(async tx=>{
   const fresh=(await tx.get(ref)).data();if(!fresh||fresh.consumed||fresh.expiresAt.toMillis()<=this.service.now())fail('failed-precondition','verification-expired','Scan again to start a new request');
   const {e,eventId}=await this.validateTx(tx,data);
   const email=request.email,guestUid='guest-'+hash(email).slice(0,40),participantUid=verifiedUid??guestUid;
   const mapping=await tx.get(this.service.db.doc(`emailIdentities/${email}`));
   if(mapping.exists&&mapping.data()!.uid!==participantUid)fail('failed-precondition','identity-conflict','Use the canonical account or ask an admin');
   const profile=verifiedUid?await tx.get(this.service.db.doc(`users/${verifiedUid}`)):null;
   if(profile?.exists&&profile.data()!.mergedInto!==null)fail('failed-precondition','identity-conflict','This profile needs admin review');
   const scanRef=this.service.db.doc(`checkins/${eventId}_${participantUid}`),old=await tx.get(scanRef);
   if(old.exists)fail('already-exists','already-checked-in','You are already checked in',{checkinId:old.id,status:old.data()!.status});
   const versions=input(data.signedVersions??{},[...requiredForms(e),...optionalForms]),receipts=[];
   for(const formId of [...requiredForms(e),...optionalForms.filter(f=>versions[f]!==undefined&&!requiredForms(e).includes(f))]){const form=await tx.get(this.service.db.doc(`forms/${id(formId,'formId')}`)),consent=await tx.get(this.service.db.doc(`consents/${participantUid}_${formId}`));const f=form.data();if(!publishedForm(f,this.service.now()))fail('failed-precondition','form-unavailable','A required agreement is missing or unpublished. Ask the coach.');if(consent.data()?.version===f.version&&consent.data()?.formType===f.formType)continue;if(versions[formId]!==f.version)fail('failed-precondition','unsigned-forms','Read and accept each current agreement',{missingForms:[formId]});receipts.push({uid:participantUid,formId,formType:f.formType,version:f.version,signedAt:this.service.stamp()});}
   const rsvp=await tx.get(this.service.db.doc(`rsvps/${eventId}_${participantUid}`));
   const guestRef=this.service.db.doc(`guests/${participantUid}`),guest=await tx.get(guestRef);
   const firstName=text(data.firstName,'name',100),verification=verifiedUid?'email-link':'email-only',at=this.service.stamp();
   tx.set(guestRef,{uid:participantUid,emailLower:email,firstName,mergedInto:null,createdAt:guest.data()?.createdAt??at,updatedAt:at,identityVerification:verification},{merge:true});
   if(!verifiedUid)tx.set(this.service.db.doc(`guestEmailIdentities/${email}`),{uid:guestUid,emailLower:email,updatedAt:at});
   for(const c of receipts)tx.set(this.service.db.doc(`consents/${participantUid}_${c.formId}`),c);
   const distanceM=checkDistance(data.lat,data.lng,e.venue.lat,e.venue.lng,e.geofenceRadiusM??150);
   tx.create(scanRef,{eventId,uid:participantUid,guest:!profile?.exists,firstName,scannedAt:at,method:'camera',lat:data.lat,lng:data.lng,distanceM,status:'pending',confirmedBy:null,confirmedAt:null,walkIn:!rsvp.exists||rsvp.data()!.cancelledAt!==null,identityVerification:verification,corrections:[],eventEndsAt:e.endsAt,feedbackReminderPending:false});
   tx.update(ref,{consumed:true,verifiedAt:verifiedUid?at:null,checkinId:scanRef.id,eventId});
   return {status:'pending',checkinId:scanRef.id,eventId,verification,distanceM};
  });
 }
}
