import {randomUUID} from 'node:crypto';
import {FieldPath, Timestamp} from 'firebase-admin/firestore';
import {AdminConsoleService, wire} from './admin_console';
import {Identity, input, id, text, fail, hash} from './domain';
import {uid} from './service';

/** Admin-only operations. Never remove participant, Auth, consent or attendance data. */
export class AdminManagementService {
  constructor(readonly console: AdminConsoleService, readonly fetcher: typeof fetch = fetch) {}
  get service() { return this.console.service; }
  async programDeletion(who: Identity, value: unknown) {
    const d=input(value,['programId','operation','confirmation','revision']);
    await this.console.requireAdmin(who);
    const programId=id(d.programId,'programId'), operation=d.operation;
    if(!['preview','delete','restore'].includes(operation as string)) fail('invalid-argument','invalid-operation','Choose preview, delete or restore');
    const {db}=this.service;
    return db.runTransaction(async tx=>{
      if((await this.service.actor(tx,who)).role!=='admin') fail('permission-denied','admin-required','Admin access has been revoked');
      const ref=db.doc(`programs/${programId}`),snap=await tx.get(ref),p=snap.data();
      if(!p) fail('not-found','program-not-found','Program not found');
      const sessions=await tx.get(db.collection('events').where('programId','==',programId).limit(301));
      if(sessions.size>300) fail('resource-exhausted','program-too-large','This program has more than 300 sessions. Archive it instead; deletion needs a reviewed batch.');
      if(operation==='restore') {
        if(!p!.deletedAt || !p!.deletion?.batchId) fail('failed-precondition','not-deleted','This program is not deleted');
        if(d.revision!==p!.revision) fail('aborted','stale-program','Reload this program before restoring');
        const batchId=p!.deletion.batchId, at=this.service.stamp();
        const restoring=sessions.docs.filter(e=>e.data().deletion?.batchId===batchId);
        for(const e of restoring) {
          const old=e.data(), previous=old.deletion;
          tx.update(e.ref,{status:previous.status,registrationStatus:previous.registrationStatus??'open',coachUids:previous.coachUids??[],deletedAt:null,deletedBy:null,hiddenAt:null,deletion:null,restoredAt:at,restoredBy:who.uid,updatedAt:at,revision:(old.revision??0)+1});
        }
        tx.update(ref,{status:p!.deletion.status,deletedAt:null,deletedBy:null,deletion:null,restoredAt:at,restoredBy:who.uid,updatedAt:at,revision:(p!.revision??0)+1});
        tx.create(db.collection('catalogueAudits').doc(),{kind:'program-restore',programId,actorUid:who.uid,createdAt:at,batchId,eventIds:restoring.map(e=>e.id)});
        return {programId,restoredSessions:restoring.length};
      }
      if(p!.deletedAt) fail('failed-precondition','already-deleted','This program is already deleted. Use Restore.');
      const counts:Record<string,number>={registrations:0,checkins:0,attendance:0,feedback:0};
      let limited=false;
      const ids=sessions.docs.map(e=>e.id);
      for(let i=0;i<ids.length;i+=30) {
        const found=await Promise.all(['rsvps','checkins','attendance','feedback'].map(c=>tx.get(db.collection(c).where('eventId','in',ids.slice(i,i+30)).limit(1001))));
        ['registrations','checkins','attendance','feedback'].forEach((k,j)=>{counts[k]+=found[j].size;limited ||= found[j].size===1001;});
      }
      const countMetadata=sessions.docs.some(e=>(e.data().bookedCount??0)>0 || (e.data().attendedCount??0)>0);
      const future=sessions.docs.filter(e=>e.data().startsAt?.toMillis()>this.service.now() && (/^(gen-|g-)/.test(e.id)||e.data().generated===true));
      const blocked=Object.values(counts).some(n=>n>0)||countMetadata;
      const preview={programId,name:p!.name,revision:p!.revision,allowed:!blocked,blocked,...counts,countsAreMinimum:limited,countMetadata,futureGenerated:future.length,retainedSessions:sessions.size-future.length,sessionCount:sessions.size};
      if(operation==='preview') return preview;
      if(d.confirmation!==p!.name) fail('invalid-argument','confirmation-mismatch','Type the complete program name to confirm');
      if(d.revision!==p!.revision) fail('aborted','stale-program','Reload this program before deleting');
      if(blocked) fail('failed-precondition','program-has-attendance','This program has registrations or attendance history. Archive it instead.',preview);
      const at=this.service.stamp(),batchId=randomUUID(),futureIds=new Set(future.map(e=>e.id));
      // Future generated sessions become tombstones. Older/manual sessions are
      // retained but hidden. Clearing only their active assignment array keeps
      // legacy coach array-contains queries working without a data migration.
      for(const e of sessions.docs) {
        const old=e.data();
        tx.update(e.ref,{status:'deleted',registrationStatus:'closed',coachUids:[],...(futureIds.has(e.id)?{deletedAt:at,deletedBy:who.uid}:{hiddenAt:at}),deletion:{batchId,status:old.status,registrationStatus:old.registrationStatus??'open',coachUids:old.coachUids??[]},updatedAt:at,revision:(old.revision??0)+1});
      }
      tx.update(ref,{status:'deleted',deletedAt:at,deletedBy:who.uid,deletion:{batchId,status:p!.status},updatedAt:at,revision:(p!.revision??0)+1});
      tx.create(db.collection('catalogueAudits').doc(),{kind:'program-soft-delete',programId,actorUid:who.uid,createdAt:at,batchId,previousStatus:p!.status,deletedSessionIds:future.map(e=>e.id),retainedHiddenSessionIds:sessions.docs.filter(e=>!futureIds.has(e.id)).map(e=>e.id)});
      return {...preview,batchId,deleted:true};
    });
  }
  async attendanceCounts(who:Identity,value:unknown) {
    const d=input(value,['eventIds']);await this.console.requireAdmin(who);
    if(!Array.isArray(d.eventIds)||d.eventIds.length>24) fail('invalid-argument','invalid-page','Choose up to 24 sessions');
    const rows=await Promise.all(d.eventIds.map(async raw=>{
      const key=id(raw,'eventId'),{db}=this.service;
      const [rsvps,scans]=await Promise.all([db.collection('rsvps').where('eventId','==',key).select('cancelledAt').limit(2001).get(),db.collection('checkins').where('eventId','==',key).select('mergedInto').limit(2001).get()]);
      return [key,{registered:rsvps.docs.filter(r=>r.data().cancelledAt==null).length,checkedIn:scans.docs.filter(r=>!r.data().mergedInto).length,limited:rsvps.size===2001||scans.size===2001}];
    }));return {counts:Object.fromEntries(rows)};
  }
  async findPeople(who:Identity,value:unknown) {
    const d=input(value,['search','cursor']);await this.console.requireAdmin(who);
    const search=text(d.search,'search',150,2).toLowerCase();
    const cursor=d.cursor===undefined?null:input(d.cursor,['collection','id']);
    const source=cursor?.collection??'users';if(!['users','guests'].includes(source as string))fail('invalid-argument','invalid-cursor','Search again');
    let q=this.service.db.collection(source as string).orderBy(FieldPath.documentId()).limit(201);
    if(cursor?.id)q=q.startAfter(uid(cursor.id));
    const found=await q.get(),scanned=found.docs.slice(0,200);
    const people=scanned.filter(r=>!r.data().mergedInto && `${r.data().firstName??''} ${r.data().lastName??''} ${r.data().emailLower??r.data().email??''}`.toLowerCase().includes(search)).map(r=>({uid:r.id,firstName:r.data().firstName??'',lastName:r.data().lastName??'',email:r.data().emailLower??r.data().email??'',guest:source==='guests'}));
    const next=found.size>200?{collection:source,id:scanned.at(-1)!.id}:source==='users'?{collection:'guests'}:null;
    return {people,cursor:next,scanned:scanned.length};
  }
  async personAttendance(who:Identity,value:unknown) {
    const d=input(value,['uid','cursor']);await this.console.requireAdmin(who);
    const personId=uid(d.uid),{db}=this.service;
    const profile=(await db.doc(`users/${personId}`).get()).data()??(await db.doc(`guests/${personId}`).get()).data();
    if(!profile)fail('not-found','person-not-found','Person not found');
    const queries=['rsvps','checkins'].map(c=>{let q=db.collection(c).where('uid','==',personId).orderBy(FieldPath.documentId()).limit(51);if(d.cursor)q=q.startAfter(text(d.cursor,'cursor',300));return q.get();});
    const [rsvps,scans]=await Promise.all(queries),all=[...new Set([...rsvps.docs,...scans.docs].map(r=>r.id))].sort(),keys=all.slice(0,50),byIntent=new Map(rsvps.docs.map(r=>[r.id,r.data()])),byScan=new Map(scans.docs.map(r=>[r.id,r.data()]));
    const rows=await Promise.all(keys.map(async key=>{
      const r=byIntent.get(key),c=byScan.get(key);if(c?.mergedInto)return null;
      const eventId=id(c?.eventId??r?.eventId,'eventId'),e=(await db.doc(`events/${eventId}`).get()).data()??{};
      return wire({eventId,program:e.name??eventId,programId:e.programId??null,venue:e.venue?.name??'',startsAt:e.startsAt??null,timezone:e.timezone??'Australia/Sydney',countedIn:!!r&&r.cancelledAt==null,status:c?.status??(r?.cancelledAt?'cancelled':'counted-in'),walkIn:c?.walkIn??false,scannedAt:c?.scannedAt??null,distanceM:c?.distanceM??null,confirmedBy:c?.confirmedBy??null,decision:c?`${c.status}${c.confirmedBy?' · '+c.confirmedBy:''}`:'Not scanned'});
    }));
    return {person:{uid:personId,firstName:profile!.firstName??'',lastName:profile!.lastName??'',email:profile!.emailLower??profile!.email??''},rows:rows.filter(Boolean),cursor:all.length>50?keys.at(-1):null};
  }
  async coordinates(who:Identity,value:unknown) {
    const d=input(value,['address','suburb','postcode','state']);await this.console.requireAdmin(who);
    const address=[text(d.address,'street address',300,3),text(d.suburb,'suburb',100,1),text(d.state,'state',10,2),text(d.postcode??'','postcode',10,0),'Australia'].filter(Boolean).join(', '),{db}=this.service;
    const key=hash(address.toLowerCase()),cached=await db.doc(`adminGeocodeCache/${key}`).get();
    if(cached.exists && cached.data()!.expiresAt.toMillis()>this.service.now())return {results:cached.data()!.results,cached:true};
    const gate=db.doc('adminOperations/nominatim'),now=this.service.now();
    await db.runTransaction(async tx=>{
      const old=(await tx.get(gate)).data();
      if((old?.busyUntil?.toMillis()??0)>now || (old?.nextAt?.toMillis()??0)>now)fail('resource-exhausted','geocoder-busy','A coordinate lookup is already running. Wait a moment and try again.');
      tx.set(gate,{busyUntil:Timestamp.fromMillis(now+30000),nextAt:Timestamp.fromMillis(now+1100)});
    });
    try {
      const endpoint=process.env.NOMINATIM_ENDPOINT??'https://nominatim.openstreetmap.org/search';
      const url=new URL(endpoint);if(url.protocol!=='https:')throw Error('Invalid geocoding endpoint');
      url.search=new URLSearchParams({q:address,format:'jsonv2',countrycodes:'au',limit:'5'}).toString();
      const response=await this.fetcher(url,{headers:{'User-Agent':'Rally4Ever-Venue-Admin/1.0 (+https://rally4ever.org)','Accept':'application/json'},signal:AbortSignal.timeout(15000)});
      if(!response.ok)fail('unavailable','geocoder-unavailable','Coordinate lookup is unavailable. You can enter coordinates manually.');
      const raw=await response.json() as Array<{lat:string;lon:string;display_name:string}>;
      const results=raw.map(r=>({lat:Number(r.lat),lng:Number(r.lon),label:r.display_name,attribution:'© OpenStreetMap contributors'})).filter(r=>Number.isFinite(r.lat)&&Number.isFinite(r.lng)&&Math.abs(r.lat)<=90&&Math.abs(r.lng)<=180);
      await cached.ref.set({results,createdAt:this.service.stamp(),expiresAt:Timestamp.fromMillis(this.service.now()+30*86400000)});
      return {results,cached:false};
    } finally {await gate.set({busyUntil:Timestamp.fromMillis(0)},{merge:true});}
  }
}
