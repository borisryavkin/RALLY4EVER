const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeEmail,
  authIdentity,
  checkWindow,
  coordinate,
  checkDistance,
  distanceM,
  hash,
  secretMatches,
  input,
} = require("../lib/domain");
const rejects = (fn, reason, code) =>
  assert.throws(fn, (e) => e.code === code && e.details.reason === reason);

test("normalized email is safe as exact identity document key", () => {
  assert.equal(
    normalizeEmail("  MeMber@EXAMPLE.TEST  "),
    "member@example.test",
  );
  for (const v of [
    "a/b@example.test",
    "not-an-email",
    "a@b",
    "a b@example.test",
    "",
    null,
  ])
    rejects(
      () => normalizeEmail(v),
      v === null || v === "" ? "invalid-input" : "invalid-email",
      "invalid-argument",
    );
});
test("only verified authenticated email contexts are accepted", () => {
  rejects(() => authIdentity(undefined), "sign-in-required", "unauthenticated");
  rejects(
    () =>
      authIdentity({
        uid: "p1",
        token: { email: "p@example.test", email_verified: false },
      }),
    "email-unverified",
    "permission-denied",
  );
  assert.equal(
    authIdentity({
      uid: "p1",
      token: { email: "P@example.test", email_verified: true },
    }).email,
    "p@example.test",
  );
});
test("window includes opening and closing boundaries, rejects too early/late", () => {
  const start = Date.UTC(2026, 10, 17, 7, 30),
    end = start + 3600000;
  rejects(
    () => checkWindow(start - 600001, start, end, "Australia/Sydney"),
    "too-early",
    "failed-precondition",
  );
  checkWindow(start - 600000, start, end, "Australia/Sydney");
  checkWindow(end, start, end, "Australia/Sydney");
  rejects(
    () => checkWindow(end + 1, start, end, "Australia/Sydney"),
    "too-late",
    "failed-precondition",
  );
});
test("geofence zero/boundary distance, too far and invalid coordinates", () => {
  assert.equal(distanceM(-33.89, 151.25, -33.89, 151.25), 0);
  const latDelta = ((150 / 6371000) * 180) / Math.PI;
  assert.ok(Math.abs(distanceM(0, 0, latDelta, 0) - 150) < 0.00001);
  checkDistance(0, 0, latDelta, 0, 150.00001);
  rejects(
    () => checkDistance(0, 0, latDelta * 2, 0, 150),
    "too-far",
    "failed-precondition",
  );
  for (const x of [NaN, Infinity, 91, "0"])
    rejects(() => coordinate(x, "lat"), "invalid-location", "invalid-argument");
});
test("secret comparison validates hashes, and rejects old/wrong secret", () => {
  assert.equal(secretMatches("correct", hash("correct")), true);
  assert.equal(secretMatches("wrong", hash("correct")), false);
  assert.equal(secretMatches("correct", "invalid"), false);
});
test("callable input rejects unknown fields to prevent role/status injection", () => {
  rejects(
    () => input({ role: "admin" }, ["email"]),
    "unknown-field",
    "invalid-argument",
  );
  rejects(() => input([], []), "invalid-input", "invalid-argument");
});

test("all seven callables reject malformed/forged inputs before touching persistence", async () => {
  const { AttendanceService } = require("../lib/service");
  const { MergeService } = require("../lib/merge");
  const blocked = new Proxy(
    {},
    {
      get() {
        throw new Error("Unexpected persistence access");
      },
    },
  );
  const s = new AttendanceService({ db: blocked, auth: blocked });
  const who = { uid: "participant-1", email: "one@example.test" };
  for (const promise of [
    s.registerIdentity(who, { email: "other@example.test" }),
    s.rotateEventSecret(who, { eventId: "../../secret" }),
    s.checkIn(who, {
      eventCode: "arbitrary barcode",
      secret: "x",
      lat: 0,
      lng: 0,
    }),
    s.coachDecision(who, {
      eventId: "event-1",
      uid: "participant-1",
      decision: "promote",
    }),
    s.correctAttendance(who, {
      eventId: "event-1",
      uid: "participant-1",
      status: "confirmed",
      reason: " ",
    }),
    s.addWalkIn(who, { eventId: "event-1", email: "invalid" }),
    new MergeService(s).mergeProfiles(who, {
      sourceUid: "one",
      targetUid: "two",
      reason: "review",
      dryRun: "false",
    }),
  ])
    await assert.rejects(promise, (e) =>
      ["invalid-argument", "permission-denied"].includes(e.code),
    );
});
test("notification delivery is idempotent for sent records and missing trigger scans are harmless", async () => {
  const { AttendanceService } = require("../lib/service");
  const { NotificationService } = require("../lib/notifications");
  const db = {
    doc: () => ({ get: async () => ({ exists: false }) }),
    runTransaction: (fn) =>
      fn({ get: async () => ({ data: () => ({ deliveryStatus: "sent" }) }) }),
  };
  const n = new NotificationService(
    new AttendanceService({ db, auth: {} }),
    async () => assert.fail("Already sent"),
  );
  assert.equal(await n.deliver("already-sent"), false);
  assert.equal(await n.notifyCoaches("missing"), 0);
});
function withEnv(overrides, fn) {
  const keys = Object.keys(overrides);
  const previous = Object.fromEntries(keys.map((k) => [k, process.env[k]]));
  try {
    for (const k of keys) {
      if (overrides[k] === undefined) delete process.env[k];
      else process.env[k] = overrides[k];
    }
    return fn();
  } finally {
    for (const k of keys) {
      if (previous[k] === undefined) delete process.env[k];
      else process.env[k] = previous[k];
    }
  }
}

test("the no-app walk-in gate fails closed outside the demo emulators", () => {
  const { assertEmulatorOnly } = require("../lib/index");
  withEnv({ FUNCTIONS_EMULATOR: undefined }, () =>
    rejects(assertEmulatorOnly, "emulator-only", "failed-precondition"),
  );
});

test(
  "the general backend gate fails closed with no emulator and no approved project, " +
    "but passes for the one real project these functions are approved to run against",
  () => {
    const { assertApprovedBackend } = require("../lib/index");
    withEnv(
      {
        FUNCTIONS_EMULATOR: undefined,
        GCLOUD_PROJECT: undefined,
        GOOGLE_CLOUD_PROJECT: undefined,
      },
      () =>
        rejects(assertApprovedBackend, "unapproved-backend", "failed-precondition"),
    );
    withEnv(
      {
        FUNCTIONS_EMULATOR: undefined,
        GCLOUD_PROJECT: undefined,
        GOOGLE_CLOUD_PROJECT: "some-other-project",
      },
      () =>
        rejects(assertApprovedBackend, "unapproved-backend", "failed-precondition"),
    );
    // Regression test for the incident this app hit: a deployed function
    // must actually work against its own real, approved project, not just
    // fail closed forever.
    withEnv(
      {
        FUNCTIONS_EMULATOR: undefined,
        GCLOUD_PROJECT: undefined,
        GOOGLE_CLOUD_PROJECT: "rally4ever-3adaf",
      },
      assertApprovedBackend,
    );
  },
);

test("transient Auth lookup failures retry the coach trigger instead of silently dropping alerts", async () => {
  const { AttendanceService } = require("../lib/service");
  const { NotificationService } = require("../lib/notifications");
  const snapshots = {
    "checkins/e_p": { status: "pending", eventId: "e", uid: "p" },
    "events/e": { coachUids: ["coach"] },
    "users/coach": { mergedInto: null },
  };
  const db = {
    doc: (path) => ({
      get: async () => ({ exists: true, data: () => snapshots[path] }),
    }),
  };
  const auth = {
    getUser: async () => {
      throw new Error("Temporary Auth outage");
    },
  };
  const jobs = new NotificationService(
    new AttendanceService({ db, auth }),
    async () => assert.fail("No premature send"),
  );
  await assert.rejects(jobs.notifyCoaches("e_p"), /Temporary Auth outage/);
});

test("Workspace email never creates a coach role; coach access needs a claim and protected gate", async () => {
  const { AttendanceService } = require("../lib/service");
  const who = authIdentity({
    uid: "work",
    token: {
      email: "member@rally4ever.org",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" },
    },
  });
  assert.equal(who.role, undefined);
  const db = { doc: () => ({}) };
  let profile = { role: "coach", mergedInto: null, coachEnabled: true };
  const service = new AttendanceService({ db, auth: {} }),
    tx = { get: async () => ({ data: () => profile }) };
  assert.equal((await service.actor(tx, who)).role, "participant");
  assert.equal(
    (await service.actor(tx, { ...who, role: "coach" })).role,
    "coach",
  );
  profile = { ...profile, coachEnabled: false };
  assert.equal(
    (await service.actor(tx, { ...who, role: "coach" })).role,
    "participant",
  );
});

test("network guard permits LAN only with explicit private host and demo emulator identity", () => {
  const { assertEmulatorNetwork } = require("../lib/emulator_network");
  const local = {
    FUNCTIONS_EMULATOR: "true",
    GCLOUD_PROJECT: "demo-rally4ever",
    DEMO_PROJECT_ID: "demo-rally4ever",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
    FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
  };
  assertEmulatorNetwork(local);
  const lan = {
    ...local,
    LAN_TESTING: "true",
    LAN_HOST: "192.168.1.50",
    FIRESTORE_EMULATOR_HOST: "0.0.0.0:8080",
    FIREBASE_AUTH_EMULATOR_HOST: "0.0.0.0:9099",
  };
  assertEmulatorNetwork(lan);
  for (const ip of ["10.0.0.20", "172.16.1.20", "172.31.1.20", "192.168.1.20"])
    assertEmulatorNetwork({ ...lan, LAN_HOST: ip });
  for (const env of [
    { ...lan, LAN_TESTING: "false" },
    { ...lan, LAN_HOST: "8.8.8.8" },
    { ...lan, LAN_HOST: "" },
    { ...lan, FUNCTIONS_EMULATOR: "false" },
    { ...lan, GCLOUD_PROJECT: "production" },
    { ...lan, FIREBASE_PROJECT_ID: "production" },
    { ...lan, FIREBASE_CONFIG: '{"projectId":"production"}' },
    { ...lan, NODE_ENV: "production" },
    { ...local, FIRESTORE_EMULATOR_HOST: "0.0.0.0:8080" },
    { ...lan, FIREBASE_AUTH_EMULATOR_HOST: "8.8.8.8:9099" },
    // No DEMO_PROJECT_ID at all: this is the shape of a real deployed
    // function's environment, which must never pass as "the emulator".
    { ...local, DEMO_PROJECT_ID: undefined },
    { ...local, DEMO_PROJECT_ID: "" },
  ])
    assert.throws(() => assertEmulatorNetwork(env));
});

test("production entry point and its guards never hardcode the demo project id", async () => {
  // Regression test for a real incident: functions/src/index.ts hardcoded
  // initializeApp({ projectId: "demo-rally4ever" }), so deployed functions on
  // rally4ever-3adaf verified real Firebase ID tokens against the wrong
  // "aud" and rejected every real caller. The demo project id must only ever
  // come from an environment variable that emulator/test setups set, never
  // from a literal in functions/src.
  const { readdir, readFile } = require("node:fs/promises");
  const path = require("node:path");
  const srcDir = path.join(__dirname, "..", "src");
  const offenders = [];
  for (const name of await readdir(srcDir)) {
    if (!name.endsWith(".ts")) continue;
    const content = await readFile(path.join(srcDir, name), "utf8");
    if (content.includes("demo-rally4ever")) offenders.push(name);
  }
  assert.deepEqual(offenders, []);
});
