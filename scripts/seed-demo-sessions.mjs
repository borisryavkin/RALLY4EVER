import { pathToFileURL } from 'node:url';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { requireRealStagingProject, projectId } from './seed-staging.mjs';
import { zonedTimeToUtc } from './schedule-parser.mjs';

const ACTOR_UID = 'seed-demo-sessions-script';
// Real public Sydney suburb coordinates, for plausible demo map markers --
// not real tennis/pickleball venues, no address claimed to exist there.
const VENUES = {
  bondiJunction: { name: 'Bondi Junction (demo)', suburb: 'Bondi Junction', postcode: '2022', state: 'NSW', lat: -33.8932, lng: 151.2502 },
  epping: { name: 'Epping (demo)', suburb: 'Epping', postcode: '2121', state: 'NSW', lat: -33.7728, lng: 151.0825 },
  parramatta: { name: 'Parramatta (demo)', suburb: 'Parramatta', postcode: '2150', state: 'NSW', lat: -33.8151, lng: 151.0011 },
  manly: { name: 'Manly (demo)', suburb: 'Manly', postcode: '2095', state: 'NSW', lat: -33.7969, lng: 151.2851 },
  chatswood: { name: 'Chatswood (demo)', suburb: 'Chatswood', postcode: '2067', state: 'NSW', lat: -33.7967, lng: 151.1807 },
  olympicPark: { name: 'Sydney Olympic Park (demo)', suburb: 'Sydney Olympic Park', postcode: '2127', state: 'NSW', lat: -33.8468, lng: 151.0634 },
};
const ZONE = 'Australia/Sydney', hour = 3600000;

// Today's Sydney calendar date, so "tomorrow at 6:30pm" means 6:30pm Sydney
// time regardless of what timezone this script happens to run in.
function sydneyToday(now) {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', { timeZone: ZONE, year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' })
      .formatToParts(now).map((x) => [x.type, x.value]),
  );
  return { year: +p.year, month: +p.month, day: +p.day, weekday: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday) };
}
function sydneyAt(today, daysFromNow, hourOfDay, minute = 0) {
  return zonedTimeToUtc(today.year, today.month, today.day + daysFromNow, hourOfDay, minute, ZONE);
}
function nextSaturday(today, hourOfDay) {
  const daysToSaturday = (6 - today.weekday + 7) % 7 || 7;
  return sydneyAt(today, daysToSaturday, hourOfDay);
}
function nextSunday(today, hourOfDay) {
  const daysToSunday = (0 - today.weekday + 7) % 7 || 7;
  return sydneyAt(today, daysToSunday, hourOfDay);
}

// One script run = one fixed demo schedule; re-running skips existing docs
// rather than re-rolling times -- see scripts/remove-demo-sessions.mjs to
// clear and reseed with fresh "starting soon" sessions.
function plan(now) {
  const today = sydneyToday(now);
  const soon = new Date(now.getTime() + 40 * 60000);
  return [
    { id: 'demo-tennis-bondi-now', sport: 'tennis', venue: VENUES.bondiJunction, level: 'social', price: 'Free', capacity: 8,
      startsAt: soon, durationMs: hour, coach: true, title: 'Social tennis' },
    { id: 'demo-tennis-epping-evening', sport: 'tennis', venue: VENUES.epping, level: 'beginner', price: 'Free', capacity: 10,
      startsAt: sydneyAt(today, 1, 18, 30), durationMs: hour, coach: true, title: 'Beginner tennis' },
    { id: 'demo-tennis-parramatta-weekend', sport: 'tennis', venue: VENUES.parramatta, level: 'intermediate', price: '$5', capacity: 12,
      startsAt: nextSaturday(today, 9), durationMs: 1.5 * hour, coach: false, title: 'Intermediate tennis' },
    { id: 'demo-tennis-manly-morning', sport: 'tennis', venue: VENUES.manly, level: 'social', price: 'Free', capacity: 8,
      startsAt: sydneyAt(today, 2, 7), durationMs: hour, coach: false, title: 'Morning social tennis' },
    { id: 'demo-tennis-chatswood-social', sport: 'tennis', venue: VENUES.chatswood, level: 'social', price: '$5', capacity: 6,
      startsAt: sydneyAt(today, 3, 17), durationMs: hour, coach: false, title: 'After-work social tennis' },
    { id: 'demo-tennis-olympicpark-intermediate', sport: 'tennis', venue: VENUES.olympicPark, level: 'intermediate', price: '$8', capacity: 10,
      startsAt: nextSunday(today, 15), durationMs: 1.5 * hour, coach: false, title: 'Intermediate tennis' },
    { id: 'demo-pickleball-bondi-beginner', sport: 'pickleball', venue: VENUES.bondiJunction, level: 'beginner', price: 'Free', capacity: 8,
      startsAt: sydneyAt(today, 1, 9), durationMs: hour, coach: true, title: 'Beginner pickleball' },
    { id: 'demo-pickleball-epping-social', sport: 'pickleball', venue: VENUES.epping, level: 'social', price: 'Free', capacity: 8,
      startsAt: sydneyAt(today, 0, 20), durationMs: hour, coach: false, title: 'Social pickleball' },
    { id: 'demo-pickleball-parramatta-evening', sport: 'pickleball', venue: VENUES.parramatta, level: 'social', price: '$5', capacity: 12,
      startsAt: sydneyAt(today, 1, 19), durationMs: hour, coach: false, title: 'Evening social pickleball' },
    { id: 'demo-pickleball-manly-weekend', sport: 'pickleball', venue: VENUES.manly, level: 'intermediate', price: '$8', capacity: 10,
      startsAt: nextSaturday(today, 11), durationMs: 1.5 * hour, coach: false, title: 'Intermediate pickleball' },
    { id: 'demo-pickleball-chatswood-beginner', sport: 'pickleball', venue: VENUES.chatswood, level: 'beginner', price: 'Free', capacity: 6,
      startsAt: sydneyAt(today, 2, 10), durationMs: hour, coach: false, title: 'Beginner pickleball' },
    { id: 'demo-pickleball-olympicpark-social', sport: 'pickleball', venue: VENUES.olympicPark, level: 'social', price: '$5', capacity: 10,
      startsAt: nextSunday(today, 18), durationMs: hour, coach: false, title: 'Social pickleball' },
  ];
}

export async function seedDemoSessions({ apply = false, coachUid } = {}) {
  requireRealStagingProject();
  const app = initializeApp({ credential: applicationDefault(), projectId }, `seed-demo-sessions-${Date.now()}`);
  const db = getFirestore(app);
  try {
    const sessions = plan(new Date());
    const summary = sessions.map((s) => ({
      id: s.id, title: `[DEMO] ${s.title}`, sport: s.sport, venue: s.venue.suburb,
      startsAt: s.startsAt.toISOString(), level: s.level, price: s.price, capacity: s.capacity,
      coachAssigned: s.coach && !!coachUid,
    }));
    if (!apply) return { dryRun: true, count: sessions.length, sessions: summary };

    let created = 0, skippedExisting = 0;
    for (const s of sessions) {
      const ref = db.doc(`events/${s.id}`);
      const now = Timestamp.now();
      const event = {
        isDemo: true,
        programId: null,
        catalogueManaged: false,
        name: `[DEMO] ${s.title}`,
        sport: s.sport,
        venue: { name: s.venue.name, address: '', suburb: s.venue.suburb, postcode: s.venue.postcode, state: s.venue.state, lat: s.venue.lat, lng: s.venue.lng },
        timezone: 'Australia/Sydney',
        notes: `[DEMO] ${s.level === 'beginner' ? 'Beginner-friendly' : s.level === 'intermediate' ? 'Intermediate level' : 'Social, all welcome'}. ${s.price === 'Free' ? 'Free to join.' : `Suggested donation ${s.price}.`} Invented demo data -- not a real session.`,
        photoUrl: '',
        coachNames: s.coach && coachUid ? ['Demo coach'] : [],
        coachUids: s.coach && coachUid ? [coachUid] : [],
        capacity: s.capacity,
        registrationStatus: 'open',
        bookedCount: 0,
        startsAt: Timestamp.fromDate(s.startsAt),
        endsAt: Timestamp.fromDate(new Date(s.startsAt.getTime() + s.durationMs)),
        status: 'published',
        code: `s-${s.id}`,
        requiredFormIds: ['conduct', 'waiver'],
        geofenceRadiusM: 150,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      };
      try {
        await ref.create(event);
        await db.collection('catalogueAudits').doc().create({
          kind: 'session', eventId: s.id, programId: null, actorUid: ACTOR_UID,
          reason: 'Demo session seeded via scripts/seed-demo-sessions.mjs for app review/testing',
          before: null, after: event, createdAt: now,
        });
        created++;
      } catch (error) {
        if (error.code === 6 || error.code === 'already-exists') skippedExisting++;
        else throw error;
      }
    }
    return { dryRun: false, created, skippedExisting, sessions: summary };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some((a) => a !== '--apply' && !a.startsWith('--coach-uid='))) {
    throw new Error('Usage: node scripts/seed-demo-sessions.mjs [--apply] [--coach-uid=<uid>]');
  }
  const coachUid = args.find((a) => a.startsWith('--coach-uid='))?.slice('--coach-uid='.length);
  const result = await seedDemoSessions({ apply: args.includes('--apply'), coachUid });
  console.log(JSON.stringify(result, null, 2));
}
