import {validateOperations} from './operations';
import { randomUUID } from "node:crypto";
import { DocumentData, Timestamp } from "firebase-admin/firestore";
import { AttendanceService, uid } from "./service";
import { Identity, input, text, id, fail, hash } from "./domain";
import { parseSessionTime, validateVenue } from "./catalogue";

export function wire(value: any): any {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(wire);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, wire(v)]),
    );
  return value;
}
export function venueId(v: DocumentData): string {
  return v.id ?? `v-${hash(`${v.name}|${v.lat}|${v.lng}`).slice(0, 20)}`;
}
export function venueCodeBase(name:string,state:string):string {
  const slug=name.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,110).replace(/-$/,'');
  return `${slug||'venue'}-${state.toLowerCase()}`;
}
function photos(value: unknown): string {
  const url = text(value ?? "", "photoUrl", 2048, 0);
  if (
    url &&
    !/^https:\/\/[^\s]+$/.test(url) &&
    !/^gs:\/\/rally4ever-3adaf\.firebasestorage\.app\/(?:venues|sessions)\/[A-Za-z0-9-]+\/[A-Za-z0-9._-]+$/.test(
      url,
    )
  )
    fail(
      "invalid-argument",
      "invalid-photo",
      "Use an HTTPS image or an uploaded venue photo",
    );
  return url;
}
export class AdminConsoleService {
  constructor(
    readonly service: AttendanceService,
    readonly sealPhoto?: (url: string) => Promise<void>,
  ) {}
  async requireAdmin(who: Identity) {
    if (who.role !== "admin")
      fail("permission-denied", "admin-claim-required", "Admin claim required");
    await this.service.db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail(
          "permission-denied",
          "admin-required",
          "Admin access has been revoked",
        );
    });
  }
  async catalogue(who: Identity, value: unknown) {
    const options=input(value, ["includeDeleted"]);
    if(options.includeDeleted!==undefined && typeof options.includeDeleted!=="boolean") fail("invalid-argument","invalid-input","Invalid deleted filter");
    await this.requireAdmin(who);
    const { db } = this.service;
    const [events, programs, stored, forms, programOps, sessionOps] = await Promise.all(
      ["events", "programs", "venues", "forms", "programOperations", "sessionOperations"].map((c) =>
        db.collection(c).limit(1001).get(),
      ),
    );
    if ([events, programs, stored].some((q) => q.size > 1000))
      fail(
        "resource-exhausted",
        "catalogue-limit",
        "More than 1000 records: request a paginated export before editing",
      );
    const privatePrograms=new Map(programOps.docs.map(d=>[d.id,d.data()]));
    const privateSessions=new Map(sessionOps.docs.map(d=>[d.id,d.data()]));
    const operations=(data:DocumentData|undefined)=>data?{fields:data.fields??{},contacts:data.contacts??[]}:undefined;
    const venues = new Map<string, DocumentData>();
    for (const d of [...programs.docs, ...events.docs]) {
      const v = d.data().venue;
      if (v?.name) {
        const key = d.data().venueId ?? venueId(v);
        if (!venues.has(key))
          venues.set(key, {
            ...v,
            id: key,
            code: v.code ?? key,
            photoUrl: v.photoUrl ?? d.data().photoUrl ?? "",
            revision: 0,
          });
      }
    }
    for (const d of stored.docs) venues.set(d.id, { ...d.data(), id: d.id });
    return wire({
      events: events.docs.filter(d=>!d.data().deletedAt&&!d.data().hiddenAt).map((d) => ({ ...d.data(), id: d.id,operations:operations(privateSessions.get(d.id)??privatePrograms.get(d.data().programId))??{},operationsInherited:!privateSessions.has(d.id)&&privatePrograms.has(d.data().programId) })),
      programs: programs.docs.filter(d=>options.includeDeleted || !d.data().deletedAt).map((d) => ({ ...d.data(), id: d.id,operations:operations(privatePrograms.get(d.id))??{} })),
      venues: [...venues.values()].filter(v=>options.includeDeleted || !v.deletedAt),
      forms: forms.docs.map((d) => ({
        id: d.id,
        version: d.data().version,
        formType: d.data().formType,
      })),
    });
  }
  async saveSession(who: Identity, value: unknown) {
    const d = input(value, ["eventId", "revision", "changes", "operations"]);
    await this.requireAdmin(who);
    const eventId = d.eventId ? id(d.eventId, "eventId") : randomUUID(),
      changes = input(d.changes, [
        "name",
        "code",
        "sport",
        "status",
        "registrationStatus",
        "startsAt",
        "endsAt",
        "timezone",
        "capacity",
        "coachUids",
        "coachNames",
        "venue",
        "geofenceRadiusM",
        "requiredFormIds",
        "notes",
        "photoUrl",
        "isDemo",
        "seedBatch",
        "programId",
      ]);
    const operations=d.operations===undefined?undefined:validateOperations(d.operations);
    const { db } = this.service;
    await db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin access revoked");
      const ref = db.doc(`events/${eventId}`),
        old = await tx.get(ref);
      const opsRef=db.doc(`sessionOperations/${eventId}`), oldOps=operations===undefined?null:await tx.get(opsRef);
      if (old.data()?.deletedAt || old.data()?.hiddenAt) fail("failed-precondition","program-deleted","Restore the program before editing its sessions");
      if (old.exists && (old.data()!.revision ?? 0) !== d.revision)
        fail(
          "aborted",
          "stale-session",
          "Session changed. Reload before saving",
        );
      const p = { ...old.data(), ...changes };
      if ("isDemo" in changes && typeof changes.isDemo !== "boolean")
        fail("invalid-argument", "invalid-demo", "isDemo must be a boolean");
      for (const [key, options] of Object.entries({
        sport: ["tennis", "pickleball"],
        status: ["draft", "published", "cancelled", "archived"],
        registrationStatus: ["open", "full", "closed"],
      }))
        if (!options.includes(p[key]))
          fail("invalid-argument", "invalid-session", `Choose valid ${key}`);
      const startsAt = parseSessionTime(
          typeof p.startsAt === "string"
            ? p.startsAt
            : p.startsAt?.toDate().toISOString(),
        ),
        endsAt = parseSessionTime(
          typeof p.endsAt === "string"
            ? p.endsAt
            : p.endsAt?.toDate().toISOString(),
        );
      if (
        endsAt.toMillis() <= startsAt.toMillis() ||
        endsAt.toMillis() - startsAt.toMillis() > 86400000
      )
        fail(
          "invalid-argument",
          "invalid-time",
          "Session duration must be positive and within 24 hours",
        );
      if (!old.exists && startsAt.toMillis() <= this.service.now())
        fail("invalid-argument", "past-session", "Create a future session");
      const timezone = text(p.timezone, "timezone", 100);
      try {
        new Intl.DateTimeFormat("en", { timeZone: timezone }).format();
      } catch {
        fail("invalid-argument", "invalid-timezone", "Choose an IANA timezone");
      }
      const venue =
          "venue" in changes || !old.exists ? validateVenue(p.venue) : p.venue,
        code = id(p.code ?? `s-${eventId}`, "code");
      if(venue?.id && (await tx.get(db.doc(`venues/${id(venue.id,"venueId")}`))).data()?.deletedAt) fail("failed-precondition","venue-deleted","Restore this venue or choose another venue");
      const existingCode = await tx.get(
        db.collection("events").where("code", "==", code).limit(2),
      );
      if (existingCode.docs.some((e) => e.id !== eventId))
        fail(
          "already-exists",
          "duplicate-code",
          "Session code is already used",
        );
      const scans = await tx.get(
        db.collection("checkins").where("eventId", "==", eventId).limit(1),
      );
      if (
        old.exists &&
        (!scans.empty || old.data()!.startsAt.toMillis() <= this.service.now())
      ) {
        for (const key of [
          "name",
          "code",
          "sport",
          "startsAt",
          "endsAt",
          "timezone",
          "venue",
          "geofenceRadiusM",
          "requiredFormIds",
        ]) {
          if (
            key in changes &&
            JSON.stringify(wire(old.data()![key])) !==
              JSON.stringify(wire(p[key]))
          )
            fail(
              "failed-precondition",
              "attendance-started",
              "Keep original scan/session context; only status, notes, coaches, photo and capacity may change",
            );
        }
      }
      if (!Array.isArray(p.coachUids) || p.coachUids.length > 10)
        fail(
          "invalid-argument",
          "invalid-coaches",
          "Choose up to ten staff accounts",
        );
      const coachUids = [...new Set<string>(p.coachUids.map(uid))],
        coachNames: string[] = [];
      const validateCoaches =
        !old.exists ||
        "coachUids" in changes ||
        (p.status === "published" && old.data()?.status !== "published");
      if (!validateCoaches)
        coachNames.push(...(old.data()?.coachNames ?? coachUids));
      for (const staff of validateCoaches ? coachUids : []) {
        const profile = (await tx.get(db.doc(`users/${staff}`))).data();
        if (
          !profile ||
          profile.mergedInto !== null ||
          !["admin", "coach"].includes(profile.role) ||
          (profile.role === "coach" && profile.coachEnabled === false)
        )
          fail("failed-precondition", "invalid-coach", "Assign active staff");
        coachNames.push(profile.firstName ?? staff);
      }
      const capacity = p.capacity ?? null;
      if (
        capacity !== null &&
        (!Number.isInteger(capacity) || capacity < 1 || capacity > 5000)
      )
        fail(
          "invalid-argument",
          "invalid-capacity",
          "Capacity must be 1–5000 or unlimited",
        );
      const rsvps = await tx.get(
        db
          .collection("rsvps")
          .where("eventId", "==", eventId)
          .where("cancelledAt", "==", null),
      );
      if (capacity !== null && capacity < rsvps.size)
        fail(
          "failed-precondition",
          "capacity-below-reservations",
          "Capacity is below current reservations",
        );
      const radius = p.geofenceRadiusM ?? 150;
      if (!Number.isInteger(radius) || radius < 10 || radius > 2000)
        fail(
          "invalid-argument",
          "invalid-geofence",
          "Geofence must be 10–2000 metres",
        );
      if (!Array.isArray(p.requiredFormIds))
        fail("invalid-argument", "invalid-forms", "Form IDs must be an array");
      const forms = p.requiredFormIds;
      if (forms.length > 10)
        fail("invalid-argument", "invalid-forms", "Choose up to ten forms");
      for (const f of !old.exists ||
      "requiredFormIds" in changes ||
      (p.status === "published" && old.data()?.status !== "published")
        ? forms
        : [])
        if (!(await tx.get(db.doc(`forms/${id(f, "formId")}`))).exists)
          fail("invalid-argument", "invalid-forms", "Unknown form");
      if (
        p.status === "published" &&
        (!old.exists ||
          old.data()?.status !== "published" ||
          "venue" in changes ||
          "coachUids" in changes) &&
        (venue.lat == null || venue.lng == null || !coachUids.length)
      )
        fail(
          "failed-precondition",
          "incomplete-session",
          "Published sessions need venue coordinates and a coach",
        );
      const programId = p.programId ? id(p.programId, "programId") : null;
      if (programId) {
        const program = (await tx.get(db.doc(`programs/${programId}`))).data();
        if (
          !program ||
          (p.status === "published" && program.status !== "active")
        )
          fail(
            "failed-precondition",
            "inactive-program",
            "Publish the linked program first",
          );
      }
      const at = this.service.stamp();
      const next = {
        name: text(p.name, "name", 200),
        code,
        sport: p.sport,
        status: p.status,
        registrationStatus:
          p.status === "cancelled" ? "closed" : p.registrationStatus,
        startsAt,
        endsAt,
        timezone,
        capacity,
        bookedCount: rsvps.size,
        coachUids,
        coachNames,
        venue,
        geofenceRadiusM: radius,
        requiredFormIds: forms,
        notes: text(p.notes ?? "", "notes", 4000, 0),
        photoUrl: photos(p.photoUrl),
        isDemo: p.isDemo === true,
        seedBatch: text(p.seedBatch ?? "", "seedBatch", 200, 0),
        programId,
        revision: (old.data()?.revision ?? 0) + 1,
        catalogueManaged: old.exists ? (old.data()?.catalogueManaged ?? false) || !!programId : true,
        createdAt: old.data()?.createdAt ?? at,
        updatedAt: at,
        updatedBy: who.uid,
      };
      tx.set(ref, next, { merge: true });
      if(operations!==undefined) tx.set(opsRef,{...operations,revision:next.revision,updatedAt:at,updatedBy:who.uid});
      tx.create(db.collection("catalogueAudits").doc(), {
        kind: "admin-session",
        operationsBefore:oldOps?.data()??null,
        operationsAfter:operations??null,
        eventId,
        actorUid: who.uid,
        createdAt: at,
        before: old.data() ?? null,
        after: next,
      });
    });
    return { eventId };
  }
  async saveVenue(who: Identity, value: unknown) {
    const d = input(value, ["venueId", "revision", "venue"]);
    await this.requireAdmin(who);
    const v = input(d.venue, [
      "name",
      "code",
      "address",
      "suburb",
      "postcode",
      "state",
      "country",
      "lat",
      "lng",
      "photoUrl",
      "isDemo",
    ]);
    const key = d.venueId ? id(d.venueId, "venueId") : randomUUID(),
      base = validateVenue(
        Object.fromEntries(
          ["name", "address", "suburb", "postcode", "state", "country", "lat", "lng"].map(
            (k) => [k, v[k]],
          ),
        ),
      ),
      photoUrl = photos(v.photoUrl);
    const automaticCode = !v.code, baseCode=venueCodeBase(base.name,base.state);
    let code = v.code ? id(v.code, "venue code") : baseCode;
    if (photoUrl.startsWith("gs://")) {
      if (
        !photoUrl.startsWith(
          `gs://rally4ever-3adaf.firebasestorage.app/venues/${key}/`,
        )
      )
        fail(
          "invalid-argument",
          "venue-photo-path",
          "Upload the photo under this venue ID",
        );
      await this.sealPhoto?.(photoUrl);
    }
    const { db } = this.service;
    const [events, programs] = await Promise.all(
      ["events", "programs"].map((c) => db.collection(c).limit(1001).get()),
    );
    if (events.size > 1000 || programs.size > 1000)
      fail(
        "resource-exhausted",
        "catalogue-limit",
        "Too many records for a single venue update",
      );
    const linked = [...events.docs, ...programs.docs].filter(
      (r) => r.data().venue && (r.data().venueId ?? venueId(r.data().venue)) === key,
    );
    if (linked.length > 150)
      fail(
        "resource-exhausted",
        "venue-too-large",
        "Split this venue update into reviewed batches",
      );
    await db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin access revoked");
      const ref = db.doc(`venues/${key}`), old = await tx.get(ref);
      if(old.data()?.deletedAt) fail("failed-precondition","venue-deleted","Restore this venue before editing");
      let conflicts=await tx.get(db.collection("venues").where("code","==",code).limit(2));
      if(automaticCode) {
        for(let suffix=2;conflicts.docs.some(r=>r.id!==key)&&suffix<=100;suffix++) {
          code=`${baseCode}-${suffix}`;
          conflicts=await tx.get(db.collection("venues").where("code","==",code).limit(2));
        }
      }
      if (conflicts.docs.some((r) => r.id !== key))
        fail(
          "already-exists",
          "duplicate-venue-code",
          "Venue code is already used",
        );
      if (old.exists && old.data()!.revision !== d.revision)
        fail("aborted", "stale-venue", "Venue changed. Reload first");
      const snapshots = await Promise.all(linked.map((r) => tx.get(r.ref)));
      const scanned = new Set<string>();
      for (const r of snapshots.filter((r) => r.ref.parent.id === "events")) {
        if (
          !(
            await tx.get(
              db.collection("checkins").where("eventId", "==", r.id).limit(1),
            )
          ).empty
        )
          scanned.add(r.id);
      }
      const at = this.service.stamp(),
        venue = { ...base, id: key, code, photoUrl };
      tx.set(ref, {
        ...venue,
        isDemo: v.isDemo === true,
        revision: (old.data()?.revision ?? 0) + 1,
        createdAt: old.data()?.createdAt ?? at,
        updatedAt: at,
        updatedBy: who.uid,
      });
      for (const r of snapshots) {
        const p = r.data()!;
        if (!p.venue || (p.venueId ?? venueId(p.venue)) !== key) continue;
        const started =
          r.ref.parent.id === "events" &&
          (p.startsAt.toMillis() <= this.service.now() || scanned.has(r.id));
        tx.update(r.ref, {
          venue: started ? { ...p.venue, id: key, photoUrl } : venue,
          ...((p.photoMode === 'venue' || (!p.photoMode && p.photoUrl && p.photoUrl === p.venue.photoUrl)) ? {photoUrl:'',photoMode:'venue'} : {}),
          revision: (p.revision ?? 0) + 1,
          updatedAt: at,
        });
      }
      tx.create(db.collection("catalogueAudits").doc(), {
        kind: "venue",
        venueId: key,
        actorUid: who.uid,
        createdAt: at,
        before: old.data() ?? null,
        after: venue,
        updatedRecords: snapshots.map((r) => ({
          path: r.ref.path,
          venue: r.data()!.venue,
          photoUrl: r.data()!.photoUrl ?? "",
          revision: r.data()!.revision ?? 0,
        })),
      });
    });
    return { venueId: key, code, updatedRecords: linked.length };
  }
  async setPhoto(who: Identity, value: unknown) {
    const d = input(value, ['kind','id','revision','photoUrl','mode']);
    await this.requireAdmin(who);
    if (!['session','venue'].includes(d.kind as string)) fail('invalid-argument','invalid-kind','Choose session or venue');
    const key=id(d.id), mode=d.mode ?? 'override';
    if (!['override','venue','none'].includes(mode as string)) fail('invalid-argument','invalid-photo-mode','Choose a photo mode');
    const photoUrl=mode==='override'?photos(d.photoUrl):'';
    if (photoUrl) {
      let path='';
      if(photoUrl.startsWith('gs://rally4ever-3adaf.firebasestorage.app/')) path=photoUrl.slice('gs://rally4ever-3adaf.firebasestorage.app/'.length);
      else {try {const u=new URL(photoUrl);if(u.origin==='https://firebasestorage.googleapis.com'&&u.pathname.startsWith('/v0/b/rally4ever-3adaf.firebasestorage.app/o/'))path=decodeURIComponent(u.pathname.split('/o/')[1]);}catch {}}
      const expected=d.kind==='venue'?'venues':'sessions';
      if(!new RegExp('^'+expected+'/'+key+'/[A-Za-z0-9._-]+$').test(path))fail('invalid-argument','photo-path','Upload under this record ID');
      await this.sealPhoto?.('gs://rally4ever-3adaf.firebasestorage.app/'+path);
    }
    const {db}=this.service;
    if(d.kind==='venue') {
      const v=(await db.doc('venues/'+key).get()).data();if(!v)fail('not-found','venue-not-found','Venue unavailable');
      const fields=['name','code','address','suburb','postcode','state','lat','lng','isDemo'];
      return this.saveVenue(who,{venueId:key,revision:d.revision,venue:{...Object.fromEntries(fields.map(k=>[k,v![k]??({isDemo:false}[k as 'isDemo']??'')])),photoUrl}});
    }
    return db.runTransaction(async tx=>{
      if((await this.service.actor(tx,who)).role!=='admin')fail('permission-denied','admin-required','Admin access required');
      const ref=db.doc('events/'+key),old=await tx.get(ref);if(!old.exists)fail('not-found','session-not-found','Session unavailable');
      if((old.data()!.revision??0)!==d.revision)fail('aborted','stale-session','Session changed. Reload before saving');
      const next={photoUrl,photoMode:mode,revision:(old.data()!.revision??0)+1,updatedAt:this.service.stamp(),updatedBy:who.uid};
      tx.update(ref,next);tx.create(db.collection('catalogueAudits').doc(),{kind:'session-photo',eventId:key,actorUid:who.uid,before:{photoUrl:old.data()!.photoUrl??'',photoMode:old.data()!.photoMode??null},after:next,createdAt:this.service.stamp()});
      return {eventId:key,...next};
    });
  }
  async demo(who: Identity, value: unknown) {
    const d = input(value, ["apply", "expectedIds", "expectedPaths"]);
    await this.requireAdmin(who);
    const { db } = this.service;
    return db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin access revoked");
      const collections = ["events", "programs", "venues"];
      const found = await Promise.all(
        collections.map((c) =>
          tx.get(db.collection(c).where("isDemo", "==", true)),
        ),
      );
      const docs = found.flatMap((q) => q.docs),
        paths = docs.map((d) => d.ref.path).sort(),
        ids = found[0].docs.map((d) => d.id).sort();
      const counts = Object.fromEntries(
        collections.map((c, i) => [c, found[i].size]),
      );
      if (d.apply !== true)
        return { count: paths.length, counts, paths, eventIds: ids };
      const expected =
        d.expectedPaths ??
        (paths.every((p) => p.startsWith("events/")) &&
        Array.isArray(d.expectedIds)
          ? d.expectedIds.map((i) => "events/" + i)
          : []);
      if (JSON.stringify(paths) !== JSON.stringify(expected))
        fail(
          "aborted",
          "demo-changed",
          "Demo selection changed. Preview again",
        );
      if (paths.length > 200)
        fail(
          "resource-exhausted",
          "demo-too-large",
          "Remove demo catalogue records in reviewed batches",
        );
      // Do not orphan a real session/program by removing its demo parent/venue.
      const [events, programs] = await Promise.all(
        ["events", "programs"].map((c) => tx.get(db.collection(c).limit(1001))),
      );
      if (events.size > 1000 || programs.size > 1000)
        fail(
          "resource-exhausted",
          "catalogue-limit",
          "Review references before removing this catalogue",
        );
      const removing = new Set(paths);
      for (const record of [...events.docs, ...programs.docs]) {
        if (removing.has(record.ref.path)) continue;
        const p = record.data();
        if (
          (p.programId && removing.has("programs/" + p.programId)) ||
          (p.venue && removing.has("venues/" + venueId(p.venue)))
        )
          fail(
            "failed-precondition",
            "demo-in-use",
            "A non-demo record still uses this demo program or venue",
          );
      }
      const at = this.service.stamp();
      for (const doc of docs) {
        tx.create(db.doc(`demoRemovalBackups/${randomUUID()}`), {
          path: doc.ref.path,
          before: doc.data(),
          actorUid: who.uid,
          removedAt: at,
        });
        tx.delete(doc.ref);
      }
      tx.create(db.collection("catalogueAudits").doc(), {
        kind: "remove-demo",
        paths,
        counts,
        actorUid: who.uid,
        createdAt: at,
      });
      return { removed: paths.length, counts, paths, eventIds: ids };
    });
  }
}
