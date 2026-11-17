import { randomBytes } from "node:crypto";
import { Timestamp } from "firebase-admin/firestore";
import { Identity, input, text, id, fail } from "./domain";
import { AttendanceService, uid } from "./service";

export class AdminRoleService {
  constructor(readonly service: AttendanceService) {}
  async listUsers(who: Identity, value: unknown) {
    const d = input(value, ["query", "cursor"]);
    const search =
      d.query === undefined ? "" : text(d.query, "query", 254, 0).toLowerCase();
    const { db } = this.service;
    await db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin role required");
    });
    let query = db.collection("users").orderBy("emailLower").limit(50);
    if (search) query = query.startAt(search).endAt(search + "\uf8ff");
    if (d.cursor !== undefined)
      query = query.startAfter(text(d.cursor, "cursor", 254));
    const found = await query.get();
    const events = await db
      .collection("events")
      .orderBy("startsAt")
      .limit(100)
      .get();
    return {
      events: events.docs.map((e) => ({
        eventId: e.id,
        name: e.data().name,
        coachUids: e.data().coachUids,
      })),
      users: found.docs.map((doc) => {
        const p = doc.data();
        return {
          uid: doc.id,
          email: p.emailLower,
          firstName: p.firstName,
          role: p.role ?? "participant",
          coachEnabled: p.coachEnabled ?? p.role === "coach",
          mergedInto: p.mergedInto,
        };
      }),
      cursor: found.size === 50 ? found.docs.at(-1)!.data().emailLower : null,
    };
  }
  async setUserRole(who: Identity, value: unknown) {
    const d = input(value, ["uid", "role", "enabled", "reason"]),
      targetUid = uid(d.uid),
      reason = text(d.reason, "reason", 1000);
    if (d.role !== "coach" || typeof d.enabled !== "boolean")
      fail(
        "invalid-argument",
        "invalid-role",
        "Only coach access can be granted or revoked here",
      );
    const { db, auth } = this.service,
      operationId = randomBytes(16).toString("hex");
    const targetRef = db.doc(`users/${targetUid}`),
      lock = db.doc(`roleChanges/${targetUid}`),
      audit = db.doc(`roleAudits/${operationId}`);
    const target = await db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin role required");
      const [p, old] = await Promise.all([tx.get(targetRef), tx.get(lock)]);
      if (!p.exists || p.data()!.mergedInto !== null)
        fail("not-found", "profile-not-found", "Choose an active profile");
      if (
        old.data()?.status === "pending" &&
        old.data()!.expiresAt.toMillis() > this.service.now()
      )
        fail(
          "aborted",
          "role-change-in-progress",
          "Another role update is in progress",
        );
      // Fail closed while Auth and Firestore are updated across two systems.
      tx.update(targetRef, {
        coachEnabled: false,
        updatedAt: this.service.stamp(),
      });
      tx.set(lock, {
        operationId,
        status: "pending",
        expiresAt: Timestamp.fromMillis(this.service.now() + 60000),
      });
      tx.create(audit, {
        operationId,
        actorUid: who.uid,
        targetUid,
        reason,
        enabled: d.enabled,
        action: "coach-role",
        createdAt: this.service.stamp(),
        status: "pending",
      });
      return p.data()!;
    });
    try {
      const account = await auth.getUser(targetUid);
      if (d.enabled && (!account.emailVerified || account.disabled))
        fail(
          "failed-precondition",
          "email-unverified",
          "The coach must verify their account first",
        );
      const previous = account.customClaims ?? {};
      const roles = new Set<string>(
        (Array.isArray(previous.roles) ? previous.roles : []).filter(
          (r: string) => r !== "coach",
        ),
      );
      roles.add("participant");
      if (target.role === "admin") roles.add("admin");
      if (d.enabled) roles.add("coach");
      const role =
        target.role === "admin" ? "admin" : d.enabled ? "coach" : "participant";
      await auth.setCustomUserClaims(targetUid, {
        ...previous,
        role,
        roles: [...roles],
      });
      await db.runTransaction(async (tx) => {
        if ((await this.service.actor(tx, who)).role !== "admin")
          fail("permission-denied", "admin-required", "Admin role required");
        const current = await tx.get(lock);
        if (current.data()?.operationId !== operationId)
          fail(
            "aborted",
            "role-change-in-progress",
            "Role operation superseded",
          );
        tx.update(targetRef, {
          role,
          coachEnabled: d.enabled,
          updatedAt: this.service.stamp(),
        });
        tx.update(lock, { status: "applied" });
        tx.update(audit, {
          status: "applied",
          appliedAt: this.service.stamp(),
        });
      });
      return {
        uid: targetUid,
        roles: [...roles],
        coachEnabled: d.enabled,
        auditId: operationId,
        refreshRequired: true,
      };
    } catch (error) {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(lock);
        if (current.data()?.operationId === operationId) {
          tx.update(lock, { status: "failed" });
          tx.update(audit, { status: "failed" });
        }
      });
      throw error;
    }
  }
  async assignEventCoaches(who: Identity, value: unknown) {
    const d = input(value, ["eventId", "coachUids", "reason"]),
      eventId = id(d.eventId, "eventId"),
      reason = text(d.reason, "reason", 1000);
    if (!Array.isArray(d.coachUids) || d.coachUids.length > 10)
      fail("invalid-argument", "invalid-coaches", "Choose up to ten coaches");
    const coachUids = [...new Set(d.coachUids.map(uid))];
    for (const coachUid of coachUids) {
      const a = await this.service.auth.getUser(coachUid);
      if (
        !a.emailVerified ||
        !(
          a.customClaims?.role === "coach" ||
          a.customClaims?.roles?.includes("coach")
        )
      )
        fail(
          "failed-precondition",
          "coach-claim-required",
          "Every assigned coach needs an admin-issued claim",
        );
    }
    const audit = this.service.db.collection("roleAudits").doc();
    await this.service.db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin role required");
      await this.service.event(tx, eventId);
      for (const coachUid of coachUids) {
        const p = (
          await tx.get(this.service.db.doc(`users/${coachUid}`))
        ).data();
        if (
          !p ||
          p.mergedInto !== null ||
          p.coachEnabled === false ||
          !["coach", "admin"].includes(p.role)
        )
          fail(
            "failed-precondition",
            "coach-claim-required",
            "Coach access has been revoked",
          );
      }
      tx.update(this.service.db.doc(`events/${eventId}`), {
        coachUids,
        updatedAt: this.service.stamp(),
      });
      tx.create(audit, {
        actorUid: who.uid,
        eventId,
        coachUids,
        reason,
        action: "assign-event",
        status: "applied",
        createdAt: this.service.stamp(),
      });
    });
    return { eventId, coachUids, auditId: audit.id };
  }
  async coachOverview(who: Identity, value: unknown) {
    input(value, []);
    const { db } = this.service;
    await db.runTransaction(async (tx) => {
      const p = await this.service.actor(tx, who);
      if (p.role !== "coach" && p.role !== "admin")
        fail(
          "permission-denied",
          "coach-claim-required",
          "Ask your admin for coach access",
        );
    });
    const events = await db
      .collection("events")
      .where("coachUids", "array-contains", who.uid)
      .limit(50)
      .get();
    const pending = [];
    for (const e of events.docs) {
      const scans = await db
        .collection("checkins")
        .where("eventId", "==", e.id)
        .where("status", "==", "pending")
        .limit(100)
        .get();
      for (const scan of scans.docs) {
        const s = scan.data();
        const p = (await db.doc(`users/${s.uid}`).get()).data();
        pending.push({
          checkinId: scan.id,
          eventId: e.id,
          eventName: e.data().name,
          firstName: p?.firstName ?? "Member",
          scannedAt: s.scannedAt.toDate().toISOString(),
          distanceM: s.distanceM,
          identityVerification: s.identityVerification ?? "account",
          status: "pending",
        });
      }
    }
    return {
      events: events.docs.map((e) => ({ eventId: e.id, name: e.data().name })),
      pending,
    };
  }
}
