// Reviewed Humanitix occurrences only. Default dry-run, no deletion or broad matching.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {initializeApp,applicationDefault,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,FieldValue} from 'firebase-admin/firestore';
import {requireRealStagingProject,projectId} from './seed-staging.mjs';
export const sources=[
 {key:'ultimo',programId:'nsw-pickleball-ultimo',venueId:'humanitix-ultimo-community-centre',name:'Pickleball at Ultimo Community Centre',url:'https://events.humanitix.com/rally4ever-pickleball-at-ultimo-community-centre-snypragq',scheduleText:'Thursdays 11:30–12:30',first:'2026-11-26',weekday:4,hour:11,minute:30,venue:{name:'Ultimo Community Centre',address:'40 William Henry Street',suburb:'Ultimo',postcode:'2007',state:'NSW',lat:-33.878,lng:151.19776}},
 {key:'unsw',programId:'humanitix-unsw-pickleball',venueId:'humanitix-unsw-b5-court-1',name:'Pickleball at UNSW',url:'https://events.humanitix.com/copy-of-rally4ever-pickleball-at-unsw',scheduleText:'Tuesdays 13:00–14:00',first:'2026-11-24',weekday:2,hour:13,minute:0,venue:{name:'UNSW Fitness & Aquatic Centre (B5), Court 1',address:'Gate 2, High Street',suburb:'Kensington',postcode:'2052',state:'NSW',lat:-33.9151103,lng:151.2261372}},
];
export async function reviewedPlan(){return Promise.all(sources.map(async source=>{
 const occurrences=JSON.parse(await readFile(new URL('../docs/imports/humanitix-'+source.key+'.json',import.meta.url),'utf8'));
 const dates=new Set();for(const e of occurrences){const date=e.startDate.slice(0,10),start=new Date(e.startDate),end=new Date(e.endDate);const local=new Intl.DateTimeFormat('en-AU',{timeZone:'Australia/Sydney',weekday:'short',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(start);const expected=source.key==='ultimo'?'Thu 11:30':'Tue 13:00';if(e.url!==source.url||date<source.first||!Number.isFinite(start.getTime())||end-start!==3600000||local!==expected||dates.has(date))throw Error('Unexpected Humanitix occurrence: '+JSON.stringify({date,local,expected}));dates.add(date);}
 return {...source,occurrences};
}));}
export async function importHumanitix({apply=false}={}){
 requireRealStagingProject();const plan=await reviewedPlan();const app=initializeApp({projectId,credential:applicationDefault()},'humanitix-import-'+Date.now()),db=getFirestore(app);
 try{
 const all=(await db.collection('programs').get()).docs;
 for(const p of plan){const conflicts=all.filter(d=>d.id!==p.programId&&(d.data().sourceUrl===p.url||d.data().humanitixUrl===p.url));if(conflicts.length)throw Error('Duplicate source program: '+conflicts.map(d=>d.id));}
 const docs=[];
 for(const p of plan){const base={sport:'pickleball',timezone:'Australia/Sydney',venueId:p.venueId,venue:p.venue,requiredFormIds:['conduct','waiver'],isDemo:false,source:'humanitix',sourceUrl:p.url};
 docs.push({path:'venues/'+p.venueId,data:{...p.venue,code:'HX-'+p.key.toUpperCase(),isDemo:false,sourceUrl:p.url}});
 docs.push({path:'programs/'+p.programId,data:{...base,name:p.name,status:'active',scheduleText:p.scheduleText,coachUids:[],coachNames:[],notes:p.key==='unsw'?'For currently enrolled UNSW students only. Coach and capacity to be confirmed.':'Coach and capacity to be confirmed.',capacity:null,photoUrl:null}});
 for(const e of p.occurrences){const date=e.startDate.slice(0,10);docs.push({path:'events/hx-'+p.key+'-'+date,data:{...base,programId:p.programId,name:p.name,code:'hx-'+p.key+'-'+date,status:'published',registrationStatus:'open',startsAt:Timestamp.fromDate(new Date(e.startDate)),endsAt:Timestamp.fromDate(new Date(e.endDate)),capacity:null,bookedCount:0,coachUids:[],coachNames:[],geofenceRadiusM:150,photoUrl:null,notes:p.key==='unsw'?'For currently enrolled UNSW students only. Register each week.':'Register each week.',sourceOccurrence:e.startDate}});}}
 const refs=docs.map(d=>db.doc(d.path)),before=await db.getAll(...refs);
 for(let i=0;i<before.length;i++){const old=before[i].data();if(old&&docs[i].path.startsWith('events/')&&old.source!=='humanitix')throw Error('Unexpected existing session '+docs[i].path);if(old?.source==='humanitix'&&old.sourceUrl!==docs[i].data.sourceUrl)throw Error('Source conflict '+docs[i].path);}
 const summary={projectId,dryRun:!apply,programs:2,venues:2,sessions:docs.filter(d=>d.path.startsWith('events/')).length,create:before.filter(d=>!d.exists).length,update:before.filter(d=>d.exists).length,coordinates:plan.map(p=>({venue:p.venue.name,lat:p.venue.lat,lng:p.venue.lng})),dates:plan.map(p=>({program:p.name,count:p.occurrences.length,first:p.occurrences[0].startDate,last:p.occurrences.at(-1).startDate})),notes:['No statewide listings imported.','Capacity unknown; coaches unassigned.','UNSW postcode uses official facility 2052; Humanitix lists 2033.']};
 if(!apply)return summary;
 await mkdir('backups',{recursive:true});const backup='backups/humanitix-before-'+Date.now()+'.json';await writeFile(backup,JSON.stringify({projectId,documents:before.map(d=>({path:d.ref.path,exists:d.exists,data:d.data()??null}))},null,2),{mode:0o600});
 await db.runTransaction(async tx=>{const fresh=await tx.getAll(...refs);for(let i=0;i<fresh.length;i++)if(fresh[i].updateTime?.toMillis()!==before[i].updateTime?.toMillis())throw Error('Concurrent edit '+refs[i].path);for(let i=0;i<docs.length;i++){const old=before[i].data();if(old?.source==='humanitix')continue;const data={...docs[i].data,revision:(old?.revision??0)+1,updatedAt:FieldValue.serverTimestamp(),updatedBy:'import-humanitix-script'};if(!old)data.createdAt=FieldValue.serverTimestamp();if(old?.coachUids?.length){data.coachUids=old.coachUids;data.coachNames=old.coachNames??[];}tx.set(refs[i],data,{merge:true});tx.create(db.collection('catalogueAudits').doc(),{kind:docs[i].path.split('/')[0],documentPath:docs[i].path,actorUid:'import-humanitix-script',action:'humanitix-import',before:old??null,after:data,at:FieldValue.serverTimestamp()});}});
 return {...summary,backup};
 }finally{await deleteApp(app);}}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){if(process.argv.slice(2).some(a=>a!=='--apply'))throw Error('Use --apply only');console.log(JSON.stringify(await importHumanitix({apply:process.argv.includes('--apply')}),null,2));}
