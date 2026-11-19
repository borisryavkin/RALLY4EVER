// Recover one server-side demo-removal backup. Defaults to dry-run; never overwrites.
import {initializeApp,applicationDefault,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {requireRealStagingProject,projectId} from './seed-staging.mjs';
requireRealStagingProject();const args=process.argv.slice(2),apply=args.includes('--apply'),key=args.find(a=>!a.startsWith('--'));
if(!key||!/^[A-Za-z0-9-]+$/.test(key))throw Error('Usage: node scripts/restore-demo-record.mjs BACKUP_ID [--apply]');
const app=initializeApp({projectId,credential:applicationDefault()},'demo-restore');const db=getFirestore(app);
try{await db.runTransaction(async tx=>{const ref=db.doc('demoRemovalBackups/'+key),snap=await tx.get(ref),b=snap.data();if(!b||!b.before||! /^(events|programs|venues)\/[A-Za-z0-9-]+$/.test(b.path))throw Error('Unknown or unexpected backup; stopped');const target=db.doc(b.path);if((await tx.get(target)).exists)throw Error('Target already exists; refusing to overwrite');console.log(JSON.stringify({projectId,path:b.path,mode:apply?'apply':'dry-run',fieldCount:Object.keys(b.before).length}));if(apply){tx.create(target,b.before);tx.update(ref,{restoredAt:Timestamp.now()});}});}finally{await deleteApp(app);}
