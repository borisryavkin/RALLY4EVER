import { DocumentData, Timestamp } from "firebase-admin/firestore";
import { AttendanceService } from "./service";

export type PushSender = (
  id: string,
  note: DocumentData,
  tokens: string[],
) => Promise<void>;
export class NotificationService {
  constructor(
    readonly service: AttendanceService,
    readonly send: PushSender,
  ) {}
  async deliver(notificationId: string): Promise<boolean> {
    const { db, now } = this.service,
      ref = db.doc(`notifications/${notificationId}`);
    const claimed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref),
        n = snap.data();
      if (
        !n ||
        n.deliveryStatus === "sent" ||
        n.deliveryStatus === "dead" ||
        (n.leaseUntil?.toMillis() ?? 0) > now()
      )
        return null;
      const p = await tx.get(db.doc(`users/${n.uid}`));
      if (!p.exists || p.data()!.mergedInto !== null) {
        tx.update(ref, { deliveryStatus: "suppressed", leaseUntil: null });
        return null;
      }
      if (n.type === "feedback") {
        const scan = await tx.get(db.doc(`checkins/${n.eventId}_${n.uid}`));
        if (!scan.exists || scan.data()!.status !== "confirmed") {
          tx.update(ref, { deliveryStatus: "suppressed", leaseUntil: null });
          return null;
        }
      }
      const devices = await tx.get(db.collection(`users/${n.uid}/devices`));
      const attempts = (n.attempts ?? 0) + 1;
      if (attempts > 5) {
        tx.update(ref, { deliveryStatus: "dead", leaseUntil: null });
        return null;
      }
      tx.update(ref, {
        deliveryStatus: "sending",
        attempts,
        leaseUntil: Timestamp.fromMillis(now() + 60000),
      });
      return {
        note: n,
        tokens: devices.docs
          .map((d) => d.data().token)
          .filter((t) => typeof t === "string"),
        attempts,
      };
    });
    if (!claimed) return false;
    try {
      await this.send(notificationId, claimed.note, claimed.tokens);
      await ref.update({
        deliveryStatus: "sent",
        sentAt: this.service.stamp(),
        leaseUntil: null,
        lastError: null,
      });
      return true;
    } catch {
      await ref.update({
        deliveryStatus: claimed.attempts >= 5 ? "dead" : "failed",
        leaseUntil: null,
        lastError: "push-send-failed",
      });
      return false;
    }
  }
  async notifyCoaches(checkinId: string): Promise<number> {
    const { db } = this.service;
    const initial = await db.doc(`checkins/${checkinId}`).get();
    if (
      !initial.exists ||
      initial.data()!.status !== "pending" ||
      initial.data()!.mergedFromUid
    )
      return 0;
    const e = await db.doc(`events/${initial.data()!.eventId}`).get();
    if (!e.exists) return 0;
    let queued = 0;
    for (const coachUid of e.data()!.coachUids ?? []) {
      // Match callable/rule role fallback when a trusted profile uses claims only.
      const coachProfile = await db.doc(`users/${coachUid}`).get();
      let claimRole: unknown;
      if (coachProfile.exists && coachProfile.data()!.role === undefined) {
        try {
          claimRole = (await this.service.auth.getUser(coachUid)).customClaims
            ?.role;
        } catch (error) {
          if ((error as { code?: string }).code === "auth/user-not-found")
            continue;
          throw error;
        }
      }

      const notificationId = `checkin-${initial.data()!.uid}_${initial.data()!.eventId}_${coachUid}`;
      const created = await db.runTransaction(async (tx) => {
        const [scan, currentEvent, coach, old] = await Promise.all([
          tx.get(initial.ref),
          tx.get(e.ref),
          tx.get(db.doc(`users/${coachUid}`)),
          tx.get(db.doc(`notifications/${notificationId}`)),
        ]);
        if (
          !scan.exists ||
          scan.data()!.status !== "pending" ||
          !currentEvent.data()?.coachUids?.includes(coachUid) ||
          !coach.exists ||
          coach.data()!.mergedInto !== null ||
          (coach.data()!.role ?? claimRole) !== "coach" ||
          old.exists
        )
          return false;
        tx.create(db.doc(`notifications/${notificationId}`), {
          type: `checkin-${scan.data()!.uid}`,
          eventId: scan.data()!.eventId,
          uid: coachUid,
          attendeeUid: scan.data()!.uid,
          createdAt: this.service.stamp(),
          readAt: null,
          deliveryStatus: "pending",
          attempts: 0,
          leaseUntil: null,
          sentAt: null,
          route: `/coach/events/${scan.data()!.eventId}/checkins`,
        });
        return true;
      });
      if (created) queued++;
      await this.deliver(notificationId);
    }
    return queued;
  }
  async feedbackReminders(): Promise<{ queued: number; delivered: number }> {
    const { db, now } = this.service;
    const due = await db
      .collection("checkins")
      .where("status", "==", "confirmed")
      .where("feedbackReminderPending", "==", true)
      .where("eventEndsAt", "<=", Timestamp.fromMillis(now() - 2400000))
      .orderBy("eventEndsAt")
      .limit(100)
      .get();
    let queued = 0;
    for (const candidate of due.docs) {
      const made = await db.runTransaction(async (tx) => {
        const scan = await tx.get(candidate.ref),
          s = scan.data();
        if (
          !s ||
          s.status !== "confirmed" ||
          !s.feedbackReminderPending ||
          s.eventEndsAt.toMillis() > now() - 2400000
        )
          return false;
        const notificationId = `feedback_${s.eventId}_${s.uid}`,
          note = db.doc(`notifications/${notificationId}`);
        const [old, e, p] = await Promise.all([
          tx.get(note),
          tx.get(db.doc(`events/${s.eventId}`)),
          tx.get(db.doc(`users/${s.uid}`)),
        ]);
        // Recheck authoritative event end in case an event was extended.
        if (!e.exists || e.data()!.endsAt.toMillis() > now() - 2400000) {
          if (e.exists)
            tx.update(candidate.ref, { eventEndsAt: e.data()!.endsAt });
          return false;
        }
        tx.update(candidate.ref, { feedbackReminderPending: false });
        if (
          old.exists ||
          !p.exists ||
          p.data()!.mergedInto !== null ||
          e.data()!.status === "cancelled"
        )
          return false;
        tx.create(note, {
          type: "feedback",
          eventId: s.eventId,
          uid: s.uid,
          createdAt: this.service.stamp(),
          readAt: null,
          deliveryStatus: "pending",
          attempts: 0,
          leaseUntil: null,
          sentAt: null,
          route: `/feedback/${s.eventId}`,
        });
        return true;
      });
      if (made) queued++;
    }
    const outstanding = await db
      .collection("notifications")
      .where("deliveryStatus", "in", ["pending", "failed", "sending"])
      .limit(100)
      .get();
    let delivered = 0;
    for (const note of outstanding.docs)
      if (await this.deliver(note.id)) delivered++;
    return { queued, delivered };
  }
}
