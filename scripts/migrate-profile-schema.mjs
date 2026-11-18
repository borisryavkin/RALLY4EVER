#!/usr/bin/env node
import {pathToFileURL, fileURLToPath} from 'node:url';
import {resolve, relative} from 'node:path';
import {writeFile, readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
// Match the Functions Admin SDK instance, including its Timestamp/FieldValue types.
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const {initializeApp, applicationDefault, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
import {planProfileUpgrade} from './profile-schema.mjs';

function encode(value) {
  if (value instanceof Timestamp) return {$timestamp: [value.seconds, value.nanoseconds]};
  if (Array.isArray(value)) return value.map(encode);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,encode(v)]));
  return value;
}
function decode(value) {
  if (value?.$timestamp) return new Timestamp(...value.$timestamp);
  if (Array.isArray(value)) return value.map(decode);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,decode(v)]));
  return value;
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k,canonical(value[k])]));
  return value;
}
const digest = value => createHash('sha256').update(JSON.stringify(canonical(encode(value)))).digest('hex');

export async function migrateProfiles(db, {project, apply=false, backup, rollback}={}) {
  if (rollback) {
    if (!apply) throw new Error('Rollback requires explicit --apply and project confirmation');
    const saved=JSON.parse(await readFile(rollback,'utf8'));
    if(saved.project!==project || saved.version!==2) throw new Error('Backup project/version mismatch');
    let restored=0;
    for(const row of saved.rows) {
      const changed=await db.runTransaction(async tx=>{
        const user=db.doc(`users/${row.uid}`), contact=db.doc(`users/${row.uid}/private/contact`);
        const [p,c]=await Promise.all([tx.get(user),tx.get(contact)]);
        const currentHash=digest({profile:p.data(),contact:c.exists?c.data():null});
        if(currentHash===row.beforeHash)return false;
        if(currentHash!==row.afterHash) throw new Error('Rollback refused: data changed after migration');
        const before=decode(row.before);
        tx.set(user,before.profile);
        if(before.contact===null)tx.delete(contact);else tx.set(contact,before.contact);
        tx.set(db.collection('mergeAudits').doc(),{type:'profile-schema-v2-rollback',uid:row.uid,createdAt:FieldValue.serverTimestamp()});
        return true;
      });
      if(changed)restored++;
    }
    return {restored};
  }
  const users=await db.collection('users').limit(1001).get();
  if(users.size>1000) throw new Error('More than 1000 profiles: prepare a reviewed paginated migration');
  const counts={dryRun:!apply,total:users.size,upgrade:0,unchanged:0,merged:0,needsReview:0};
  const rows=[];
  for(const user of users.docs) {
    try {
      const c=await db.doc(`users/${user.id}/private/contact`).get();
      const before={profile:user.data(),contact:c.exists?c.data():null};
      if(before.profile.uid!==user.id)throw new Error('UID mismatch');
      const plan=planProfileUpgrade(before.profile,before.contact);
      if(plan.skipped){counts.merged++;continue;}
      if(!plan.changed){counts.unchanged++;continue;}
      counts.upgrade++;
      rows.push({uid:user.id,before:encode(before),beforeHash:digest(before),afterHash:digest({profile:plan.profile,contact:plan.contact})});
    } catch {counts.needsReview++;}
  }
  if(!apply)return counts;
  if(counts.needsReview)throw new Error('Migration refused: resolve all preview conflicts first');
  if(!backup)throw new Error('--backup is required before any writes');
  // Exclusive creation prevents overwriting a prior rollback snapshot.
  await writeFile(backup,JSON.stringify({version:2,project,rows},null,2),{flag:'wx',mode:0o600});
  for(const row of rows) {
    await db.runTransaction(async tx=>{
      const user=db.doc(`users/${row.uid}`), contact=db.doc(`users/${row.uid}/private/contact`);
      const [p,c]=await Promise.all([tx.get(user),tx.get(contact)]);
      const before={profile:p.data(),contact:c.exists?c.data():null};
      if(digest(before)!==row.beforeHash)throw new Error('Migration refused: profile changed since preview/backup');
      const plan=planProfileUpgrade(before.profile,before.contact);
      tx.set(user,plan.profile);tx.set(contact,plan.contact);
      tx.set(db.collection('mergeAudits').doc(),{type:'profile-schema-v2',uid:row.uid,beforeHash:row.beforeHash,afterHash:row.afterHash,createdAt:FieldValue.serverTimestamp()});
    });
  }
  return {...counts,applied:rows.length};
}

export function validateMigrationTarget(args, env=process.env) {
  const project=args.get('--project');
  if(project==='demo-rally4ever') {
    if(env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080' || env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' || env.GOOGLE_APPLICATION_CREDENTIALS) throw new Error('Explicit local demo emulators required');
  } else if(project==='rally4ever-3adaf' && args.has('--staging')) {
    if(Object.keys(env).some(k=>k.includes('EMULATOR') && env[k]))throw new Error('Staging refuses emulator environment');
  } else throw new Error('Explicit demo project or --staging --project rally4ever-3adaf required');
  if(args.has('--apply') && args.has('--dry-run'))throw new Error('Choose dry-run or apply, never both');
  if(args.has('--apply') && args.get('--confirm-project')!==project)throw new Error('--apply requires --confirm-project matching the target; obtain owner approval first');
  return project;
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  const args=new Map();
  for(const item of process.argv.slice(2)) {
    const [key,...value]=item.split('=');
    if(!['--project','--staging','--apply','--confirm-project','--backup','--rollback','--dry-run'].includes(key) || args.has(key))throw new Error('Unknown or duplicate migration option');
    if(['--apply','--staging','--dry-run'].includes(key) && value.length)throw new Error('Boolean flags must be bare, e.g. --apply');
    if(!['--apply','--staging','--dry-run'].includes(key) && (!value.length || !value.join('=')))throw new Error('Use --option=value for migration paths/project');
    args.set(key,value.length?value.join('='):true);
  }
  const project=validateMigrationTarget(args);
  for(const key of ['--backup','--rollback']) {
    if(args.has(key) && !relative(fileURLToPath(new URL('../',import.meta.url)),resolve(args.get(key))).startsWith('..'))throw new Error('Keep personal-data backups outside the repository');
  }
  const app=initializeApp({projectId:project,...(args.has('--staging')?{credential:applicationDefault()}:{})},'profile-schema-upgrade');
  try {
    console.log(JSON.stringify(await migrateProfiles(getFirestore(app),{project,apply:args.has('--apply'),backup:args.get('--backup'),rollback:args.get('--rollback')}),null,2));
  } finally {await deleteApp(app);}
}
