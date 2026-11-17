import { pathToFileURL } from 'node:url';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { requireEmulators, projectId } from './emulator-env.mjs';
import { accounts, demoPassword, profile, emailHash, event } from './fixtures.mjs';

export async function seed() {
  requireEmulators();
  const app = initializeApp({projectId}, `seed-${Date.now()}`);
  const auth = getAuth(app), db = getFirestore(app);
  try {
    const now = Timestamp.now();
    // Create-only documents/accounts: rerunning never overwrites edited fixture data.
    async function create(path, data) {
      try { await db.doc(path).create(data); }
      catch (error) { if (error.code !== 6 && error.code !== 'already-exists') throw error; }
    }
    for (const account of accounts) {
      try {
        await auth.createUser({uid: account.uid, email: account.email, emailVerified: true, password: demoPassword});
      } catch (error) {
        if (error.code !== 'auth/uid-already-exists') throw error;
        const existing = await auth.getUser(account.uid);
        if (existing.email !== account.email) throw new Error(`Seed identity collision: ${account.uid}`);
      }
      await auth.setCustomUserClaims(account.uid, {role: account.role});
      await create(`users/${account.uid}`, profile(account, now));
      await create(`emailIdentities/${emailHash(account.email)}`, {
        emailLower: account.email, uid: account.uid, createdAt: now,
      });
    }
    for (const [id, offset, coach] of [['event-1', 0, 'coach-1'], ['event-2', 86400000, 'coach-2'], ['event-3', -86400000, 'coach-1']]) {
      await create(`events/${id}`, event(id, coach,
        Timestamp.fromMillis(now.toMillis() + offset - 300000),
        Timestamp.fromMillis(now.toMillis() + offset + 3600000)));
    }
    for (const formType of ['conduct', 'waiver']) {
      await create(`forms/${formType}`, {formType, version: 1, title: `Demo ${formType}`, content: 'Emulator fixture only; not approved legal text.', updatedAt: now});
    }
    await create('rsvps/event-1_participant-1', {
      eventId: 'event-1', uid: 'participant-1', createdAt: now, cancelledAt: null, source: 'coach-added',
    });
    await create('checkins/event-3_participant-1', {
      eventId: 'event-3', uid: 'participant-1', scannedAt: now, method: 'manual',
      lat: -33.8926, lng: 151.2511, distanceM: 0, status: 'confirmed', confirmedBy: 'coach-1',
      confirmedAt: now, walkIn: false, corrections: [],
      eventEndsAt: Timestamp.fromMillis(now.toMillis() - 82800000),
    });
    return {accounts: accounts.length, events: 3};
  } finally { await deleteApp(app); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(await seed());
}
