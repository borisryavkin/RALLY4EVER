import {sealVenuePhoto} from './venue_photos';
import {AdminConsoleService} from './admin_console';
import { StaffService } from './staff';
import { CatalogueService } from "./catalogue";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { authIdentity, input, id } from "./domain";
import { AttendanceService } from "./service";
import { MergeService } from "./merge";
import { NotificationService } from "./notifications";
import { rateLimit } from "./rate_limits";
import { NoAppService } from "./no_app";
import { AdminRoleService } from "./admin_roles";
import { assertEmulatorNetwork, assertApprovedProject } from "./emulator_network";

setGlobalOptions({ region: "australia-southeast1", maxInstances: 1 });
// No projectId here: resolve from the runtime's own environment (the real
// project when deployed, the emulator's GCLOUD_PROJECT when run locally).
// A hardcoded project here previously made deployed functions verify real
// Firebase ID tokens against the wrong "aud", rejecting every real caller.
const app = initializeApp();
const db = getFirestore(app),
  service = new AttendanceService({ db, auth: getAuth(app) });
const merge = new MergeService(service);

// Passes for the local demo emulator or the one real project these
// functions are approved to run against (see emulator_network.ts). Covers
// everything that only reads/writes via the Admin SDK.
export function assertApprovedBackend(): void {
  try {
    assertApprovedProject();
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "This function is not available in this environment",
      { reason: "unapproved-backend" },
    );
  }
}
// The "no app" walk-in flow calls the local Auth emulator's REST API
// directly (see emulator_network.ts) and has no real-project
// implementation yet, so it stays emulator-only regardless of project.
export function assertEmulatorOnly(): void {
  try {
    assertEmulatorNetwork();
  } catch {
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
    assertApprovedBackend();
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
  // Browser callables need a public transport endpoint; verified Firebase Auth
  // and protected role checks below still authorize every request.
  onCall({invoker: "public"}, async (request) => {
    assertApprovedBackend();
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
    assertApprovedBackend();
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
  assertApprovedBackend();
  await notifications.feedbackReminders();
});

const noApp = new NoAppService(service);
export const beginNoAppCheckIn = onCall({invoker: "public"}, async (request) => {
  assertApprovedBackend();
  return noApp.begin(request.data, request.rawRequest.ip ?? "local");
});
export const completeNoAppCheckIn = onCall({invoker: "public"}, async (request) => {
  assertApprovedBackend();
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

export const getNoAppForms = onCall({invoker:"public"}, async request => {
  assertApprovedBackend();return noApp.info(request.data,request.rawRequest.ip??'local');
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
export const removeParticipantPhoto = callable((who, data) =>
  roles.removeParticipantPhoto(who, data),
);

const catalogue = new CatalogueService(service);
export const listPrograms = callable((who, data) => catalogue.listPrograms(who, data));
export const saveProgram = callable((who, data) => catalogue.saveProgram(who, data));
export const saveSession = callable((who, data) => catalogue.saveSession(who, data));
export const setRsvp = callable((who, data) => rateLimit(db, "setRsvp", who.uid, 30, 60000).then(() => catalogue.setRsvp(who, data)));
export const syncSessionAvailability = onDocumentWritten({document:"rsvps/{rsvpId}",retry:true}, async (event) => {
  assertApprovedBackend();
  const before = event.data?.before.data(), after = event.data?.after.data();
  const ids = new Set([before?.eventId, after?.eventId].filter((id): id is string => typeof id === "string" && /^[a-zA-Z0-9-]{1,128}$/.test(id)));
  for (const eventId of ids) await catalogue.reconcileAvailability(eventId);
  // An RSVP (including a legacy direct-write "Count me in") is a real
  // relationship with the event's coaches -- grant them contact visibility.
  const rsvpUid = (after?.uid ?? before?.uid) as string | undefined;
  if (rsvpUid) {
    for (const eventId of ids) await service.syncContactVisibility(eventId, rsvpUid);
  }
});

const staff = new StaffService(service);
export const listStaffSessions = callable((who, data) => staff.listStaffSessions(who, data));
export const getEventConsole = callable((who, data) => staff.getEventConsole(who, data));

export const cancelSession = callable((who, data) => catalogue.cancelSession(who, data));

const adminConsole = new AdminConsoleService(service, url=>sealVenuePhoto(app,url));
export const adminCatalogue = callable((who,data)=>adminConsole.catalogue(who,data));
export const adminSaveSession = callable((who,data)=>adminConsole.saveSession(who,data));
export const adminSaveVenue = callable((who,data)=>adminConsole.saveVenue(who,data));
export const adminSetPhoto = callable((who,data)=>adminConsole.setPhoto(who,data));
export const adminRemoveDemo = callable((who,data)=>adminConsole.demo(who,data));
