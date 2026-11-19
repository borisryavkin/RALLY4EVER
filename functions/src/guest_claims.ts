import {Firestore,Timestamp} from 'firebase-admin/firestore';
import {hash} from './domain';
// Email is supplied only after authoritative Firebase ownership verification.
// Copy disjoint attendance and keep original scans with a forwarding marker.
// Conflicts are retained in place for admin review; never overwrite either scan.
export async function claimGuestAttendance(db:Firestore,targetUid:string,email:string,at:Timestamp){
 const sourceUid='guest-'+hash(email).slice(0,40);
 return db.runTransaction(async tx=>{
  const key=db.doc(`guestEmailIdentities/${email}`),mapping=await tx.get(key),source=await tx.get(db.doc(`guests/${sourceUid}`));
  if(!mapping.exists||!source.exists||mapping.data()!.uid===targetUid)return {copied:0,conflicts:[]};
  if(mapping.data()!.uid!==sourceUid||source.data()!.emailLower!==email)return {copied:0,conflicts:['identity-mismatch']};
  const found=await tx.get(db.collection('checkins').where('uid','==',sourceUid).limit(101));
  if(found.size>100){tx.set(db.doc(`guestClaimAudits/${sourceUid}_${targetUid}`),{sourceUid,targetUid,status:'review-required',reason:'too-many-records',createdAt:at});return {copied:0,conflicts:['too-many-records']};}
  const moves=[],conflicts=[];
  for(const old of found.docs){if(old.data().mergedInto)continue;const dest=db.doc(`checkins/${old.data().eventId}_${targetUid}`),existing=await tx.get(dest);if(existing.exists)conflicts.push(old.id);else moves.push({old,dest});}
  for(const {old,dest} of moves){tx.create(dest,{...old.data(),uid:targetUid,mergedFromGuestUid:sourceUid});tx.update(old.ref,{mergedInto:dest.path,mergedAt:at});}
  tx.update(source.ref,{mergedInto:targetUid,updatedAt:at});tx.update(key,{uid:targetUid,updatedAt:at});
  tx.set(db.doc(`guestClaimAudits/${sourceUid}_${targetUid}`),{sourceUid,targetUid,copied:moves.length,conflicts,status:conflicts.length?'review-required':'claimed',createdAt:at});
  return {copied:moves.length,conflicts};
 });
}
