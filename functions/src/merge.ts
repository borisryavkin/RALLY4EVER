import {
  DocumentData,
  DocumentSnapshot,
  Transaction,
} from "firebase-admin/firestore";
import { Identity, input, id, text, fail, hash, normalizeEmail } from "./domain";
import { AttendanceService, uid } from "./service";

interface Move {
  from: string;
  to: string;
  data: DocumentData;
}
export class MergeService {
  constructor(readonly service: AttendanceService) {}
  async collect(tx: Transaction, source: string, target: string) {
    const { db } = this.service;
    const sourceRef = db.doc(`users/${source}`),
      targetRef = db.doc(`users/${target}`);
    const [a, b] = await Promise.all([tx.get(sourceRef), tx.get(targetRef)]);
    if (!a.exists || !b.exists)
      fail("not-found", "profile-not-found", "Both profiles must exist");
    if (a.data()!.mergedInto !== null || b.data()!.mergedInto !== null)
      fail(
        "failed-precondition",
        "already-merged",
        "Use active source and target profiles",
      );
    if (a.data()!.role !== "participant" || b.data()!.role !== "participant")
      fail(
        "failed-precondition",
        "privileged-profile",
        "Only participant profiles can be merged",
      );
    const snapshots: DocumentSnapshot[] = [a, b];
    const moves: Move[] = [],
      conflicts: string[] = [];
    const aliases = await tx.get(
      db.collection("emailIdentities").where("uid", "==", source).limit(201),
    );
    if (aliases.size > 200)
      fail(
        "resource-exhausted",
        "merge-too-large",
        "Merge exceeds safe transaction size",
      );
    snapshots.push(...aliases.docs);
    for (const name of [
      "rsvps",
      "checkins",
      "consents",
      "feedback",
      "notifications",
    ]) {
      const found = await tx.get(
        db.collection(name).where("uid", "==", source).limit(201),
      );
      if (found.size > 200)
        fail(
          "resource-exhausted",
          "merge-too-large",
          "Merge exceeds safe transaction size",
        );
      for (const old of found.docs) {
        const data = old.data();
        let targetId: string;
        if (name === "consents")
          targetId = `${target}_${id(data.formId, "formId")}`;
        else if (name === "notifications") {
          if (!old.id.endsWith(`_${source}`))
            fail(
              "failed-precondition",
              "invalid-reference",
              "Notification ID does not match recipient",
            );
          targetId = old.id.slice(0, -source.length) + target;
        } else targetId = `${id(data.eventId, "eventId")}_${target}`;
        const dest = db.doc(`${name}/${targetId}`),
          exists = await tx.get(dest);
        snapshots.push(old, exists);
        if (exists.exists) conflicts.push(dest.path);
        moves.push({
          from: old.ref.path,
          to: dest.path,
          data: { ...data, uid: target, mergedFromUid: source },
        });
      }
    }
    const writes = moves.length * 2 + aliases.size + 3;
    if (writes > 400)
      fail(
        "resource-exhausted",
        "merge-too-large",
        "Merge exceeds safe transaction size",
      );
    const originals = snapshots
      .filter((s) => s.exists)
      .map((s) => ({ path: s.ref.path, data: s.data() }));
    if (Buffer.byteLength(JSON.stringify(originals)) > 500000)
      fail(
        "resource-exhausted",
        "merge-too-large",
        "Merge audit would be too large",
      );
    const revision = snapshots
      .map(
        (s) =>
          `${s.ref.path}:${s.updateTime?.seconds ?? "missing"}:${s.updateTime?.nanoseconds ?? ""}`,
      )
      .sort()
      .join("|");
    return {
      source: a,
      target: b,
      moves,
      aliases: aliases.docs,
      conflicts,
      originals,
      fingerprint: hash(revision),
      writes,
    };
  }
  async mergeProfiles(who: Identity, value: unknown) {
    const d = input(value, [
      "sourceUid",
      "targetUid",
      "reason",
      "dryRun",
      "dryRunId",
      "email",
    ]);
    const source = uid(d.sourceUid),
      target = uid(d.targetUid),
      reason = text(d.reason, "reason", 1000);
    if (source === target)
      fail(
        "invalid-argument",
        "same-profile",
        "Choose distinct source and target profiles",
      );
    if (d.dryRun !== undefined && typeof d.dryRun !== "boolean")
      fail("invalid-argument", "invalid-input", "dryRun must be boolean");
    await this.service.db.runTransaction(async tx=>{
      if((await this.service.actor(tx,who)).role!=='admin')fail('permission-denied','admin-required','Admin role required');
    });
    const targetAccount=await this.service.auth.getUser(target);
    if(targetAccount.disabled||!targetAccount.emailVerified)fail('failed-precondition','unverified-target','The canonical account must have a verified email');
    const verifiedEmail=normalizeEmail(targetAccount.email);
    if(d.email!==undefined&&normalizeEmail(d.email)!==verifiedEmail)fail('permission-denied','email-mismatch','Use the canonical verified email');
    const dryRun = d.dryRun !== false;
    const auditRef = dryRun
      ? this.service.db.collection("mergeAudits").doc()
      : this.service.db.doc(`mergeAudits/${id(d.dryRunId, "dryRunId")}`);
    return this.service.db.runTransaction(async (tx) => {
      if ((await this.service.actor(tx, who)).role !== "admin")
        fail("permission-denied", "admin-required", "Admin role required");
      const previous = dryRun ? null : await tx.get(auditRef);
      if (
        !dryRun &&
        (!previous?.exists ||
          previous.data()!.sourceUid !== source ||
          previous.data()!.targetUid !== target ||
          previous.data()!.actorUid !== who.uid ||
          previous.data()!.reason !== reason)
      ) {
        fail(
          "failed-precondition",
          "dry-run-required",
          "Run and review a dry-run with these exact inputs first",
        );
      }
      if (previous?.data()?.status === "applied")
        return {
          dryRun: false,
          auditId: auditRef.id,
          status: "applied",
          unchanged: true,
        };
      if (
        previous &&
        previous.data()!.createdAt.toMillis() < this.service.now() - 900000
      )
        fail("failed-precondition", "dry-run-expired", "Run a fresh dry-run");
      const plan = await this.collect(tx, source, target);
      if(normalizeEmail(plan.target.data()!.emailLower)!==verifiedEmail)fail('failed-precondition','identity-conflict','Target profile and verified Auth email differ');
      const summary = {
        verifiedEmail,
        sourceEmail:plan.source.data()!.emailLower,
        manualDifferentEmails:plan.source.data()!.emailLower!==verifiedEmail,
        moves: plan.moves.map((m) => ({ from: m.from, to: m.to })),
        aliases: plan.aliases.map((a) => a.id),
        writes: plan.writes,
      };
      if (dryRun) {
        tx.create(auditRef, {
          sourceUid: source,
          targetUid: target,
          actorUid: who.uid,
          reason,
          createdAt: this.service.stamp(),
          status: "dry-run",
          fingerprint: plan.fingerprint,
          conflicts: plan.conflicts,
          summary,
        });
        return {
          dryRun: true,
          auditId: auditRef.id,
          status: "dry-run",
          conflicts: plan.conflicts,
          summary,
        };
      }
      if (plan.fingerprint !== previous!.data()!.fingerprint)
        fail(
          "failed-precondition",
          "stale-dry-run",
          "Data changed; run a fresh dry-run",
        );
      if (plan.conflicts.length)
        fail(
          "failed-precondition",
          "merge-conflicts",
          "Resolve overlapping records before applying",
          { conflicts: plan.conflicts },
        );
      // Move references atomically, retaining complete pre-merge originals in a private audit.
      for (const move of plan.moves) {
        tx.create(this.service.db.doc(move.to), move.data);
        tx.delete(this.service.db.doc(move.from));
      }
      for (const alias of plan.aliases)
        tx.update(alias.ref, { uid: target, updatedAt: this.service.stamp() });
      tx.update(plan.source.ref, {
        mergedInto: target,
        updatedAt: this.service.stamp(),
      });
      tx.update(plan.target.ref, { updatedAt: this.service.stamp() });
      tx.update(auditRef, {
        status: "applied",
        appliedAt: this.service.stamp(),
        originals: plan.originals,
      });
      // Old device tokens stay on the blocked source profile and are never moved to another account.
      return {
        dryRun: false,
        auditId: auditRef.id,
        status: "applied",
        unchanged: false,
        summary,
      };
    });
  }
}
