import { pathToFileURL } from 'node:url';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { requireRealStagingProject, projectId } from './seed-staging.mjs';

const VENUE_PLACEHOLDER = /\(venue to verify\)\s*$/i;
const SCHEDULE_PLACEHOLDER = /^schedule to verify$/i;
const ACTOR_UID = 'publish-programs-script';

// Mirrors functions/src/catalogue.ts's saveSession gates that matter for a
// program to actually be usable once published -- a program missing these
// would publish "successfully" but an admin (or scripts/generate-sessions.mjs)
// could never create a real dated session against it.
function assess(program) {
  const venue = program.venue ?? {};
  const issues = [];
  if (venue.lat == null || venue.lng == null) issues.push('missing coordinates');
  if (!venue.name || VENUE_PLACEHOLDER.test(venue.name)) issues.push('missing venue location');
  if (!program.scheduleText?.trim() || SCHEDULE_PLACEHOLDER.test(program.scheduleText.trim())) issues.push('missing schedule');
  if ((program.sourceConflicts ?? []).length > 0) issues.push(`unresolved venue conflict (${program.sourceConflicts.length} source file(s) disagree)`);
  return issues;
}

function summarize(program) {
  const issues = assess(program);
  const v = program.venue ?? {};
  return {
    id: program.id,
    name: program.name,
    sport: program.sport,
    venue: [v.name, v.suburb, v.postcode, v.state].filter(Boolean).join(', '),
    coordinates: v.lat != null && v.lng != null ? `${v.lat},${v.lng}` : null,
    scheduleText: program.scheduleText ?? '',
    coachCount: (program.coachUids ?? []).length,
    issues,
    willPublish: issues.length === 0,
  };
}

export async function publishPrograms({ apply = false } = {}) {
  requireRealStagingProject();
  const app = initializeApp(
    { credential: applicationDefault(), projectId },
    `publish-programs-${Date.now()}`,
  );
  const db = getFirestore(app);
  try {
    const snap = await db.collection('programs').where('status', '==', 'draft').get();
    const programs = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const summaries = programs.map(summarize);
    const publishable = summaries.filter((p) => p.willPublish);
    const blocked = summaries.filter((p) => !p.willPublish);
    // No coach is assigned on any import yet; publishing doesn't require one
    // (the brief only asked to gate on location/coordinates/schedule), but a
    // published program still can't get a real session until it has one.
    const publishableWithoutCoach = publishable.filter((p) => p.coachCount === 0).length;

    if (!apply) {
      return {
        dryRun: true,
        draftCount: programs.length,
        willPublish: publishable.length,
        blocked: blocked.length,
        publishableWithoutCoach,
        programs: summaries,
      };
    }

    let published = 0;
    for (const p of publishable) {
      const applied = await db.runTransaction(async (tx) => {
        const ref = db.doc(`programs/${p.id}`);
        const current = await tx.get(ref);
        if (!current.exists || current.data().status !== 'draft') return false;
        const before = current.data();
        const at = Timestamp.now();
        const after = {
          ...before,
          status: 'active',
          needsVerification: false,
          reviewedBy: ACTOR_UID,
          reviewedAt: at,
          updatedAt: at,
          updatedBy: ACTOR_UID,
          revision: (before.revision ?? 0) + 1,
        };
        tx.set(ref, after, { merge: true });
        tx.create(db.collection('catalogueAudits').doc(), {
          kind: 'program',
          programId: p.id,
          actorUid: ACTOR_UID,
          reason: 'Bulk-published a complete imported draft via scripts/publish-programs.mjs',
          before,
          after,
          createdAt: at,
        });
        return true;
      });
      if (applied) published++;
    }
    return {
      dryRun: false,
      published,
      skipped: blocked.length,
      publishableWithoutCoach,
      programs: summaries,
    };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some((a) => a !== '--apply')) {
    throw new Error('Usage: node scripts/publish-programs.mjs [--apply]. Default is dry-run.');
  }
  const result = await publishPrograms({ apply: args.includes('--apply') });
  console.log(JSON.stringify(result, null, 2));
}
