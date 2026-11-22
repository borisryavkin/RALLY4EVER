import {validateOperations} from './operations';
import { randomUUID } from "node:crypto";
import { Timestamp } from "firebase-admin/firestore";
import { AttendanceService, uid } from "./service";
import { Identity, input, text, id, coordinate, fail } from "./domain";

const STATES = ["ACT", "NSW", "NT", "QLD", "SA", "TAS", "VIC", "WA"];
function choice(value: unknown, options: string[], name: string): string {
  if (typeof value !== "string" || !options.includes(value))
    fail("invalid-argument", "invalid-catalogue", `Choose a valid ${name}`);
  return value;
}
function strings(value: unknown, name: string, max = 20): string[] {
  if (!Array.isArray(value) || value.length > max)
    fail("invalid-argument", "invalid-catalogue", `Invalid ${name}`);
  return [...new Set(value.map((v) => text(v, name, 128)))];
}
function photo(value: unknown): string {
  const result = value === undefined ? "" : text(value, "photoUrl", 2048, 0);
  if (result) {
    let url: URL;
    try { url = new URL(result); } catch { fail("invalid-argument", "invalid-photo", "Use an HTTPS photo URL"); }
    if ((url!.protocol !== "https:" && !/^gs:\/\/rally4ever-3adaf\.firebasestorage\.app\/venues\//.test(result)) || url!.username || url!.password)
      fail("invalid-argument", "invalid-photo", "Use an HTTPS photo URL");
  }
  return result;
}
export function validateVenue(value: unknown) {
  const v = input(value, ["name", "address", "suburb", "postcode", "state", "lat", "lng", "id", "code", "photoUrl"]);
  if ((v.lat == null) !== (v.lng == null)) fail("invalid-argument","invalid-location","Supply both latitude and longitude");
  return {...(v.id?{id:id(v.id,'venueId')}:{}),...(v.code?{code:id(v.code,'venue code')}:{}),...(v.photoUrl?{photoUrl:photo(v.photoUrl)}:{}),name:text(v.name,"venue name",200), address:text(v.address??"","address",500,0), suburb:text(v.suburb,"suburb",100),
    postcode:text(v.postcode??"","postcode",10,0),state:choice(v.state,STATES,"state"),lat:v.lat==null?null:coordinate(v.lat,"lat"),lng:v.lng==null?null:coordinate(v.lng,"lng")};
}
export function validateProgram(value: unknown) {
  const d = input(value, ["name", "sport", "status", "venue", "timezone", "scheduleText", "coachUids", "coachNames", "notes", "photoUrl", "capacity", "registrationStatus"]);
  const v = validateVenue(d.venue);
  const zone = text(d.timezone, "timezone", 100);
  try { new Intl.DateTimeFormat("en-AU", { timeZone: zone }).format(); }
  catch { fail("invalid-argument", "invalid-timezone", "Choose a valid timezone"); }
  const capacity = d.capacity ?? null;
  if (capacity !== null && (!Number.isInteger(capacity) || (capacity as number) < 1 || (capacity as number) > 5000))
    fail("invalid-argument", "invalid-capacity", "Capacity must be 1–5000, or unlimited");
  if ((v.lat == null) !== (v.lng == null))
    fail("invalid-argument", "invalid-location", "Supply both latitude and longitude");
  return {
    name: text(d.name, "name", 200), sport: choice(d.sport, ["tennis", "pickleball"], "sport"),
    status: choice(d.status, ["draft", "active", "archived"], "status"),
    venue: v,
    timezone: zone, scheduleText: text(d.scheduleText, "schedule", 500),
    coachUids: strings(d.coachUids ?? [], "coachUids").map(uid), coachNames: strings(d.coachNames ?? [], "coachNames"),
    notes: text(d.notes ?? "", "notes", 4000, 0), photoUrl: photo(d.photoUrl), capacity,
    registrationStatus: choice(d.registrationStatus ?? "open", ["open", "full", "closed"], "registration status"),
  };
}
export function parseSessionTime(value: unknown): Timestamp {
  const raw = text(value, "session time", 50);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(raw) || !Number.isFinite(Date.parse(raw)))
    fail("invalid-argument", "invalid-time", "Use an ISO date/time with a timezone offset");
  const day = raw.slice(0, 10), [year, month, date] = day.split("-").map(Number);
  if (new Date(Date.UTC(year, month - 1, date)).toISOString().slice(0, 10) !== day)
    fail("invalid-argument", "invalid-time", "Use a valid calendar date");
  return Timestamp.fromMillis(Date.parse(raw));
}
export class CatalogueService {
  constructor(readonly service: AttendanceService) {}
  async listPrograms(who: Identity, value: unknown) {
    input(value, []);
    await this.service.db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin") fail("permission-denied", "admin-required", "Admin role required");
    });
    const rows = await this.service.db.collection("programs").orderBy("name").limit(500).get();
    return { programs: rows.docs.filter(d=>!d.data().deletedAt).map((d) => ({ ...d.data(), id: d.id })) };
  }
  async saveProgram(who: Identity, value: unknown) {
    const d = input(value, ["programId", "program", "reason", "revision", "operations"]), program = validateProgram(d.program);
    const operations = d.operations === undefined ? undefined : validateOperations(d.operations);
    const programId = d.programId ? id(d.programId, "programId") : randomUUID();
    const reason = d.reason === undefined ? "Program updated" : text(d.reason, "reason", 1000), { db } = this.service;
    await db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin") fail("permission-denied", "admin-required", "Admin role required");
      const ref = db.doc(`programs/${programId}`), old = await tx.get(ref);
      const opsRef=db.doc(`programOperations/${programId}`), oldOps=operations===undefined?null:await tx.get(opsRef);
      if(program.venue?.id && (await tx.get(db.doc(`venues/${id(program.venue.id,"venueId")}`))).data()?.deletedAt) fail("failed-precondition","venue-deleted","Restore this venue or choose another venue");
      if(old.data()?.deletedAt) fail("failed-precondition","program-deleted","Restore this program before editing or publishing");
      if (old.exists && d.revision !== old.data()!.revision) fail("aborted", "stale-program", "Program changed. Reload before saving");
      const validateCoaches = !old.exists || JSON.stringify(old.data()?.coachUids ?? []) !== JSON.stringify(program.coachUids) || (program.status === "active" && old.data()?.status !== "active");
      for (const coachId of validateCoaches ? program.coachUids : []) {
        const coach = (await tx.get(db.doc(`users/${coachId}`))).data();
        if (!coach || coach.mergedInto !== null || !["coach", "admin"].includes(coach.role) || (coach.role === "coach" && coach.coachEnabled === false))
          fail("failed-precondition", "invalid-coach", "Assign an active coach account");
      }
      const at = this.service.stamp();
      tx.set(ref, { ...program, needsVerification: program.status === "active" ? false : (old.data()?.needsVerification ?? false), reviewedBy: program.status === "active" ? who.uid : (old.data()?.reviewedBy ?? null), reviewedAt: program.status === "active" ? at : (old.data()?.reviewedAt ?? null), createdAt: old.data()?.createdAt ?? at, updatedAt: at, updatedBy: who.uid, revision: (old.data()?.revision ?? 0) + 1 }, { merge: true });
      if(operations!==undefined) tx.set(opsRef,{...operations,revision:(old.data()?.revision??0)+1,updatedAt:at,updatedBy:who.uid});
      tx.create(db.collection("catalogueAudits").doc(), {operationsBefore:oldOps?.data()??null,operationsAfter:operations??null, kind: "program", programId, actorUid: who.uid, reason, before: old.data() ?? null, after: program, createdAt: at });
    });
    return { programId };
  }
  async saveSession(who: Identity, value: unknown) {
    const d = input(value, ["programId", "eventId", "startsAt", "endsAt", "status", "reason", "revision", "capacity", "registrationStatus", "notes", "photoUrl", "venue", "coachUids", "timezone"]);
    const programId = d.programId === undefined ? null : id(d.programId, "programId"), eventId = d.eventId ? id(d.eventId, "eventId") : randomUUID();
    if (!programId && !d.eventId) fail("invalid-argument", "program-required", "Create sessions from a published program");
    const startsAt = parseSessionTime(d.startsAt), endsAt = parseSessionTime(d.endsAt);
    const reason = d.reason === undefined ? "Session updated" : text(d.reason, "reason", 1000), status = choice(d.status ?? "published", ["published", "cancelled"], "session status");
    if (endsAt.toMillis() <= startsAt.toMillis() || endsAt.toMillis() - startsAt.toMillis() > 86400000)
      fail("invalid-argument", "invalid-time", "Session end must follow start, within 24 hours");
    const { db } = this.service;
    await db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin") fail("permission-denied", "admin-required", "Admin role required");
      const ref = db.doc(`events/${eventId}`), old = await tx.get(ref);
      const p = programId ? (await tx.get(db.doc(`programs/${programId}`))).data() : old.data();
      if (!p || (programId ? p.status !== "active" : !old.exists || p.programId != null)) fail("failed-precondition", "inactive-program", "Publish an active program first");
      if ((d.venue === undefined && (p.venue.lat == null || p.venue.lng == null))) fail("failed-precondition", "missing-location", "Verify the venue coordinates before scheduling");
      const venue = d.venue === undefined ? p.venue : validateVenue(d.venue);
      const coachUids = d.coachUids === undefined ? p.coachUids : strings(d.coachUids, "coachUids", 10).map(uid);
      const timezone = d.timezone === undefined ? p.timezone : text(d.timezone,"timezone",100);
      try { new Intl.DateTimeFormat("en-AU",{timeZone:timezone}).format(); } catch { fail("invalid-argument","invalid-timezone","Choose a valid timezone"); }
      if (venue.lat == null || venue.lng == null) fail("failed-precondition","missing-location","Verify the venue coordinates");
      if (coachUids.length === 0) fail("failed-precondition", "missing-coach", "Assign a coach before scheduling");
      if (old.exists && ((old.data()!.programId ?? null) !== programId || (old.data()!.revision ?? null) !== (d.revision ?? null)))
        fail("aborted", "stale-session", "Session changed. Reload before saving");
      if (old.exists && old.data()!.startsAt.toMillis() <= this.service.now())
        fail("failed-precondition", "session-started", "Started sessions retain their original details");
      if (startsAt.toMillis() <= this.service.now()) fail("invalid-argument", "past-session", "Create a future session");
      const coachNames: string[] = [];
      for (const coachId of coachUids) {
        const coach = (await tx.get(db.doc(`users/${coachId}`))).data();
        if (!coach || !["coach", "admin"].includes(coach.role) || (coach.role === "coach" && coach.coachEnabled === false) || coach.mergedInto !== null)
          fail("failed-precondition", "invalid-coach", "Assign an active coach account");
        coachNames.push(coach.firstName || "Coach");
      }
      if (old.exists && !(await tx.get(db.collection("checkins").where("eventId", "==", eventId).limit(1))).empty)
        fail("failed-precondition", "session-started", "Attendance has begun; retain the original session details");
      const capacity = d.capacity === undefined ? (p.capacity ?? null) : d.capacity;
      if (capacity !== null && (!Number.isInteger(capacity) || (capacity as number) < 1 || (capacity as number) > 5000)) fail("invalid-argument", "invalid-capacity", "Choose a valid session capacity");
      const registrationStatus = d.registrationStatus === undefined ? (p.registrationStatus ?? "open") : choice(d.registrationStatus, ["open", "full", "closed"], "reservations");
      const rsvps = await tx.get(db.collection("rsvps").where("eventId", "==", eventId).where("cancelledAt", "==", null));
      if (capacity != null && rsvps.size > (capacity as number)) fail("failed-precondition", "capacity-below-reservations", "Capacity is below existing reservations");
      const at = this.service.stamp();
      const event = { ...(programId ? {programId} : {}), catalogueManaged: !!programId, name: p.name, sport: p.sport, venue, timezone,
        notes: d.notes === undefined ? (p.notes ?? "") : text(d.notes, "notes", 4000, 0), photoUrl: d.photoUrl === undefined ? (old.data()?.photoUrl ?? "") : photo(d.photoUrl), coachNames, coachUids,
        capacity, registrationStatus, bookedCount: rsvps.size, startsAt, endsAt, status,
        code: old.data()?.code ?? `s-${eventId}`, requiredFormIds: old.data()?.requiredFormIds ?? ["conduct", "waiver"],
        geofenceRadiusM: old.data()?.geofenceRadiusM ?? 150, createdAt: old.data()?.createdAt ?? at,
        updatedAt: at, revision: (old.data()?.revision ?? 0) + 1 };
      tx.set(ref, event, { merge: true });
      tx.create(db.collection("catalogueAudits").doc(), { kind: "session", eventId, programId, actorUid: who.uid, reason, before: old.data() ?? null, after: event, createdAt: at });
    });
    return { eventId };
  }
  async cancelSession(who: Identity, value: unknown) {
    const d=input(value,["eventId","reason","revision"]), eventId=id(d.eventId,"eventId"), reason=d.reason===undefined?"Session cancelled":text(d.reason,"reason",1000);
    const {db}=this.service;
    await db.runTransaction(async tx=>{
      if((await this.service.actor(tx,who)).role!=="admin")fail("permission-denied","admin-required","Admin role required");
      const ref=db.doc(`events/${eventId}`), e=await tx.get(ref);
      if(!e.exists)fail("not-found","event-not-found","Session not found");
      if((e.data()!.revision??null)!==(d.revision??null))fail("aborted","stale-session","Reload the session before cancelling");
      if(e.data()!.endsAt.toMillis()<=this.service.now())fail("failed-precondition","session-ended","Ended sessions retain their status");
      const at=this.service.stamp();
      tx.update(ref,{status:"cancelled",registrationStatus:"closed",updatedAt:at,revision:(e.data()!.revision??0)+1});
      tx.create(db.collection("catalogueAudits").doc(),{kind:"session-cancel",eventId,actorUid:who.uid,reason,before:e.data(),createdAt:at});
    });return {eventId,status:"cancelled"};
  }
  async setRsvp(who: Identity, value: unknown) {
    const d = input(value, ["eventId", "cancel"]), eventId = id(d.eventId, "eventId");
    if (d.cancel !== undefined && typeof d.cancel !== "boolean") fail("invalid-argument", "invalid-input", "Invalid cancellation");
    const { db } = this.service;
    return db.runTransaction(async (tx) => {
      await this.service.actor(tx, who);
      const ref = db.doc(`events/${eventId}`), e = (await tx.get(ref)).data();
      if (!e) fail("not-found", "event-not-found", "Session is unavailable");
      const rsvpRef = db.doc(`rsvps/${eventId}_${uid(who.uid)}`), old = await tx.get(rsvpRef);
      const p = e!.programId ? (await tx.get(db.doc(`programs/${e!.programId}`))).data() : null;
      const active = await tx.get(db.collection("rsvps").where("eventId", "==", eventId).where("cancelledAt", "==", null));
      const already = old.exists && old.data()!.cancelledAt === null;
      if (!d.cancel && !already) {
        if (e!.status !== "published" || e!.endsAt.toMillis() < this.service.now() || (e!.programId && p?.status !== "active") || (["full", "closed"].includes(e!.registrationStatus) || ["full", "closed"].includes(p?.registrationStatus)))
          fail("failed-precondition", "registration-closed", "This session is not accepting reservations");
        if (e!.capacity != null && active.size >= e!.capacity) fail("resource-exhausted", "session-full", "This session is full");
      }
      const bookedCount = active.size + (d.cancel ? (already ? -1 : 0) : (already ? 0 : 1));
      const at = this.service.stamp();
      if (d.cancel) { if (old.exists && already) tx.update(rsvpRef, { cancelledAt: at }); }
      else if (old.exists) { if (!already) tx.update(rsvpRef, { cancelledAt: null }); }
      else tx.create(rsvpRef, { eventId, uid: who.uid, createdAt: at, cancelledAt: null, source: "app" });
      tx.update(ref, { bookedCount, updatedAt: at });
      return { eventId, countedIn: !d.cancel, bookedCount, spotsAvailable: e!.capacity == null ? null : Math.max(0, e!.capacity - bookedCount) };
    });
  }
  async reconcileAvailability(eventId: string) {
    const { db } = this.service;
    await db.runTransaction(async (tx) => {
      const ref = db.doc(`events/${id(eventId)}`), event = await tx.get(ref);
      if (!event.exists) return;
      const active = await tx.get(db.collection("rsvps").where("eventId", "==", eventId).where("cancelledAt", "==", null));
      if (event.data()!.bookedCount !== active.size) tx.update(ref, { bookedCount: active.size });
    });
  }
}
