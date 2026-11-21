// Remove only unmistakable bundled Waverley/aerial placeholders on demo sessions.
// A dry run is the default. No profiles, Auth users, or image objects are deleted.
import{initializeApp,applicationDefault,deleteApp}from'firebase-admin/app';
import{getFirestore,FieldValue}from'firebase-admin/firestore';
import{mkdir,writeFile}from'node:fs/promises';
import{requireRealStagingProject,projectId}from'./seed-staging.mjs';
requireRealStagingProject();const app=initializeApp({projectId,credential:applicationDefault()},'audit-demo-photos');const db=getFirestore(app);
try{
 const demo=(await db.collection('events').where('isDemo','==',true).get()).docs;
 const wrong=demo.filter(d=>/^(?:assets\/)?(?:wavley|waverley|aerial)[^/]*\.(?:jpg|jpeg|png|webp)$/i.test(d.data().photoUrl??''));
 const out={projectId,dryRun:!process.argv.includes('--apply'),demoSessions:demo.length,placeholdersToClear:wrong.map(d=>d.id),emptyPhotos:demo.filter(d=>!d.data().photoUrl).length};
 if(process.argv.includes('--apply')&&wrong.length){await mkdir('backups',{recursive:true});out.backup='backups/demo-photos-'+Date.now()+'.json';await writeFile(out.backup,JSON.stringify(wrong.map(d=>({path:d.ref.path,data:d.data()})),null,2),{mode:0o600});await db.runTransaction(async tx=>{const fresh=await tx.getAll(...wrong.map(d=>d.ref));for(let i=0;i<fresh.length;i++)if(fresh[i].updateTime.toMillis()!==wrong[i].updateTime.toMillis())throw Error('Concurrent edit; stopped');for(const d of fresh){tx.update(d.ref,{photoUrl:'',photoMode:'venue',revision:(d.data().revision??0)+1,updatedAt:FieldValue.serverTimestamp()});tx.create(db.collection('catalogueAudits').doc(),{kind:'demo-placeholder-photo',eventId:d.id,before:d.data(),createdAt:FieldValue.serverTimestamp()});}});}
 console.log(JSON.stringify(out,null,2));
}finally{await deleteApp(app);}
