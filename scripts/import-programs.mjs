import {readFile,writeFile} from 'node:fs/promises';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {requireEmulators,projectId} from './emulator-env.mjs';
import {preparePrograms} from './program-catalogue.mjs';

const args=process.argv.slice(2);
if(args.some(a=>a!=='--apply-emulator' && !a.startsWith('--report=')))throw new Error('Use --apply-emulator and/or --report=/private/report.json. Default is dry-run.');
const files=['rally4ever_programs.json','nsw_programs.json'];
const sources=await Promise.all(files.map(async name=>({name,programs:JSON.parse(await readFile(new URL(`../assets/${name}`,import.meta.url),'utf8')).programs})));
const programs=preparePrograms(sources);
const report=args.find(a=>a.startsWith('--report='))?.slice('--report='.length);
if(report)await writeFile(report,JSON.stringify({dryRun:!args.includes('--apply-emulator'),programs},null,2)+'\n',{mode:0o600});
console.log({sourceEntries:sources.reduce((n,s)=>n+s.programs.length,0),programs:programs.length,withCoordinates:programs.filter(p=>p.venue.lat!=null).length,conflicts:programs.filter(p=>p.sourceConflicts.length).length,status:'draft; admin review required',mode:args.includes('--apply-emulator')?'emulator only':'dry-run; no Firebase requests'});
if(args.includes('--apply-emulator')){
  requireEmulators();const app=initializeApp({projectId},`catalogue-import-${Date.now()}`);
  try{
    const db=getFirestore(app);let created=0;
    for(const {id,...program} of programs){
      await db.runTransaction(async tx=>{
        const ref=db.doc(`programs/${id}`);if((await tx.get(ref)).exists)return;
        const stamp=Timestamp.now();tx.create(ref,{...program,createdAt:stamp,updatedAt:stamp,updatedBy:'emulator-import'});
        tx.create(db.collection('catalogueAudits').doc(),{kind:'program-import',programId:id,actorUid:'emulator-import',reason:'Review draft from existing bundled assets',createdAt:stamp});created++;
      });
    }
    console.log({created,skipped:programs.length-created});
  }finally{await deleteApp(app);}
}
