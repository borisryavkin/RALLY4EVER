import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { authIdentity, input, id } from "./domain";
import { AttendanceService } from "./service";
import { MergeService } from "./merge";
import { NotificationService } from "./notifications";
import { rateLimit } from "./rate_limits";
import { NoAppService } from "./no_app";
import { AdminRoleService } from "./admin_roles";

setGlobalOptions({ region: "australia-southeast1", maxInstances: 1 });
const app = initializeApp({ projectId: "demo-rally4ever" });
const db = getFirestore(app),
  service = new AttendanceService({ db, auth: getAuth(app) });
const merge = new MergeService(service);

export function assertLocal(): void {
  if (
    process.env.FUNCTIONS_EMULATOR !== "true" ||
    process.env.GCLOUD_PROJECT !== "demo-rally4ever" ||
    process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8080" ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9099"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "This build runs only in the local demo emulators",
      { reason: "emulator-only" },
    );
  }
}
// Deterministic local delivery double. No FCM SDK or external send is used in this build.
const notifications = new NotificationService(
  service,
  async (notificationId, note, tokens) => {
    assertLocal();
    await db.doc(`emulatorPushes/${notificationId}`).set({
      notificationId,
      uid: note.uid,
      eventId: note.eventId,
      type: note.type,
      route: note.route,
      tokenCount: tokens.length,
      recordedAt: service.stamp(),
    });
  },
);
const callable = (
  handler: (
    who: ReturnType<typeof authIdentity>,
    data: unknown,
  ) => Promise<unknown>,
) =>
  onCall(async (request) => {
    assertLocal();
    const who = authIdentity(request.auth);
    try {
      return await handler(who, request.data);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error(
        "Attendance operation failed",
        error instanceof Error ? error.message : "Unknown error",
      );
      throw new HttpsError(
        "internal",
        "Unable to complete the request; please retry",
        { reason: "internal-error" },
      );
    }
  });
export const registerIdentity = callable((who, data) =>
  rateLimit(db, "registerIdentity", who.uid, 20, 3600000).then(() =>
    service.registerIdentity(who, data),
  ),
);
export const rotateEventSecret = callable((who, data) =>
  service.rotateEventSecret(who, data),
);
export const checkIn = callable((who, data) =>
  rateLimit(db, "checkIn", who.uid, 10, 60000).then(() =>
    service.checkIn(who, data),
  ),
);
export const coachDecision = callable((who, data) =>
  service.coachDecision(who, data),
);
export const correctAttendance = callable((who, data) =>
  service.correctAttendance(who, data),
);
export const addWalkIn = callable((who, data) => service.addWalkIn(who, data));
export const mergeProfiles = callable((who, data) =>
  merge.mergeProfiles(who, data),
);
export const notifyCoachesOnCheckIn = onDocumentCreated(
  { document: "checkins/{checkinId}", retry: true },
  async (event) => {
    assertLocal();
    try {
      await notifications.notifyCoaches(event.params.checkinId);
    } catch (error) {
      // A merge or local test reset may remove a scan while a trigger is in flight.
      if (!(await db.doc(`checkins/${event.params.checkinId}`).get()).exists)
        return;
      throw error;
    }
  },
);
export const sendFeedbackReminders = onSchedule("every 5 minutes", async () => {
  assertLocal();
  await notifications.feedbackReminders();
});

const noApp = new NoAppService(service);
export const beginNoAppCheckIn = onCall(async (request) => {
  assertLocal();
  return noApp.begin(request.data, request.rawRequest.ip ?? "local");
});
export const completeNoAppCheckIn = onCall(async (request) => {
  assertLocal();
  return noApp.complete(request.data, request.rawRequest.ip ?? "local");
});

export const getCountedIn = callable(async (who, value) => {
  const d = input(value, ["eventId"]),
    eventId = id(d.eventId, "eventId");
  await db.runTransaction(async (tx) => {
    await service.actor(tx, who);
    const event = await service.event(tx, eventId);
    if (event.status !== "published")
      throw new HttpsError("permission-denied", "Event is not public");
  });
  const intents = await db
    .collection("rsvps")
    .where("eventId", "==", eventId)
    .where("cancelledAt", "==", null)
    .limit(200)
    .get();
  const people = [];
  for (const intent of intents.docs) {
    const p = (await db.doc(`users/${intent.data().uid}`).get()).data();
    if (
      p &&
      p.mergedInto === null &&
      (p.preferences?.showInWhosGoing === true || p.uid === who.uid)
    )
      people.push({
        label: p.uid === who.uid ? "You" : p.firstName || "Member",
        initials: (p.firstName || "M").slice(0, 1),
        isYou: p.uid === who.uid,
      });
  }
  return { count: intents.size, people };
});

export const getNoAppForms = onCall(async (request) => {
  assertLocal();
  await rateLimit(
    db,
    "noapp-info",
    request.rawRequest.ip ?? "local",
    20,
    60000,
  );
  const d = input(request.data, ["eventCode", "secret", "lat", "lng"]);
  const { e, eventId } = await noApp.validate(d);
  const forms = [];
  for (const formId of e.requiredFormIds) {
    const f = await db.doc(`forms/${formId}`).get();
    if (f.exists) forms.push({ id: formId, ...f.data() });
  }
  return { eventId, name: e.name, forms };
});

const roles = new AdminRoleService(service);
export const listUsers = callable((who, data) => roles.listUsers(who, data));
export const setUserRole = callable((who, data) =>
  roles.setUserRole(who, data),
);
export const assignEventCoaches = callable((who, data) =>
  roles.assignEventCoaches(who, data),
);
export const coachOverview = callable((who, data) =>
  roles.coachOverview(who, data),
);
