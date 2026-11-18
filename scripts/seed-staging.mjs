import { pathToFileURL } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

// The only project this script is ever allowed to touch. Hardcoded, not read
// from an env var, so a stray GCLOUD_PROJECT/GOOGLE_CLOUD_PROJECT cannot redirect it.
export const projectId = 'rally4ever-3adaf';
export const seedSource = 'scripts/seed-staging.mjs';
const day = 86400000;

// Never allow this to run against the emulator suite or any other project.
export function requireRealStagingProject() {
  for (const name of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    if (process.env[name]) {
      throw new Error(`Refusing to seed real staging data: ${name} is set (this targets the emulator)`);
    }
  }
  for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
    if (process.env[name] && process.env[name] !== projectId) {
      throw new Error(`Refusing to seed: ${name}=${process.env[name]} must be ${projectId} or unset`);
    }
  }
  return projectId;
}

function hash(value) {
  return createHash('sha256').update(value).digest('hex');
}

const seedAllowedEmails = () =>
  new Set(
    (process.env.SEED_ALLOW_EMAILS ?? '')
      .split(',')
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  );

// Fails closed: any users/events document that this script did not create and
// that isn't on the operator's explicit allowlist blocks the run before any write.
async function assertSafeToSeed(db) {
  const allowedEmails = seedAllowedEmails();
  const users = await db.collection('users').get();
  const foreignUsers = users.docs.filter((doc) => {
    const data = doc.data();
    if (data.seedSource === seedSource) return false;
    return !allowedEmails.has((data.emailLower ?? '').toLowerCase());
  });
  if (foreignUsers.length > 0) {
    throw new Error(
      'Refusing to seed: found participant data this script did not create: ' +
        foreignUsers.map((doc) => doc.id).join(', ') +
        '. If these are your own test accounts, re-run with SEED_ALLOW_EMAILS set to their comma-separated emails.',
    );
  }
  const events = await db.collection('events').get();
  const foreignEvents = events.docs.filter((doc) => doc.data().seedSource !== seedSource);
  if (foreignEvents.length > 0) {
    throw new Error(
      'Refusing to seed: found existing event data this script did not create: ' +
        foreignEvents.map((doc) => doc.id).join(', ') +
        '. This script does not seed into a project that already has real program data.',
    );
  }
}

// Create-only: rerunning never overwrites a document or account another run already wrote.
async function create(db, path, data) {
  try {
    await db.doc(path).create(data);
    return true;
  } catch (error) {
    if (error.code === 6 || error.code === 'already-exists') return false;
    throw error;
  }
}

const venues = {
  waverley: { name: 'Waverley Park Courts', address: 'Bondi Junction NSW', lat: -33.8926, lng: 151.2511 },
  addison: { name: 'Addison Road Courts', address: 'Marrickville NSW', lat: -33.9057, lng: 151.1572 },
};

const coaches = [
  { uid: 'seed-coach-1', email: 'coach1@rally4ever-staging-seed.test', firstName: 'SeedCoach1' },
  { uid: 'seed-coach-2', email: 'coach2@rally4ever-staging-seed.test', firstName: 'SeedCoach2' },
];

const participants = [
  { uid: 'seed-participant-1', email: 'participant1@rally4ever-staging-seed.test', firstName: 'SeedParticipant1' },
  { uid: 'seed-participant-2', email: 'participant2@rally4ever-staging-seed.test', firstName: 'SeedParticipant2' },
  { uid: 'seed-participant-3', email: 'participant3@rally4ever-staging-seed.test', firstName: 'SeedParticipant3' },
];

const seedPassword = 'Staging-seed-only-Password-123!';

function profile({ uid, email, firstName }, role, now) {
  return {
    uid, email, emailLower: email, role, coachEnabled: role === 'coach', mergedInto: null,
    createdAt: now, updatedAt: now, firstName, lastName: '', postcode: '2022', mobile: '',
    emergencyContact: { name: '', mobile: '' }, injuries: '',
    preferences: { useInReports: false, wellbeingCheckIns: false, showInWhosGoing: false, marketingEmails: false },
    about: {}, seedSource,
  };
}

function event({ id, code, name, coachUid, venue, startsAt, endsAt }) {
  return {
    eventId: id, code, name, sport: 'tennis', status: 'published', startsAt, endsAt,
    timezone: 'Australia/Sydney', coachUids: [coachUid], venue, geofenceRadiusM: 150,
    requiredFormIds: ['conduct', 'waiver'], seedSource,
  };
}

// Mirrors functions/src/service.ts rotateEventSecret: a fresh, short-lived hashed
// secret. Only the hash is stored, matching production; the plaintext is returned
// so an operator can scan within the validity window, but real testing should
// trigger a normal in-app coach "start session" rotation instead of relying on this.
function secretFor(eventId, endsAtMillis, now) {
  const secret = randomBytes(32).toString('base64url');
  return {
    secret,
    doc: {
      currentSecretHash: hash(secret),
      rotatedAt: Timestamp.fromMillis(now.toMillis()),
      expiresAt: Timestamp.fromMillis(Math.min(now.toMillis() + 300000, endsAtMillis)),
      generation: 1,
      seedSource,
    },
  };
}

export async function seedStaging() {
  requireRealStagingProject();
  const app = initializeApp({ credential: applicationDefault(), projectId }, `seed-staging-${Date.now()}`);
  const auth = getAuth(app), db = getFirestore(app);
  try {
    await assertSafeToSeed(db);
    const now = Timestamp.now();
    const nowMs = now.toMillis();

    for (const account of [...coaches, ...participants]) {
      const role = coaches.includes(account) ? 'coach' : 'participant';
      try {
        await auth.createUser({ uid: account.uid, email: account.email, emailVerified: true, password: seedPassword });
      } catch (error) {
        if (error.code !== 'auth/uid-already-exists') throw error;
        const existing = await auth.getUser(account.uid);
        if (existing.email !== account.email) throw new Error(`Seed identity collision: ${account.uid}`);
      }
      await auth.setCustomUserClaims(account.uid, {
        role, roles: role === 'participant' ? ['participant'] : ['participant', role],
      });
      await create(db, `users/${account.uid}`, profile(account, role, now));
      await create(db, `emailIdentities/${account.email}`, {
        emailLower: account.email, uid: account.uid, createdAt: now, seedSource,
      });
    }

    for (const [formType, title] of [['conduct', 'Code of conduct'], ['waiver', 'Participation waiver']]) {
      await create(db, `forms/${formType}`, {
        formType, version: 1, title, content: `Staging placeholder ${title.toLowerCase()} text; not approved legal copy.`,
        updatedAt: now, seedSource,
      });
    }

    const secretsIssued = [];
    const upcoming = [
      { id: 'seed-event-upcoming-1', code: 'SEEDUP1', name: 'Tuesday rally', coachUid: coaches[0].uid, venue: venues.waverley, offsetDays: 1 },
      { id: 'seed-event-upcoming-2', code: 'SEEDUP2', name: 'Thursday rally', coachUid: coaches[1].uid, venue: venues.addison, offsetDays: 3 },
      { id: 'seed-event-upcoming-3', code: 'SEEDUP3', name: 'Saturday social', coachUid: coaches[0].uid, venue: venues.waverley, offsetDays: 7 },
    ];
    for (const spec of upcoming) {
      const startsAt = Timestamp.fromMillis(nowMs + spec.offsetDays * day);
      const endsAt = Timestamp.fromMillis(nowMs + spec.offsetDays * day + 3600000);
      const created = await create(db, `events/${spec.id}`, event({ ...spec, startsAt, endsAt }));
      const { secret, doc } = secretFor(spec.id, endsAt.toMillis(), now);
      const secretCreated = await create(db, `eventSecrets/${spec.id}`, doc);
      if (secretCreated) secretsIssued.push({ eventId: spec.id, secret, expiresAt: doc.expiresAt.toDate().toISOString() });
      void created;
    }

    const past = [
      { id: 'seed-event-past-1', code: 'SEEDPAST1', name: 'Last week rally', coachUid: coaches[0].uid, venue: venues.waverley, offsetDays: -7 },
      { id: 'seed-event-past-2', code: 'SEEDPAST2', name: 'Two weeks ago social', coachUid: coaches[1].uid, venue: venues.addison, offsetDays: -14 },
    ];
    const feedbackTemplates = [
      { rating: 5, tags: ['coaching', 'atmosphere'], comment: 'Great session, really enjoyed the coaching.' },
      { rating: 4, tags: ['people', 'timing'], comment: 'Good fun, started a few minutes late.' },
    ];
    for (const [i, spec] of past.entries()) {
      const startsAt = Timestamp.fromMillis(nowMs + spec.offsetDays * day);
      const endsAt = Timestamp.fromMillis(nowMs + spec.offsetDays * day + 3600000);
      await create(db, `events/${spec.id}`, event({ ...spec, startsAt, endsAt }));
      for (const [j, participant] of participants.slice(0, 2).entries()) {
        const checkinId = `${spec.id}_${participant.uid}`;
        const scannedAt = Timestamp.fromMillis(endsAt.toMillis() - 1800000);
        await create(db, `checkins/${checkinId}`, {
          feedbackReminderPending: false, eventId: spec.id, uid: participant.uid, scannedAt, method: 'manual',
          lat: spec.venue.lat, lng: spec.venue.lng, distanceM: 0, status: 'confirmed', confirmedBy: spec.coachUid,
          confirmedAt: scannedAt, walkIn: false, corrections: [], eventEndsAt: endsAt, seedSource,
        });
        const template = feedbackTemplates[(i + j) % feedbackTemplates.length];
        await create(db, `feedback/${checkinId}`, {
          uid: participant.uid, eventId: spec.id, rating: template.rating, tags: template.tags,
          comment: template.comment, createdAt: Timestamp.fromMillis(endsAt.toMillis() + 600000), seedSource,
        });
      }
    }

    return {
      coaches: coaches.length, participants: participants.length,
      upcomingEvents: upcoming.length, pastEvents: past.length, secretsIssued,
    };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await seedStaging();
  console.log(JSON.stringify(result, null, 2));
}
