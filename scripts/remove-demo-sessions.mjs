import { pathToFileURL } from 'node:url';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { requireRealStagingProject, projectId } from './seed-staging.mjs';

// Deletes only events/{id} docs with isDemo === true (optionally narrowed
// further to one seedBatch), and their rsvps and checkins (so no orphaned
// attendance references a deleted demo session). Never matches on title --
// matches by field only. Never touches users/profiles. Dry run by default.
export async function removeDemoSessions({ apply = false, seedBatch } = {}) {
  requireRealStagingProject();
  const app = initializeApp({ credential: applicationDefault(), projectId }, `remove-demo-sessions-${Date.now()}`);
  const db = getFirestore(app);
  try {
    let query = db.collection('events').where('isDemo', '==', true);
    if (seedBatch) query = query.where('seedBatch', '==', seedBatch);
    const demo = await query.get();
    const ids = demo.docs.map((d) => d.id);
    if (!apply) return { dryRun: true, count: ids.length, eventIds: ids };

    let removed = 0;
    for (const id of ids) {
      const [rsvps, checkins] = await Promise.all([
        db.collection('rsvps').where('eventId', '==', id).get(),
        db.collection('checkins').where('eventId', '==', id).get(),
      ]);
      const batch = db.batch();
      for (const d of rsvps.docs) batch.delete(d.ref);
      for (const d of checkins.docs) batch.delete(d.ref);
      batch.delete(db.doc(`events/${id}`));
      batch.delete(db.doc(`eventSecrets/${id}`));
      await batch.commit();
      removed++;
    }
    return { dryRun: false, removed, eventIds: ids };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.some((a) => a !== '--apply' && !a.startsWith('--seed-batch='))) {
    throw new Error('Usage: node scripts/remove-demo-sessions.mjs [--apply] [--seed-batch=<value>]. Default is dry-run.');
  }
  const seedBatch = args.find((a) => a.startsWith('--seed-batch='))?.slice('--seed-batch='.length);
  const result = await removeDemoSessions({ apply: args.includes('--apply'), seedBatch });
  console.log(JSON.stringify(result, null, 2));
}
