import { randomBytes } from "node:crypto";
import { Auth } from "firebase-admin/auth";
import {
  DocumentData,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {
  Identity,
  input,
  text,
  id,
  normalizeEmail,
  fail,
  hash,
  coordinate,
  checkWindow,
  checkDistance,
  secretMatches,
} from "./domain";

export interface Dependencies {
  db: Firestore;
  auth: Auth;
  now?: () => number;
}
export function uid(value: unknown): string {
  const result = text(value, "uid", 128);
  if (result.includes("/") || /[\x00-\x20]/.test(result))
    fail("invalid-argument", "invalid-id", "Invalid uid");
  return result;
}
export class AttendanceService {
  readonly db: Firestore;
  readonly auth: Auth;
  readonly now: () => number;
  constructor(deps: Dependencies) {
    this.db = deps.db;
    this.auth = deps.auth;
    this.now = deps.now ?? Date.now;
  }
  stamp(): Timestamp {
    return Timestamp.fromMillis(this.now());
  }
  async actor(tx: Transaction, who: Identity): Promise<DocumentData> {
    const snap = await tx.get(this.db.doc(`users/${uid(who.uid)}`));
    const p = snap.data();
    if (!p || p.mergedInto !== null)
      fail(
        "failed-precondition",
        "inactive-profile",
        "Register or resolve your profile first",
      );
    let role = p.role ?? who.role ?? "participant";
    if ((role === "admin" && who.role !== "admin") ||
        (role === "coach" && (who.role !== "coach" || p.coachEnabled === false)))
      role = "participant";
    return { ...p, role };
  }
  authorize(
    p: DocumentData,
    who: Identity,
    e: DocumentData,
    adminAllowed = true,
  ): void {
    if (
      (adminAllowed && p.role === "admin") ||
      (p.role === "coach" &&
        Array.isArray(e.coachUids) &&
        e.coachUids.includes(who.uid))
    )
      return;
    fail(
      "permission-denied",
      "event-role-required",
      "Only an assigned coach can manage this event",
    );
  }
  async event(tx: Transaction, eventId: string): Promise<DocumentData> {
    const snap = await tx.get(this.db.doc(`events/${eventId}`));
    if (!snap.exists) fail("not-found", "event-not-found", "Event not found");
    return snap.data()!;
  }
  window(e: DocumentData): void {
    if (e.status !== "published")
      fail(
        "failed-precondition",
        "event-unavailable",
        "This event is not open for check-in",
      );
    checkWindow(
      this.now(),
      e.startsAt.toMillis(),
      e.endsAt.toMillis(),
      e.timezone,
    );
  }
  async missingForms(
    tx: Transaction,
    participantUid: string,
    e: DocumentData,
  ): Promise<string[]> {
    if (!Array.isArray(e.requiredFormIds) || e.requiredFormIds.length > 10)
      fail("failed-precondition", "invalid-event", "Invalid required forms");
    const missing: string[] = [];
    for (const formId of e.requiredFormIds) {
      id(formId, "formId");
      const [form, consent] = await Promise.all([
        tx.get(this.db.doc(`forms/${formId}`)),
        tx.get(this.db.doc(`consents/${participantUid}_${formId}`)),
      ]);
      if (!form.exists)
        fail(
          "failed-precondition",
          "form-unavailable",
          "A required form is unavailable",
        );
      const c = consent.data(),
        f = form.data()!;
      if (
        !c ||
        c.uid !== participantUid ||
        c.formId !== formId ||
        c.version !== f.version ||
        c.formType !== f.formType ||
        !(c.signedAt instanceof Timestamp) ||
        c.signedAt.toMillis() > this.now()
      )
        missing.push(formId);
    }
    return missing;
  }
  baseProfile(userId: string, email: string): DocumentData {
    const at = this.stamp();
    return {
      uid: userId,
      email,
      emailLower: email,
      role: "participant",
      mergedInto: null,
      createdAt: at,
      updatedAt: at,
      firstName: "",
      lastName: "",
      postcode: "",
      injuries: "",
      preferences: {
        useInReports: false,
        wellbeingCheckIns: false,
        showInWhosGoing: false,
        marketingEmails: false,
      },
      about: {},
    };
  }
  // mobile/emergencyContact deliberately live here, not on the main profile:
  // only the owner, admin, and a coach actually running an event this person
  // is involved in may ever read them (see firestore.rules' validContact and
  // syncContactVisibility below).
  baseContact(): DocumentData {
    return {
      mobile: "",
      mobileVerified: false,
      emergencyContact: { name: "", mobile: "" },
      visibleToCoachUids: [],
      updatedAt: this.stamp(),
    };
  }
  // Grants every coach on `eventId` read access to `uid`'s contact details,
  // recording a real RSVP/check-in relationship. Never removes a coach once
  // granted -- a past relationship is still a legitimate reason to retain
  // visibility, and this only ever widens a narrow, purpose-built allowlist.
  async syncContactVisibility(eventId: string, uid: string): Promise<void> {
    const [event, contact] = await Promise.all([
      this.db.doc(`events/${eventId}`).get(),
      this.db.doc(`users/${uid}/private/contact`).get(),
    ]);
    const coachUids = (event.data()?.coachUids as string[] | undefined) ?? [];
    if (!contact.exists || coachUids.length === 0) return;
    await contact.ref.update({
      visibleToCoachUids: FieldValue.arrayUnion(...coachUids),
      updatedAt: this.stamp(),
    });
  }
  // Both registerIdentity and addWalkIn reserve this exact mapping in a transaction.
  async reserveIdentity(
    userId: string,
    email: string,
  ): Promise<{ uid: string; created: boolean }> {
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.doc(`emailIdentities/${email}`);
      const [mapping, existing] = await Promise.all([
        tx.get(ref),
        tx.get(this.db.doc(`users/${userId}`)),
      ]);
      if (mapping.exists) {
        const canonical = uid(mapping.data()!.uid);
        const p = await tx.get(this.db.doc(`users/${canonical}`));
        if (!p.exists || p.data()!.mergedInto !== null)
          fail(
            "failed-precondition",
            "identity-conflict",
            "Identity needs admin resolution",
          );
        return { uid: canonical, created: false };
      }
      if (
        existing.exists &&
        (existing.data()!.emailLower !== email ||
          existing.data()!.mergedInto !== null)
      ) {
        fail(
          "failed-precondition",
          "identity-conflict",
          "Profile email or merge needs admin resolution",
        );
      }
      if (!existing.exists) {
        tx.create(
          this.db.doc(`users/${userId}`),
          this.baseProfile(userId, email),
        );
        tx.create(
          this.db.doc(`users/${userId}/private/contact`),
          this.baseContact(),
        );
      }
      tx.create(ref, {
        uid: userId,
        emailLower: email,
        createdAt: this.stamp(),
      });
      return { uid: userId, created: !existing.exists };
    });
  }
  async registerIdentity(who: Identity, value: unknown) {
    const d = input(value, ["email"]);
    const email = d.email === undefined ? who.email : normalizeEmail(d.email);
    if (email !== who.email)
      fail(
        "permission-denied",
        "email-mismatch",
        "Use your verified account email",
      );
    // Recheck authoritative Auth state, not an arbitrary request email or a stale verification token.
    const account = await this.auth.getUser(who.uid);
    if (
      !account.emailVerified ||
      account.disabled ||
      normalizeEmail(account.email) !== email
    ) {
      fail(
        "permission-denied",
        "email-mismatch",
        "Use your current verified account email",
      );
    }
    const result = await this.reserveIdentity(who.uid, email);
    return { ...result, requiresSignIn: result.uid !== who.uid };
  }
  async rotateEventSecret(who: Identity, value: unknown) {
    const d = input(value, ["eventId"]);
    const eventId = id(d.eventId, "eventId");
    const secret = randomBytes(32).toString("base64url");
    return this.db.runTransaction(async (tx) => {
      const p = await this.actor(tx, who),
        e = await this.event(tx, eventId);
      this.authorize(p, who, e);
      if (e.status !== "published" || e.endsAt.toMillis() <= this.now())
        fail(
          "failed-precondition",
          "event-unavailable",
          "Event has ended or is unavailable",
        );
      const ref = this.db.doc(`eventSecrets/${eventId}`),
        old = await tx.get(ref);
      const code = id(e.code, "eventCode");
      const expiresAt = Timestamp.fromMillis(
        Math.min(this.now() + 300000, e.endsAt.toMillis()),
      );
      const generation = (old.data()?.generation ?? 0) + 1;
      tx.set(ref, {
        currentSecretHash: hash(secret),
        rotatedAt: this.stamp(),
        expiresAt,
        generation,
      });
      return {
        eventId,
        eventCode: code,
        url: `https://rally4ever.org/c/${encodeURIComponent(code)}?k=${secret}`,
        secret,
        generation,
        expiresAt: expiresAt.toDate().toISOString(),
      };
    });
  }
  async checkIn(
    who: Identity,
    value: unknown,
    trusted: { walkIn?: boolean; identityVerification?: string } = {},
  ) {
    const d = input(value, ["eventCode", "secret", "lat", "lng", "method"]);
    const code = id(d.eventCode, "eventCode"),
      secret = text(d.secret, "secret", 128);
    const lat = coordinate(d.lat, "lat"),
      lng = coordinate(d.lng, "lng");
    const method = d.method ?? "app";
    if (method !== "app" && method !== "camera")
      fail("invalid-argument", "invalid-method", "Use app or camera check-in");
    return this.db.runTransaction(async (tx) => {
      const p = await this.actor(tx, who);
      const matches = await tx.get(
        this.db.collection("events").where("code", "==", code).limit(2),
      );
      if (matches.empty)
        fail("not-found", "event-not-found", "Event not found");
      if (matches.size !== 1)
        fail(
          "failed-precondition",
          "invalid-event",
          "Event code must be unique",
        );
      const e = matches.docs[0].data(),
        eventId = id(matches.docs[0].id, "eventId");
      this.window(e);
      const checkinId = `${eventId}_${who.uid}`,
        ref = this.db.doc(`checkins/${checkinId}`);
      const [old, credentials, rsvp, contact] = await Promise.all([
        tx.get(ref),
        tx.get(this.db.doc(`eventSecrets/${eventId}`)),
        tx.get(this.db.doc(`rsvps/${checkinId}`)),
        tx.get(this.db.doc(`users/${who.uid}/private/contact`)),
      ]);
      if (old.exists)
        fail(
          "already-exists",
          "already-checked-in",
          "You are already checked in",
          { checkinId, status: old.data()!.status },
        );
      const k = credentials.data();
      if (
        !k ||
        k.expiresAt.toMillis() <= this.now() ||
        !secretMatches(secret, k.currentSecretHash)
      ) {
        fail(
          "permission-denied",
          "invalid-secret",
          "This QR code is invalid or expired; ask the coach for a new code",
        );
      }
      const distance = checkDistance(
        lat,
        lng,
        coordinate(e.venue?.lat, "lat"),
        coordinate(e.venue?.lng, "lng"),
        e.geofenceRadiusM ?? 150,
      );
      const missing = await this.missingForms(tx, who.uid, e);
      if (missing.length)
        fail(
          "failed-precondition",
          "unsigned-forms",
          "Sign the current required forms before checking in",
          { missingForms: missing },
        );
      const c = contact.data();
      const missingDetails = ["firstName"].filter(
        (key) => typeof p[key] !== "string" || !p[key].trim(),
      );
      if (typeof c?.mobile !== "string" || !c.mobile.trim())
        missingDetails.push("mobile");
      if (!c?.emergencyContact?.name?.trim() || !c?.emergencyContact?.mobile?.trim())
        missingDetails.push("emergencyContact");
      if (missingDetails.length)
        fail(
          "failed-precondition",
          "missing-details",
          "Complete your details before checking in",
          { missingDetails },
        );
      tx.create(ref, {
        eventId,
        uid: who.uid,
        scannedAt: this.stamp(),
        method,
        lat,
        lng,
        distanceM: distance,
        status: "pending",
        confirmedBy: null,
        confirmedAt: null,
        walkIn:
          trusted.walkIn ?? (!rsvp.exists || rsvp.data()!.cancelledAt !== null),
        identityVerification: trusted.identityVerification ?? "account",
        corrections: [],
        eventEndsAt: e.endsAt,
        feedbackReminderPending: false,
      });
      // A real check-in is as strong a relationship as an RSVP -- grant the
      // event's coaches contact visibility (covers walk-ins who never RSVP'd).
      if (contact.exists && (e.coachUids as string[] | undefined)?.length) {
        tx.update(contact.ref, {
          visibleToCoachUids: FieldValue.arrayUnion(...(e.coachUids as string[])),
          updatedAt: this.stamp(),
        });
      }
      return { checkinId, eventId, status: "pending", distanceM: distance };
    });
  }
  async coachDecision(who: Identity, value: unknown) {
    const d = input(value, ["eventId", "uid", "decision"]);
    const eventId = id(d.eventId, "eventId"),
      participant = uid(d.uid);
    if (d.decision !== "confirm" && d.decision !== "reject")
      fail("invalid-argument", "invalid-decision", "Choose confirm or reject");
    const status = d.decision === "confirm" ? "confirmed" : "rejected";
    return this.db.runTransaction(async (tx) => {
      const p = await this.actor(tx, who),
        e = await this.event(tx, eventId);
      this.authorize(p, who, e);
      const checkinId = `${eventId}_${participant}`,
        ref = this.db.doc(`checkins/${checkinId}`),
        scan = await tx.get(ref);
      if (!scan.exists)
        fail("not-found", "checkin-not-found", "Check-in not found");
      if (scan.data()!.status === status)
        return { checkinId, status, unchanged: true };
      if (scan.data()!.status !== "pending")
        fail(
          "failed-precondition",
          "decision-already-made",
          "Use an attendance correction to change this decision",
        );
      tx.update(ref, {
        status,
        confirmedBy: who.uid,
        confirmedAt: this.stamp(),
        feedbackReminderPending: status === "confirmed",
      });
      return { checkinId, status, unchanged: false };
    });
  }
  async correctAttendance(who: Identity, value: unknown) {
    const d = input(value, ["eventId", "uid", "status", "reason"]);
    const eventId = id(d.eventId, "eventId"),
      participant = uid(d.uid),
      reason = text(d.reason, "reason", 1000);
    if (!["pending", "confirmed", "rejected"].includes(d.status as string))
      fail("invalid-argument", "invalid-status", "Invalid attendance status");
    return this.db.runTransaction(async (tx) => {
      const p = await this.actor(tx, who),
        e = await this.event(tx, eventId);
      this.authorize(p, who, e);
      const checkinId = `${eventId}_${participant}`,
        ref = this.db.doc(`checkins/${checkinId}`),
        scan = await tx.get(ref);
      if (!scan.exists)
        fail("not-found", "checkin-not-found", "Check-in not found");
      const old = scan.data()!,
        corrections = old.corrections ?? [];
      if (corrections.length >= 100)
        fail(
          "resource-exhausted",
          "correction-limit",
          "Correction history needs admin review",
        );
      tx.update(ref, {
        status: d.status,
        confirmedBy: who.uid,
        confirmedAt: this.stamp(),
        feedbackReminderPending: d.status === "confirmed",
        corrections: [
          ...corrections,
          {
            at: this.stamp(),
            by: who.uid,
            reason,
            previousStatus: old.status,
            newStatus: d.status,
          },
        ],
      });
      return {
        checkinId,
        status: d.status,
        correctionCount: corrections.length + 1,
      };
    });
  }
  async addWalkIn(who: Identity, value: unknown) {
    const d = input(value, [
      "eventId",
      "email",
      "firstName",
      "lastName",
      "mobile",
      "emergencyContact",
      "injuries",
    ]);
    const eventId = id(d.eventId, "eventId"),
      email = normalizeEmail(d.email);
    const details: DocumentData = {};
    for (const [key, max] of [
      ["firstName", 100],
      ["lastName", 100],
      ["injuries", 2000],
    ] as const) {
      if (d[key] !== undefined) details[key] = text(d[key], key, max, 0);
    }
    const contactDetails: DocumentData = {};
    if (d.mobile !== undefined) contactDetails.mobile = text(d.mobile, "mobile", 40, 0);
    if (d.emergencyContact !== undefined) {
      const contact = input(d.emergencyContact, ["name", "mobile"]);
      contactDetails.emergencyContact = {
        name: text(contact.name, "contact.name", 200),
        mobile: text(contact.mobile, "contact.mobile", 40),
      };
    }
    // Authorize before Auth lookup/creation; reauthorize in the write transaction.
    await this.db.runTransaction(async (tx) => {
      this.authorize(
        await this.actor(tx, who),
        who,
        await this.event(tx, eventId),
      );
      this.window(await this.event(tx, eventId));
    });
    const mapping = await this.db.doc(`emailIdentities/${email}`).get();
    let participant: string,
      created = false;
    if (mapping.exists) participant = uid(mapping.data()!.uid);
    else {
      let account;
      try {
        account = await this.auth.getUserByEmail(email);
      } catch (error) {
        if ((error as { code?: string }).code !== "auth/user-not-found")
          throw error;
        try {
          account = await this.auth.createUser({ email, emailVerified: false });
        } catch (createError) {
          if (
            (createError as { code?: string }).code !==
            "auth/email-already-exists"
          )
            throw createError;
          account = await this.auth.getUserByEmail(email);
        }
      }
      const reserved = await this.reserveIdentity(account.uid, email);
      participant = reserved.uid;
      created = reserved.created;
    }
    return this.db.runTransaction(async (tx) => {
      const coach = await this.actor(tx, who),
        e = await this.event(tx, eventId);
      this.authorize(coach, who, e);
      this.window(e);
      const pRef = this.db.doc(`users/${participant}`),
        contactRef = this.db.doc(`users/${participant}/private/contact`),
        [p, c] = await Promise.all([
          tx.get(pRef).then((s) => s.data()),
          tx.get(contactRef).then((s) => s.data()),
        ]);
      if (!p || p.mergedInto !== null)
        fail(
          "failed-precondition",
          "inactive-profile",
          "Profile needs admin resolution",
        );
      const checkinId = `${eventId}_${participant}`,
        ref = this.db.doc(`checkins/${checkinId}`);
      const [old, rsvp] = await Promise.all([
        tx.get(ref),
        tx.get(this.db.doc(`rsvps/${checkinId}`)),
      ]);
      const missing = await this.missingForms(tx, participant, e);
      if (old.exists)
        fail(
          "already-exists",
          "already-checked-in",
          "This participant is already checked in",
          { checkinId, uid: participant },
        );
      // Existing details are not silently overwritten by a different coach.
      const fill: DocumentData = {};
      for (const [key, val] of Object.entries(details)) {
        if (!p[key]) fill[key] = val;
      }
      if (Object.keys(fill).length)
        tx.update(pRef, { ...fill, updatedAt: this.stamp() });
      const contactFill: DocumentData = {};
      for (const [key, val] of Object.entries(contactDetails)) {
        if (key === "emergencyContact" ? !c?.emergencyContact?.name : !c?.[key])
          contactFill[key] = val;
      }
      if (Object.keys(contactFill).length)
        tx.update(contactRef, { ...contactFill, updatedAt: this.stamp() });
      if (!rsvp.exists)
        tx.create(this.db.doc(`rsvps/${checkinId}`), {
          eventId,
          uid: participant,
          createdAt: this.stamp(),
          cancelledAt: null,
          source: "coach-added",
        });
      if (missing.length)
        return {
          uid: participant,
          created,
          status: "awaiting-forms",
          missingForms: missing,
          checkinId: null,
        };
      tx.create(ref, {
        eventId,
        uid: participant,
        scannedAt: this.stamp(),
        method: "manual",
        lat: null,
        lng: null,
        distanceM: null,
        status: "pending",
        confirmedBy: null,
        confirmedAt: null,
        walkIn: true,
        corrections: [],
        eventEndsAt: e.endsAt,
        feedbackReminderPending: false,
      });
      return {
        uid: participant,
        created,
        status: "pending",
        missingForms: [],
        checkinId,
      };
    });
  }
}
