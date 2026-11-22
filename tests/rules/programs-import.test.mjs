import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc } from 'firebase/firestore';
import { requireEmulators, projectId } from '../../scripts/emulator-env.mjs';

let env;
const user = (uid, claims = {}) =>
  env.authenticatedContext(uid, { email_verified: true, role: 'participant', ...claims }).firestore();

before(async () => {
  requireEmulators();
  env = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile('firestore.rules', 'utf8') },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      // Deliberately not the shared admin-1/participant-1 fixture UIDs
      // from scripts/fixtures.mjs: this file shares a live Firestore
      // emulator with every other tests/rules/*.test.mjs file in the same
      // run, and those UIDs are used elsewhere with different expected
      // field values.
      setDoc(doc(db, 'users/programs-import-test-participant'), {
        uid: 'programs-import-test-participant', email: 'participant@example.test',
        emailLower: 'participant@example.test', role: 'participant', mergedInto: null,
      }),
      setDoc(doc(db, 'users/programs-import-test-admin'), {
        uid: 'programs-import-test-admin', email: 'admin@example.test',
        emailLower: 'admin@example.test', role: 'admin', mergedInto: null,
      }),
      setDoc(doc(db, 'programOperational/nsw-tennis-armidale'), {
        coachName: 'Damian Roff', coachNumber: '0400000000',
        contactName: 'Glen', contactEmail: 'glen@example.test',
        notes: 'Internal note never shown to a participant',
      }),
      setDoc(doc(db, 'venueOperational/v-example'), {
        contactName: 'Jane', contactEmail: 'jane@example.test',
      }),
    ]);
  });
});

test('a signed-out user cannot read program or venue operational data', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'programOperational/nsw-tennis-armidale')));
  await assertFails(getDoc(doc(db, 'venueOperational/v-example')));
});

test('a normal participant cannot read program or venue operational data', async () => {
  const db = user('programs-import-test-participant');
  await assertFails(getDoc(doc(db, 'programOperational/nsw-tennis-armidale')));
  await assertFails(getDoc(doc(db, 'venueOperational/v-example')));
});

test('a participant cannot write operational data either (admin-script-only via Admin SDK)', async () => {
  const db = user('programs-import-test-participant');
  await assertFails(setDoc(doc(db, 'programOperational/nsw-tennis-armidale'), { coachName: 'Hacked' }));
});

test('an admin can read operational data', async () => {
  const db = user('programs-import-test-admin', { role: 'admin' });
  await assertSucceeds(getDoc(doc(db, 'programOperational/nsw-tennis-armidale')));
  await assertSucceeds(getDoc(doc(db, 'venueOperational/v-example')));
});

test('even an admin cannot write operational data through client rules (Admin SDK import script only)', async () => {
  const db = user('programs-import-test-admin', { role: 'admin' });
  await assertFails(setDoc(doc(db, 'programOperational/nsw-tennis-armidale'), { coachName: 'Hacked' }));
});
