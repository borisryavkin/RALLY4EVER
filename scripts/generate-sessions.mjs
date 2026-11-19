import { pathToFileURL } from 'node:url';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { requireRealStagingProject, projectId } from './seed-staging.mjs';
import { parseWeeklySchedule, nextWeeklyOccurrences } from './schedule-parser.mjs';

const WEEKS_AHEAD = 4;
const ACTOR_UID = 'generate-sessions-script';

// Mirrors functions/src/catalogue.ts's saveSession gates, since this script
// writes events/{eventId} directly with the Admin SDK and must not create a
// session that an admin couldn't also create through the app.
function gate(program) {
  const issues = [];
  if (program.status !== 'active') issues.push('program is not published (status != active)');
  if (program.venue?.lat == null || program.venue?.lng == null) issues.push('missing venue coordinates');
  if ((program.coachUids ?? []).length === 0) issues.push('no coach assigned');
  const schedule = parseWeeklySchedule(program.scheduleText);
  if (!schedule) issues.push('scheduleText is not a single confidently-parseable weekly day+time (not guessed)');
  return { issues, schedule };
}

function sessionId(programId, startsAt, timeZone) {
  const localDate = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(startsAt);
  return `gen-${programId}-${localDate}`;
}

export async function generateSessions({ apply = false } = {}) {
  requireRealStagingProject();
  const app = initializeApp(
    { credential: applicationDefault(), projectId },
    `generate-sessions-${Date.now()}`,
  );
  const db = getFirestore(app);
  try {
    const allPrograms = (await db.collection('programs').get()).docs.map((d) => ({ id: d.id, ...d.data() }));
    const now = new Date();

    // Status-independent preview so the real blockers (no coach assigned
    // anywhere yet, unparseable schedule text) are visible even before any
    // program has been published.
    const preview = allPrograms.map((p) => {
      const { issues, schedule } = gate(p);
      return { id: p.id, name: p.name, status: p.status, issues, parsedSchedule: schedule };
    });

    const activePrograms = allPrograms.filter((p) => p.status === 'active');
    const plan = [];
    for (const program of activePrograms) {
      const { issues, schedule } = gate(program);
      if (issues.length > 0) {
        plan.push({ programId: program.id, name: program.name, issues, sessions: [] });
        continue;
      }
      const starts = nextWeeklyOccurrences(schedule.weekday, schedule.startHour, schedule.startMinute, program.timezone, now, WEEKS_AHEAD);
      const durationMs = (schedule.endHour * 60 + schedule.endMinute - schedule.startHour * 60 - schedule.startMinute) * 60000;
      const sessions = starts.map((startsAt) => ({
        eventId: sessionId(program.id, startsAt, program.timezone),
        startsAt,
        endsAt: new Date(startsAt.getTime() + durationMs),
      }));
      plan.push({ programId: program.id, name: program.name, issues: [], sessions });
    }

    const toCreate = plan.flatMap((p) => p.sessions.map((s) => ({ ...s, programId: p.programId, name: p.name })));

    if (!apply) {
      // Idempotency check is read-only and safe to run in a dry run too, so
      // the reported count reflects what --apply would actually create.
      const existing = await Promise.all(toCreate.map((s) => db.doc(`events/${s.eventId}`).get()));
      const willCreate = toCreate.filter((_, i) => !existing[i].exists);
      return {
        dryRun: true,
        activePrograms: activePrograms.length,
        eligiblePrograms: plan.filter((p) => p.issues.length === 0).length,
        blockedPrograms: plan.filter((p) => p.issues.length > 0).map((p) => ({ programId: p.programId, name: p.name, issues: p.issues })),
        sessionsToCreate: willCreate.length,
        alreadyExist: toCreate.length - willCreate.length,
        estimatedWrites: willCreate.length * 2, // 1 events/{eventId} + 1 catalogueAudits doc, each
        estimatedReads: toCreate.length, // the existence check above
        plan: plan.map((p) => ({ ...p, sessions: p.sessions.map((s) => ({ eventId: s.eventId, startsAt: s.startsAt.toISOString(), endsAt: s.endsAt.toISOString() })) })),
        allProgramsPreview: preview,
      };
    }

    let created = 0,
      skippedExisting = 0;
    for (const session of toCreate) {
      const applied = await db.runTransaction(async (tx) => {
        const programRef = db.doc(`programs/${session.programId}`),
          eventRef = db.doc(`events/${session.eventId}`);
        const [programSnap, eventSnap] = await Promise.all([tx.get(programRef), tx.get(eventRef)]);
        if (eventSnap.exists) return false; // no duplicates on rerun
        const p = programSnap.data();
        if (!p || p.status !== 'active' || p.venue?.lat == null || p.venue?.lng == null || (p.coachUids ?? []).length === 0) return false;
        const at = Timestamp.now();
        const event = {
          programId: session.programId,
          catalogueManaged: true,
          name: p.name,
          sport: p.sport,
          venue: p.venue,
          timezone: p.timezone,
          notes: p.notes ?? '',
          photoUrl: p.photoUrl ?? '',
          coachNames: p.coachNames ?? [],
          coachUids: p.coachUids ?? [],
          capacity: p.capacity ?? null,
          registrationStatus: p.registrationStatus ?? 'open',
          bookedCount: 0,
          startsAt: Timestamp.fromDate(session.startsAt),
          endsAt: Timestamp.fromDate(session.endsAt),
          status: 'published',
          code: `s-${session.eventId}`,
          requiredFormIds: ['conduct', 'waiver'],
          geofenceRadiusM: 150,
          createdAt: at,
          updatedAt: at,
          revision: 1,
        };
        tx.create(eventRef, event);
        tx.create(db.collection('catalogueAudits').doc(), {
          kind: 'session',
          eventId: session.eventId,
          programId: session.programId,
          actorUid: ACTOR_UID,
          reason: `Generated from the program's weekly schedule via scripts/generate-sessions.mjs (next ${WEEKS_AHEAD} weeks)`,
          before: null,
          after: event,
          createdAt: at,
        });
        return true;
      });
      if (applied) created++;
      else skippedExisting++;
    }
    return { dryRun: false, created, skippedExisting, plan: plan.map((p) => ({ programId: p.programId, name: p.name, issues: p.issues, sessionCount: p.sessions.length })) };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some((a) => a !== '--apply')) {
    throw new Error('Usage: node scripts/generate-sessions.mjs [--apply]. Default is dry-run.');
  }
  const result = await generateSessions({ apply: args.includes('--apply') });
  console.log(JSON.stringify(result, null, 2));
}
