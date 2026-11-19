const { test, before, after, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { AttendanceService } = require("../lib/service");
const { MergeService } = require("../lib/merge");
const { NotificationService } = require("../lib/notifications");
let app, db, auth, service, seed;
const tokens = new Map();
const identity = (uid, role = "participant") => ({
  uid,
  email:
    uid === "admin-1"
      ? "admin@rally4ever.org"
      : uid === "coach-1"
        ? "dan@rally4ever.org"
        : `member${uid.split("-")[1]}@example.test`,
  role,
});
const stamp = () => Timestamp.now();
async function login(email, password = "Emulator-only-Password-123!") {
  const response = await fetch(
    "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const result = await response.json();
  if (!response.ok) throw new Error(JSON.stringify(result));
  return result.idToken;
}
async function token(uid) {
  if (!tokens.has(uid))
    tokens.set(uid, await login((await auth.getUser(uid)).email));
  return tokens.get(uid);
}
async function call(name, data, uid = "participant-1") {
  const response = await fetch(
    `http://127.0.0.1:5001/demo-rally4ever/australia-southeast1/${name}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(uid ? { authorization: `Bearer ${await token(uid)}` } : {}),
      },
      body: JSON.stringify({ data }),
    },
  );
  const body = await response.json();
  if (body.error) {
    const e = new Error(body.error.message);
    Object.assign(e, body.error);
    throw e;
  }
  assert.ok(response.ok, JSON.stringify(body));
  return body.result;
}
const error = (fn, reason, status) =>
  assert.rejects(
    fn,
    (e) => e.details?.reason === reason && (!status || e.status === status),
  );
const nativeError = (fn, reason) =>
  assert.rejects(fn, (e) => e.details?.reason === reason);
async function rotate(eventId = "event-1", who = "coach-1") {
  return call("rotateEventSecret", { eventId }, who);
}
async function scan(extra = {}, who = "participant-1") {
  const qr = await rotate();
  return call(
    "checkIn",
    {
      eventCode: qr.eventCode,
      secret: qr.secret,
      lat: -33.8926,
      lng: 151.2511,
      ...extra,
    },
    who,
  );
}
async function sign(uid) {
  for (const formId of ["conduct", "waiver"])
    await db
      .doc(`consents/${uid}_${formId}`)
      .set({ uid, formId, formType: formId, version: 1, signedAt: stamp() });
}
async function eventually(fn) {
  const until = Date.now() + 15000;
  let last;
  while (Date.now() < until) {
    try {
      return await fn();
    } catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  throw last;
}
before(async () => {
  const env = await import("../../scripts/emulator-env.mjs");
  env.requireEmulators();
  ({ seed } = await import("../../scripts/seed.mjs"));
  app = initializeApp({ projectId: "demo-rally4ever" }, "function-tests");
  db = getFirestore(app);
  auth = getAuth(app);
  service = new AttendanceService({ db, auth });
});
after(async () => {
  if (app) await deleteApp(app);
});
beforeEach(async () => {
  const response = await fetch(
    "http://127.0.0.1:8080/emulator/v1/projects/demo-rally4ever/databases/(default)/documents",
    { method: "DELETE" },
  );
  assert.ok(response.ok);
  await seed();
  await db.doc("checkins/event-3_participant-1").delete();
  for (const uid of ["participant-1", "participant-2"]) {
    await db.doc(`users/${uid}/private/contact`).set({
      mobile: "0400000000",
      mobileVerified: false,
      emergencyContact: { name: "Emergency Contact", mobile: "0400000001" },
      visibleToCoachUids: [],
      updatedAt: Timestamp.now(),
    });
    await sign(uid);
  }
});

test("HTTP registerIdentity requires verified auth and current matching email", async () => {
  await error(
    () => call("registerIdentity", {}, null),
    "sign-in-required",
    "UNAUTHENTICATED",
  );
  await error(
    () => call("registerIdentity", { email: "member2@example.test" }),
    "email-mismatch",
    "PERMISSION_DENIED",
  );
  const email = `unverified-${Date.now()}@example.test`;
  const user = await auth.createUser({
    email,
    password: "Emulator-only-Password-123!",
  });
  tokens.set(user.uid, await login(email));
  await error(
    () => call("registerIdentity", {}, user.uid),
    "email-unverified",
    "PERMISSION_DENIED",
  );
  assert.equal(
    (await call("registerIdentity", { email: " MEMBER1@EXAMPLE.TEST " })).uid,
    "participant-1",
  );
});
test("concurrent HTTP registration reserves one normalized email and one profile", async () => {
  const email = `signup-${Date.now()}@example.test`;
  const user = await auth.createUser({
    email,
    emailVerified: true,
    password: "Emulator-only-Password-123!",
  });
  tokens.set(user.uid, await login(email));
  const results = await Promise.all(
    Array.from({ length: 8 }, () =>
      call("registerIdentity", { email: ` ${email.toUpperCase()} ` }, user.uid),
    ),
  );
  assert.ok(
    results.every((r) => r.uid === user.uid && r.requiresSignIn === false),
  );
  assert.equal(results.filter((r) => r.created).length, 1);
  assert.equal(
    (await db.collection("users").where("emailLower", "==", email).get()).size,
    1,
  );
  assert.equal(
    (await db.doc(`emailIdentities/${email}`).get()).data().uid,
    user.uid,
  );
});
test("transaction race across candidate UIDs resolves to one canonical profile", async () => {
  const email = "identity-race@example.test";
  const results = await Promise.all([
    service.reserveIdentity("candidate-a", email),
    service.reserveIdentity("candidate-b", email),
  ]);
  assert.equal(results[0].uid, results[1].uid);
  assert.equal(
    (await db.collection("users").where("emailLower", "==", email).get()).size,
    1,
  );
});
test("QR rotation is assigned-coach/admin only and invalidates previous secret", async () => {
  await error(
    () => rotate("event-1", "participant-1"),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  await error(
    () => rotate("event-1", "coach-2"),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  const first = await rotate(),
    second = await rotate();
  assert.equal(second.generation, first.generation + 1);
  assert.match(
    second.url,
    /^https:\/\/rally4ever-checkin-3adaf\.web\.app\/c\/EVENT-1\?k=[A-Za-z0-9_-]+$/,
  );
  const saved = (await db.doc("eventSecrets/event-1").get()).data();
  assert.equal(saved.secret, undefined);
  assert.equal(saved.currentSecretHash.length, 64);
  await error(
    () =>
      call("checkIn", {
        eventCode: first.eventCode,
        secret: first.secret,
        lat: -33.8926,
        lng: 151.2511,
      }),
    "invalid-secret",
    "PERMISSION_DENIED",
  );
  await rotate("event-1", "admin-1");
});
test("checkIn rejects too early, too late and too far with clear reasons", async () => {
  await db.doc("events/event-1").update({
    startsAt: Timestamp.fromMillis(Date.now() + 1200000),
    endsAt: Timestamp.fromMillis(Date.now() + 7200000),
  });
  await error(() => scan(), "too-early", "FAILED_PRECONDITION");
  await db.doc("events/event-1").update({
    startsAt: Timestamp.fromMillis(Date.now() - 7200000),
    endsAt: Timestamp.fromMillis(Date.now() + 3600000),
  });
  const qr = await rotate();
  await db
    .doc("events/event-1")
    .update({ endsAt: Timestamp.fromMillis(Date.now() - 1) });
  await error(
    () =>
      call("checkIn", {
        eventCode: qr.eventCode,
        secret: qr.secret,
        lat: -33.8926,
        lng: 151.2511,
      }),
    "too-late",
    "FAILED_PRECONDITION",
  );
  await db
    .doc("events/event-1")
    .update({ endsAt: Timestamp.fromMillis(Date.now() + 3600000) });
  await error(() => scan({ lat: 0, lng: 0 }), "too-far", "FAILED_PRECONDITION");
});
test("checkIn rejects wrong/expired secret, unsigned/outdated forms and missing details", async () => {
  await error(
    () => scan({ secret: "wrong" }),
    "invalid-secret",
    "PERMISSION_DENIED",
  );
  const qr = await rotate();
  await db
    .doc("eventSecrets/event-1")
    .update({ expiresAt: Timestamp.fromMillis(Date.now() - 1) });
  await error(
    () =>
      call("checkIn", {
        eventCode: qr.eventCode,
        secret: qr.secret,
        lat: -33.8926,
        lng: 151.2511,
      }),
    "invalid-secret",
    "PERMISSION_DENIED",
  );
  await db.doc("consents/participant-1_waiver").delete();
  await error(() => scan(), "unsigned-forms", "FAILED_PRECONDITION");
  await sign("participant-1");
  await db.doc("forms/waiver").update({ version: 2 });
  await error(() => scan(), "unsigned-forms", "FAILED_PRECONDITION");
  await db.doc("forms/waiver").update({ version: 1 });
  await db.doc("users/participant-1/private/contact").update({ mobile: "" });
  await error(() => scan(), "missing-details", "FAILED_PRECONDITION");
});
test("duplicate simultaneous scans create one pending attendance, preserving intent", async () => {
  const qr = await rotate();
  const data = {
    eventCode: qr.eventCode,
    secret: qr.secret,
    lat: -33.8926,
    lng: 151.2511,
    method: "camera",
  };
  const results = await Promise.allSettled([
    call("checkIn", data),
    call("checkIn", data),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const rejection = results.find((r) => r.status === "rejected").reason;
  assert.equal(rejection.details.reason, "already-checked-in");
  const scan = (await db.doc("checkins/event-1_participant-1").get()).data();
  assert.equal(scan.status, "pending");
  assert.equal(scan.method, "camera");
  assert.equal(scan.walkIn, false);
  assert.equal(
    (await db.doc("rsvps/event-1_participant-1").get()).data().source,
    "coach-added",
  );
});
test("new pending check-in invokes actual Firestore trigger once per coach", async () => {
  await scan();
  const path = "notifications/checkin-participant-1_event-1_coach-1";
  await eventually(async () =>
    assert.equal((await db.doc(path).get()).data()?.deliveryStatus, "sent"),
  );
  const fake = (
    await db.doc("emulatorPushes/checkin-participant-1_event-1_coach-1").get()
  ).data();
  assert.equal(fake.uid, "coach-1");
  const local = new NotificationService(service, async () => {
    throw new Error("dedupe failed");
  });
  assert.equal(await local.notifyCoaches("event-1_participant-1"), 0);
  assert.equal(
    (
      await db
        .collection("notifications")
        .where("type", "==", "checkin-participant-1")
        .get()
    ).size,
    1,
  );
});
test("coachDecision rejects non-coach/wrong coach and supports idempotent decisions", async () => {
  await scan();
  const data = {
    eventId: "event-1",
    uid: "participant-1",
    decision: "confirm",
  };
  await error(
    () => call("coachDecision", data, "participant-2"),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  await error(
    () => call("coachDecision", data, "coach-2"),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  assert.equal(
    (await call("coachDecision", data, "coach-1")).status,
    "confirmed",
  );
  assert.equal((await call("coachDecision", data, "coach-1")).unchanged, true);
  await error(
    () => call("coachDecision", { ...data, decision: "reject" }, "coach-1"),
    "decision-already-made",
    "FAILED_PRECONDITION",
  );
  await scan({}, "participant-2");
  assert.equal(
    (
      await call(
        "coachDecision",
        { ...data, uid: "participant-2", decision: "reject" },
        "coach-1",
      )
    ).status,
    "rejected",
  );
});
test("reasoned coach/admin corrections append audit entries and preserve scan", async () => {
  await scan();
  const ref = db.doc("checkins/event-1_participant-1"),
    original = (await ref.get()).data();
  const data = {
    eventId: "event-1",
    uid: "participant-1",
    status: "confirmed",
    reason: "Verified at court",
  };
  await error(
    () => call("correctAttendance", { ...data, reason: " " }, "coach-1"),
    "invalid-input",
    "INVALID_ARGUMENT",
  );
  await error(
    () => call("correctAttendance", data, "coach-2"),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  await call("correctAttendance", data, "coach-1");
  await call(
    "correctAttendance",
    { ...data, status: "rejected", reason: "Correction after roster review" },
    "admin-1",
  );
  const result = (await ref.get()).data();
  assert.equal(result.corrections.length, 2);
  assert.equal(result.corrections[0].by, "coach-1");
  for (const field of [
    "scannedAt",
    "method",
    "lat",
    "lng",
    "distanceM",
    "walkIn",
  ])
    assert.deepEqual(result[field], original[field]);
});
test("walk-in uses existing normalized identity, preserves details and requires signed forms", async () => {
  await db.doc("consents/participant-1_waiver").delete();
  const data = {
    eventId: "event-1",
    email: " MEMBER1@EXAMPLE.TEST ",
    firstName: "Do not overwrite",
  };
  const waiting = await call("addWalkIn", data, "coach-1");
  assert.equal(waiting.uid, "participant-1");
  assert.equal(waiting.status, "awaiting-forms");
  assert.equal(
    (await db.doc("checkins/event-1_participant-1").get()).exists,
    false,
  );
  await sign("participant-1");
  const added = await call("addWalkIn", data, "coach-1");
  assert.equal(added.status, "pending");
  const scan = (await db.doc("checkins/event-1_participant-1").get()).data();
  assert.equal(scan.walkIn, true);
  assert.equal(scan.method, "manual");
  assert.equal(scan.lat, null);
  assert.equal(
    (await db.doc("users/participant-1").get()).data().firstName,
    "participant-1",
  );
  await error(
    () => call("addWalkIn", data, "coach-1"),
    "already-checked-in",
    "ALREADY_EXISTS",
  );
});
test("two coaches adding same new email create one Auth UID/profile, never forge consents", async () => {
  await db.doc("events/event-1").update({ coachUids: ["coach-1", "coach-2"] });
  const email = `walkin-${Date.now()}@example.test`;
  const results = await Promise.all([
    call("addWalkIn", { eventId: "event-1", email }, "coach-1"),
    call(
      "addWalkIn",
      { eventId: "event-1", email: email.toUpperCase() },
      "coach-2",
    ),
  ]);
  assert.equal(results[0].uid, results[1].uid);
  assert.ok(results.every((r) => r.status === "awaiting-forms"));
  assert.equal((await auth.getUserByEmail(email)).uid, results[0].uid);
  assert.equal(
    (await db.collection("users").where("emailLower", "==", email).get()).size,
    1,
  );
  assert.equal(
    (await db.doc(`rsvps/event-1_${results[0].uid}`).get()).data().source,
    "coach-added",
  );
  await error(
    () =>
      call(
        "addWalkIn",
        { eventId: "event-2", email: "unauthorized@example.test" },
        "coach-1",
      ),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  await assert.rejects(
    auth.getUserByEmail("unauthorized@example.test"),
    (e) => e.code === "auth/user-not-found",
  );
});

test("merge dry-run is admin-only, apply requires reviewed fresh plan and writes audit", async () => {
  const data = {
    sourceUid: "participant-2",
    targetUid: "participant-1",
    reason: "Confirmed duplicate identity",
  };
  await db.doc("rsvps/event-2_participant-2").set({
    uid: "participant-2",
    eventId: "event-2",
    source: "coach-added",
    createdAt: stamp(),
    cancelledAt: null,
  });
  // Both already have identical form receipts: collisions must be reviewed, not silently discarded.
  for (const form of ["conduct", "waiver"])
    await db.doc(`consents/participant-2_${form}`).delete();
  await error(
    () => call("mergeProfiles", data, "coach-1"),
    "admin-required",
    "PERMISSION_DENIED",
  );
  const plan = await call("mergeProfiles", data, "admin-1");
  assert.equal(plan.dryRun, true);
  assert.equal(plan.conflicts.length, 0);
  assert.equal(
    (await db.doc("users/participant-2").get()).data().mergedInto,
    null,
  );
  assert.equal(
    (await db.doc("rsvps/event-2_participant-2").get()).exists,
    true,
  );
  await error(
    () =>
      call(
        "mergeProfiles",
        { ...data, dryRun: false, dryRunId: "missing" },
        "admin-1",
      ),
    "dry-run-required",
    "FAILED_PRECONDITION",
  );
  const applied = await call(
    "mergeProfiles",
    { ...data, dryRun: false, dryRunId: plan.auditId },
    "admin-1",
  );
  assert.equal(applied.status, "applied");
  assert.equal(
    (await db.doc("users/participant-2").get()).data().mergedInto,
    "participant-1",
  );
  assert.equal(
    (await db.doc("rsvps/event-2_participant-1").get()).data().uid,
    "participant-1",
  );
  assert.equal(
    (await db.doc("rsvps/event-2_participant-2").get()).exists,
    false,
  );
  assert.equal(
    (await db.doc("emailIdentities/member2@example.test").get()).data().uid,
    "participant-1",
  );
  const audit = (await db.doc(`mergeAudits/${plan.auditId}`).get()).data();
  assert.equal(audit.status, "applied");
  assert.ok(audit.originals.length > 0);
  assert.equal(
    (
      await call(
        "mergeProfiles",
        { ...data, dryRun: false, dryRunId: plan.auditId },
        "admin-1",
      )
    ).unchanged,
    true,
  );
  const canonical = await call("registerIdentity", {}, "participant-2");
  assert.equal(canonical.uid, "participant-1");
  assert.equal(canonical.requiresSignIn, true);
});
test("merge blocks conflicting records, stale plan, missing reason and privileged profiles", async () => {
  const data = {
    sourceUid: "participant-2",
    targetUid: "participant-1",
    reason: "Duplicate review",
  };
  await error(
    () => call("mergeProfiles", { ...data, reason: "" }, "admin-1"),
    "invalid-input",
    "INVALID_ARGUMENT",
  );
  await error(
    () => call("mergeProfiles", { ...data, sourceUid: "coach-1" }, "admin-1"),
    "privileged-profile",
    "FAILED_PRECONDITION",
  );
  const plan = await call("mergeProfiles", data, "admin-1");
  assert.ok(plan.conflicts.length >= 2);
  await error(
    () =>
      call(
        "mergeProfiles",
        { ...data, dryRun: false, dryRunId: plan.auditId },
        "admin-1",
      ),
    "merge-conflicts",
    "FAILED_PRECONDITION",
  );
  const clean = {
    sourceUid: "participant-3",
    targetUid: "participant-1",
    reason: "Duplicate review",
  };
  const old = await call("mergeProfiles", clean, "admin-1");
  await db
    .doc("users/participant-3")
    .update({ firstName: "Changed since review" });
  await error(
    () =>
      call(
        "mergeProfiles",
        { ...clean, dryRun: false, dryRunId: old.auditId },
        "admin-1",
      ),
    "stale-dry-run",
    "FAILED_PRECONDITION",
  );
});
test("scheduled wrapper queues confirmed attendees at +40 minutes once and uses local push double", async () => {
  const end = Timestamp.fromMillis(Date.now() - 2400001);
  await db.doc("events/event-3").update({ endsAt: end });
  await db.doc("checkins/event-3_participant-1").set({
    eventId: "event-3",
    uid: "participant-1",
    status: "confirmed",
    eventEndsAt: end,
    feedbackReminderPending: true,
  });
  // CLI 15.36 cannot dispatch v2 scheduler HTTP signatures through its Pub/Sub adapter.
  // Exercise the actual exported SDK handler against live emulator data instead.
  const { sendFeedbackReminders } = require("../lib/index");
  assert.equal(
    sendFeedbackReminders.__endpoint.scheduleTrigger.schedule,
    "every 5 minutes",
  );
  const previous = process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR = "true";
  try {
    await sendFeedbackReminders.run({ scheduleTime: new Date().toISOString() });
    await sendFeedbackReminders.run({ scheduleTime: new Date().toISOString() });
  } finally {
    if (previous === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = previous;
  }
  const notes = await db
    .collection("notifications")
    .where("type", "==", "feedback")
    .get();
  assert.equal(notes.size, 1);
  assert.equal(notes.docs[0].id, "feedback_event-3_participant-1");
  assert.equal(notes.docs[0].data().deliveryStatus, "sent");
  assert.equal(
    (await db.doc("emulatorPushes/feedback_event-3_participant-1").get())
      .exists,
    true,
  );
});
test("feedback timing, attendance eligibility, concurrent jobs and send retry use controlled clock", async () => {
  let now = Date.now(),
    s = new AttendanceService({ db, auth, now: () => now }),
    sends = 0,
    failOnce = true;
  const jobs = new NotificationService(s, async () => {
    sends++;
    if (failOnce) {
      failOnce = false;
      throw Error("temporary failure");
    }
  });
  const end = now - 2400000;
  await db.doc("events/event-3").update({ endsAt: Timestamp.fromMillis(end) });
  for (const [n, status, delta] of [
    [1, "confirmed", 1],
    [2, "confirmed", 0],
    [3, "pending", 0],
    [4, "rejected", 0],
  ]) {
    await db.doc(`checkins/event-3_participant-${n}`).set({
      eventId: "event-3",
      uid: `participant-${n}`,
      status,
      eventEndsAt: Timestamp.fromMillis(end + delta),
      feedbackReminderPending: true,
    });
  }
  // Participant 1 is one millisecond too early; pending/rejected attendees are never selected.
  const first = await jobs.feedbackReminders();
  assert.equal(first.queued, 1);
  assert.equal(
    (await db.doc("notifications/feedback_event-3_participant-2").get()).data()
      .deliveryStatus,
    "failed",
  );
  now++;
  await Promise.all([jobs.feedbackReminders(), jobs.feedbackReminders()]);
  assert.equal(
    (await db.collection("notifications").where("type", "==", "feedback").get())
      .size,
    2,
  );
  assert.equal(
    (await db.doc("notifications/feedback_event-3_participant-2").get()).data()
      .deliveryStatus,
    "sent",
  );
  const count = sends;
  await jobs.feedbackReminders();
  assert.equal(sends, count);
});

test("merge preserves original scan in moved record and audit, and expires old dry-runs", async () => {
  const merge = new MergeService(
    new AttendanceService({ db, auth, now: () => Date.now() + 1000000 }),
  );
  const admin = identity("admin-1", "admin");
  const oldPlan = await call(
    "mergeProfiles",
    {
      sourceUid: "participant-3",
      targetUid: "participant-1",
      reason: "Expiry check",
    },
    "admin-1",
  );
  await nativeError(
    () =>
      merge.mergeProfiles(admin, {
        sourceUid: "participant-3",
        targetUid: "participant-1",
        reason: "Expiry check",
        dryRun: false,
        dryRunId: oldPlan.auditId,
      }),
    "dry-run-expired",
  );
  const original = {
    eventId: "event-2",
    uid: "participant-3",
    scannedAt: stamp(),
    method: "manual",
    lat: null,
    lng: null,
    distanceM: null,
    status: "confirmed",
    confirmedBy: "coach-2",
    confirmedAt: stamp(),
    walkIn: true,
    corrections: [],
    eventEndsAt: stamp(),
    feedbackReminderPending: true,
  };
  await db.doc("checkins/event-2_participant-3").set(original);
  const data = {
    sourceUid: "participant-3",
    targetUid: "participant-1",
    reason: "Verified duplicate with attendance",
  };
  const plan = await call("mergeProfiles", data, "admin-1");
  await call(
    "mergeProfiles",
    { ...data, dryRun: false, dryRunId: plan.auditId },
    "admin-1",
  );
  const scan = (await db.doc("checkins/event-2_participant-1").get()).data();
  assert.deepEqual(scan.scannedAt, original.scannedAt);
  assert.equal(scan.lat, null);
  assert.equal(scan.mergedFromUid, "participant-3");
  const audit = (await db.doc(`mergeAudits/${plan.auditId}`).get()).data();
  const archived = audit.originals.find(
    (r) => r.path === "checkins/event-2_participant-3",
  ).data;
  assert.deepEqual(archived, original);
});
test("feedback delivery stops after five failures and never sends to a rejected attendee", async () => {
  let attempts = 0;
  const jobs = new NotificationService(service, async () => {
    attempts++;
    throw Error("failure");
  });
  const note = "feedback_event-1_participant-1";
  await db
    .doc("checkins/event-1_participant-1")
    .set({ uid: "participant-1", eventId: "event-1", status: "confirmed" });
  await db.doc(`notifications/${note}`).set({
    uid: "participant-1",
    eventId: "event-1",
    type: "feedback",
    deliveryStatus: "pending",
    attempts: 0,
  });
  for (let i = 0; i < 7; i++) await jobs.deliver(note);
  assert.equal(attempts, 5);
  assert.equal(
    (await db.doc(`notifications/${note}`).get()).data().deliveryStatus,
    "dead",
  );
  await db.doc("checkins/event-1_participant-1").update({ status: "rejected" });
  await db
    .doc(`notifications/${note}`)
    .update({ deliveryStatus: "pending", attempts: 0 });
  await jobs.deliver(note);
  assert.equal(attempts, 5);
  assert.equal(
    (await db.doc(`notifications/${note}`).get()).data().deliveryStatus,
    "suppressed",
  );
});
test("merge CLI defaults to dry-run without changing profiles", async () => {
  const { execFile } = require("node:child_process");
  const { promisify } = require("node:util");
  const result = await promisify(execFile)(
    process.execPath,
    [
      "scripts/merge-profiles.mjs",
      "--source",
      "participant-3",
      "--target",
      "participant-1",
      "--reason",
      "CLI dry-run review",
    ],
    { cwd: require("node:path").resolve(__dirname, "../..") },
  );
  const plan = JSON.parse(result.stdout);
  assert.equal(plan.dryRun, true);
  assert.equal(
    (await db.doc("users/participant-3").get()).data().mergedInto,
    null,
  );
});

test("protected role demotion overrides claims; claim-only coaches still receive scan alerts", async () => {
  const { FieldValue } = require("firebase-admin/firestore");
  await db.doc("users/coach-1").update({ role: "participant" });
  await error(() => rotate(), "event-role-required", "PERMISSION_DENIED");
  await db.doc("users/coach-1").update({ role: FieldValue.delete() });
  await scan();
  await eventually(async () =>
    assert.equal(
      (
        await db
          .doc("notifications/checkin-participant-1_event-1_coach-1")
          .get()
      ).data()?.deliveryStatus,
      "sent",
    ),
  );
});

test("callable rate limits are enforced on checkIn and registerIdentity", async () => {
  const qr = await rotate();
  for (let n = 0; n < 10; n++)
    await error(
      () =>
        call("checkIn", {
          eventCode: qr.eventCode,
          secret: "wrong",
          lat: -33.8926,
          lng: 151.2511,
        }),
      "invalid-secret",
      "PERMISSION_DENIED",
    );
  await error(
    () =>
      call("checkIn", {
        eventCode: qr.eventCode,
        secret: "wrong",
        lat: -33.8926,
        lng: 151.2511,
      }),
    "rate-limit",
    "RESOURCE_EXHAUSTED",
  );
  for (let n = 0; n < 20; n++) await call("registerIdentity", {});
  await error(
    () => call("registerIdentity", {}),
    "rate-limit",
    "RESOURCE_EXHAUSTED",
  );
});
async function noAppData(email = "member1@example.test") {
  const qr = await rotate();
  return {
    email,
    eventCode: qr.eventCode,
    secret: qr.secret,
    lat: -33.8926,
    lng: 151.2511,
    firstName: "Court visitor",
    mobile: "0400000000",
    emergencyContact: { name: "Emergency Contact", mobile: "0400000001" },
    signedVersions: { conduct: 1, waiver: 1 },
  };
}
test("returning no-app attendee needs a one-time Firebase email link before attendance", async () => {
  await db
    .doc("checkins/event-3_participant-1")
    .set({ uid: "participant-1", eventId: "event-3", status: "confirmed" });
  const data = await noAppData();
  const result = await call("beginNoAppCheckIn", data, null);
  assert.equal(result.status, "verification-required");
  assert.equal(
    (await db.doc("checkins/event-1_participant-1").get()).exists,
    false,
  );
  await error(
    () =>
      call(
        "completeNoAppCheckIn",
        { requestId: result.requestId, oobCode: "wrong", secret: data.secret },
        null,
      ),
    "verification-invalid",
    "PERMISSION_DENIED",
  );
  const codes = await (
    await fetch(
      "http://127.0.0.1:9099/emulator/v1/projects/demo-rally4ever/oobCodes",
    )
  ).json();
  const code = codes.oobCodes
    .filter(
      (c) =>
        c.email === "member1@example.test" && c.requestType === "EMAIL_SIGNIN",
    )
    .at(-1);
  assert.ok(code);
  const complete = {
    requestId: result.requestId,
    oobCode: code.oobCode,
    secret: data.secret,
  };
  const accepted = await call("completeNoAppCheckIn", complete, null);
  assert.equal(accepted.status, "pending");
  assert.equal(accepted.verification, "email-link");
  assert.equal(accepted.idToken, undefined);
  await error(
    () => call("completeNoAppCheckIn", complete, null),
    "verification-expired",
    "FAILED_PRECONDITION",
  );
});
test("new no-app email creates only a provisional pending walk-in, never a verified login", async () => {
  const data = await noAppData(`visitor-${Date.now()}@example.test`);
  const result = await call("beginNoAppCheckIn", data, null);
  assert.equal(result.status, "pending");
  assert.equal(result.verification, "email-only");
  assert.equal(result.idToken, undefined);
  await assert.rejects(()=>auth.getUserByEmail(data.email),e=>e.code==='auth/user-not-found');
  const mapping=(await db.doc(`guestEmailIdentities/${data.email}`).get()).data();
  assert.equal((await db.doc(`users/${mapping.uid}`).get()).exists,false);
  const scan = (await db.doc(`checkins/event-1_${mapping.uid}`).get()).data();
  assert.equal(scan.status, "pending");
  assert.equal(scan.walkIn, true);
  assert.equal(scan.identityVerification, "email-only");
  assert.equal(scan.confirmedBy, null);
});
test("no-app form requirements cannot be bypassed and private requests cannot use other secrets", async () => {
  const data = await noAppData(`unsigned-${Date.now()}@example.test`);
  data.signedVersions = { conduct: 1 };
  await error(
    () => call("beginNoAppCheckIn", data, null),
    "unsigned-forms",
    "FAILED_PRECONDITION",
  );
  await assert.rejects(()=>auth.getUserByEmail(data.email),e=>e.code==='auth/user-not-found');
  assert.equal((await db.collection('guests').where('emailLower','==',data.email).get()).empty,true);
  await db
    .doc("checkins/event-3_participant-1")
    .set({ uid: "participant-1", eventId: "event-3", status: "confirmed" });
  const valid = await noAppData();
  const request = await call("beginNoAppCheckIn", valid, null);
  await error(
    () =>
      call(
        "completeNoAppCheckIn",
        {
          requestId: request.requestId,
          oobCode: "anything",
          secret: "different",
        },
        null,
      ),
    "invalid-secret",
    "PERMISSION_DENIED",
  );
});
test("counted-in projection exposes only opted-in names and the viewer, never contact details", async () => {
  await db.doc("rsvps/event-1_participant-2").set({
    uid: "participant-2",
    eventId: "event-1",
    createdAt: stamp(),
    cancelledAt: null,
    source: "app",
  });
  const result = await call("getCountedIn", { eventId: "event-1" });
  assert.equal(result.count, 2);
  assert.equal(result.people.length, 1);
  assert.equal(result.people[0].isYou, true);
  await db
    .doc("users/participant-2")
    .update({ "preferences.showInWhosGoing": true });
  const visible = await call("getCountedIn", { eventId: "event-1" });
  assert.equal(visible.people.length, 2);
  for (const p of visible.people)
    assert.deepEqual(Object.keys(p).sort(), ["initials", "isYou", "label"]);
});

async function googleLogin(email, sub) {
  const payload = {
    sub,
    email,
    email_verified: true,
    name: "Workspace Member",
  };
  const fakeToken =
    Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString(
      "base64url",
    ) +
    "." +
    Buffer.from(JSON.stringify(payload)).toString("base64url") +
    ".";
  const result = await fetch(
    "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=demo-api-key",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        requestUri: "http://localhost",
        postBody: `id_token=${encodeURIComponent(fakeToken)}&providerId=google.com`,
        returnSecureToken: true,
        returnIdpCredential: true,
      }),
    },
  );
  const body = await result.json();
  assert.ok(result.ok, JSON.stringify(body));
  tokens.set(body.localId, body.idToken);
  return body;
}
test("Google Workspace sign-in without claim is participant; only admin can grant/assign/revoke coach", async () => {
  const google = await googleLogin(
    `workspace-${Date.now()}@rally4ever.org`,
    "workspace-new",
  );
  await call("registerIdentity", {}, google.localId);
  assert.equal(
    (await db.doc(`users/${google.localId}`).get()).data().role,
    "participant",
  );
  await error(
    () => call("coachOverview", {}, google.localId),
    "coach-claim-required",
    "PERMISSION_DENIED",
  );
  await error(
    () =>
      call(
        "setUserRole",
        {
          uid: google.localId,
          role: "coach",
          enabled: true,
          reason: "Self grant",
        },
        google.localId,
      ),
    "admin-required",
    "PERMISSION_DENIED",
  );
  const grant = await call(
    "setUserRole",
    {
      uid: google.localId,
      role: "coach",
      enabled: true,
      reason: "Approved coach",
    },
    "admin-1",
  );
  assert.ok(grant.roles.includes("participant"));
  assert.ok(grant.roles.includes("coach"));
  const refreshed = await googleLogin(
    google.email ?? (await auth.getUser(google.localId)).email,
    "workspace-new",
  );
  assert.equal(refreshed.localId, google.localId);
  await call(
    "assignEventCoaches",
    {
      eventId: "event-1",
      coachUids: [google.localId],
      reason: "Session assignment",
    },
    "admin-1",
  );
  await rotate("event-1", google.localId);
  const overview = await call("coachOverview", {}, google.localId);
  assert.equal(overview.events.length, 1);
  const listing = await call(
    "listUsers",
    { query: (await auth.getUser(google.localId)).email },
    "admin-1",
  );
  assert.equal(listing.users[0].uid, google.localId);
  await call(
    "setUserRole",
    {
      uid: google.localId,
      role: "coach",
      enabled: false,
      reason: "Coach access revoked",
    },
    "admin-1",
  );
  // Cached Google token still has the old claim, but the protected server gate denies immediately.
  await error(
    () => rotate("event-1", google.localId),
    "event-role-required",
    "PERMISSION_DENIED",
  );
  await error(
    () => call("coachOverview", {}, google.localId),
    "coach-claim-required",
    "PERMISSION_DENIED",
  );
  assert.equal(
    (
      await db
        .collection("users")
        .where("emailLower", "==", (await auth.getUser(google.localId)).email)
        .get()
    ).size,
    1,
  );
});
test("Google and pre-created email account resolve to the same existing Auth UID/profile", async () => {
  const user = await googleLogin("dan@rally4ever.org", "workspace-dan");
  assert.equal(user.localId, "coach-1");
  const identity = await call("registerIdentity", {}, user.localId);
  assert.equal(identity.uid, "coach-1");
  assert.equal(identity.created, false);
  assert.equal(
    (
      await db
        .collection("users")
        .where("emailLower", "==", "dan@rally4ever.org")
        .get()
    ).size,
    1,
  );
});
test('deferred guest flow uses both functions, normalizes email, never creates Auth/profile, rejects duplicate',async()=>{
 const data=await noAppData('DEFERRED-GUEST@example.test');const before=(await auth.listUsers()).users.length;
 const start=await call('beginNoAppCheckIn',{...data,deferCompletion:true},null);assert.equal(start.status,'ready');
 assert.equal((await db.collection('guests').get()).size,0);
 const result=await call('completeNoAppCheckIn',{requestId:start.requestId,secret:data.secret},null);assert.equal(result.status,'pending');
 assert.equal((await auth.listUsers()).users.length,before);
 const key=(await db.doc('guestEmailIdentities/deferred-guest@example.test').get()).data();assert.ok(key.uid.startsWith('guest-'));assert.equal((await db.doc('users/'+key.uid).get()).exists,false);
 await error(()=>call('beginNoAppCheckIn',{...data,email:data.email.toLowerCase()},null),'already-checked-in','ALREADY_EXISTS');
 const roster=await call('getEventConsole',{eventId:'event-1'},'coach-1');assert.ok(roster.roster.some(r=>r.uid===key.uid&&r.firstName==='Court visitor'));
 await call('coachDecision',{eventId:'event-1',uid:key.uid,decision:'confirm'},'coach-1');assert.equal((await db.doc(result.checkinId?`checkins/${result.checkinId}`:'bad/bad').get()).data().status,'confirmed');
});
test('public session info identifies a session before location, but never exposes secret hashes/private fields',async()=>{
 const data=await noAppData('info@example.test');const info=await call('getNoAppForms',{eventCode:data.eventCode,secret:data.secret},null);assert.equal(info.name,(await db.doc('events/event-1').get()).data().name);assert.equal(info.forms.length,2);assert.equal(info.currentSecretHash,undefined);assert.equal(info.coachUids,undefined);
 await error(()=>call('getNoAppForms',{eventCode:data.eventCode,secret:'arbitrary-barcode'},null),'invalid-secret','PERMISSION_DENIED');
});
test('public check-in enforces time, distance, email and request binding server-side',async()=>{
 const data=await noAppData('validation@example.test');
 await error(()=>call('beginNoAppCheckIn',{...data,email:'not-an-email'},null),'invalid-email','INVALID_ARGUMENT');
 await error(()=>call('beginNoAppCheckIn',{...data,lat:0,lng:0},null),'too-far','FAILED_PRECONDITION');
 const old=(await db.doc('events/event-1').get()).data();
 await db.doc('events/event-1').update({startsAt:Timestamp.fromMillis(Date.now()+7200000),endsAt:Timestamp.fromMillis(Date.now()+10800000)});
 await error(()=>call('beginNoAppCheckIn',data,null),'too-early','FAILED_PRECONDITION');
 await db.doc('events/event-1').update({startsAt:Timestamp.fromMillis(Date.now()-7200000),endsAt:Timestamp.fromMillis(Date.now()-1000)});
 await error(()=>call('beginNoAppCheckIn',data,null),'too-late','FAILED_PRECONDITION');
 await db.doc('events/event-1').update({startsAt:old.startsAt,endsAt:old.endsAt});
 const request=await call('beginNoAppCheckIn',{...data,deferCompletion:true},null);
 await error(()=>call('completeNoAppCheckIn',{requestId:request.requestId,secret:'wrong'},null),'invalid-secret','PERMISSION_DENIED');
});
test('verified signup claims guest history without deleting scans or overwriting conflicts',async()=>{
 const data=await noAppData('guest-claim@example.test');const scan=await call('beginNoAppCheckIn',data,null);const old=(await db.doc(`checkins/${scan.checkinId}`).get()).data();
 const member=await auth.createUser({uid:'claim-member',email:data.email,emailVerified:true,password:'Emulator-Claim-Password-123!'});
 const result=await service.registerIdentity({uid:member.uid,email:data.email},{});assert.equal(result.uid,member.uid);assert.equal(result.guestHistory.copied,1);
 const moved=(await db.doc(`checkins/event-1_${member.uid}`).get()).data();assert.equal(moved.scannedAt.toMillis(),old.scannedAt.toMillis());assert.equal(moved.identityVerification,'email-only');assert.equal((await db.doc(`checkins/${scan.checkinId}`).get()).data().mergedInto,`checkins/event-1_${member.uid}`);
 const roster=await call('getEventConsole',{eventId:'event-1'},'coach-1');assert.equal(roster.roster.filter(r=>[old.uid,member.uid].includes(r.uid)).length,1);
});
test('guest claim collisions are recorded for review and both original scans remain unchanged',async()=>{
 const data=await noAppData('guest-conflict@example.test');const result=await call('beginNoAppCheckIn',data,null);const old=(await db.doc(`checkins/${result.checkinId}`).get()).data();
 const member=await auth.createUser({uid:'claim-conflict-member',email:data.email,emailVerified:true});const dest=db.doc(`checkins/event-1_${member.uid}`);await dest.set({uid:member.uid,eventId:'event-1',status:'confirmed',scannedAt:Timestamp.fromMillis(1234)});
 const registered=await service.registerIdentity({uid:member.uid,email:data.email},{});assert.equal(registered.guestHistory.conflicts.length,1);assert.equal((await dest.get()).data().scannedAt.toMillis(),1234);assert.equal((await db.doc(`checkins/${result.checkinId}`).get()).data().scannedAt.toMillis(),old.scannedAt.toMillis());
});
test('known emails require ownership proof even without attendance, and public endpoints rate limit',async()=>{
 const data=await noAppData();const response=await call('beginNoAppCheckIn',data,null);assert.equal(response.status,'verification-required');
 const info={eventCode:data.eventCode,secret:data.secret};for(let i=0;i<30;i++)await call('getNoAppForms',info,null);
 await error(()=>call('getNoAppForms',info,null),'rate-limit','RESOURCE_EXHAUSTED');
});
test('merge target must match its verified Auth email and never silently changes ownership',async()=>{
 const value={sourceUid:'participant-2',targetUid:'participant-1',reason:'Reviewed duplicate test',dryRun:true};
 await error(()=>call('mergeProfiles',{...value,email:'wrong@example.test'},'admin-1'),'email-mismatch','PERMISSION_DENIED');
 await auth.updateUser('participant-1',{emailVerified:false});await error(()=>call('mergeProfiles',value,'admin-1'),'unverified-target','FAILED_PRECONDITION');
 assert.equal((await db.doc('users/participant-2').get()).data().mergedInto,null);
});

test('required legal forms block when absent, draft, future, blank; date versions accepted',async()=>{
 const ref=db.doc('forms/waiver');const original=(await ref.get()).data();
 await db.doc('events/event-1').update({requiredFormIds:[]});
 await ref.delete();await error(()=>scan(),'form-unavailable','FAILED_PRECONDITION');
 for(const change of [{published:false},{status:'draft'},{publishedAt:Timestamp.fromMillis(Date.now()+60000)},{body:' ',content:''}]){
  await ref.set({...original,...change});await error(()=>scan(),'form-unavailable','FAILED_PRECONDITION');
 }
 await ref.set({...original,body:'Emulator approved fixture',version:'2026-11-20',publishedAt:Timestamp.fromMillis(0)});
 await error(()=>scan(),'unsigned-forms','FAILED_PRECONDITION');
 await db.doc('consents/participant-1_waiver').update({version:'2026-11-20'});
 const result=await scan();assert.equal(result.status,'pending');
});
