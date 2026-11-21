import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let env;
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xdb, ...new Array(100).fill(0)]);
const jpegMeta = { contentType: 'image/jpeg' };

const storage = (uid, role = uid === 'admin-1' ? 'admin' : 'participant') =>
  env.authenticatedContext(uid, { email_verified: true, role }).storage();

async function seedProfile(uid, role, extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}`), { role, ...extra });
  });
}
async function seedContact(uid, visibleToCoachUids = []) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}/private/contact`), { visibleToCoachUids });
  });
}

before(async () => {
  if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:23880' || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:23999') {
    throw new Error('Isolated storage-test emulators required; never use the development instance');
  }
  env = await initializeTestEnvironment({
    projectId: 'demo-rally4ever',
    firestore: { host: '127.0.0.1', port: 23880, rules: await readFile('firestore.rules', 'utf8') },
    storage: { host: '127.0.0.1', port: 23199, rules: await readFile('storage.rules', 'utf8') },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await seedProfile('participant-1', 'participant');
  await seedContact('participant-1');
  await seedProfile('participant-2', 'participant');
  await seedContact('participant-2');
  await seedProfile('admin-1', 'admin');
  await seedProfile('coach-1', 'coach');
  await seedProfile('coach-2', 'coach');
});

test('owner can upload their own photo and read it back', async () => {
  const path = ref(storage('participant-1'), 'profilePhotos/participant-1/avatar.jpg');
  await assertSucceeds(uploadBytes(path, jpeg, jpegMeta));
  await assertSucceeds(getBytes(path));
});
test('a different signed-in user cannot write or read someone else\'s photo', async () => {
  const mine = ref(storage('participant-1'), 'profilePhotos/participant-1/avatar.jpg');
  await env.withSecurityRulesDisabled((ctx) => uploadBytes(ref(ctx.storage(), mine.fullPath), jpeg, jpegMeta));
  const asOther = ref(storage('participant-2'), 'profilePhotos/participant-1/avatar.jpg');
  await assertFails(uploadBytes(asOther, jpeg, jpegMeta));
  await assertFails(getBytes(asOther));
});
test('a non-image upload is refused', async () => {
  const path = ref(storage('participant-1'), 'profilePhotos/participant-1/avatar.jpg');
  const text = new TextEncoder().encode('not an image');
  await assertFails(uploadBytes(path, text, { contentType: 'text/plain' }));
});
test('an oversize upload is refused', async () => {
  const path = ref(storage('participant-1'), 'profilePhotos/participant-1/avatar.jpg');
  const tooBig = new Uint8Array(6 * 1024 * 1024);
  await assertFails(uploadBytes(path, tooBig, jpegMeta));
});
test('signed-out cannot upload or read', async () => {
  const anon = env.unauthenticatedContext().storage();
  const path = ref(anon, 'profilePhotos/participant-1/avatar.jpg');
  await assertFails(uploadBytes(path, jpeg, jpegMeta));
  await assertFails(getBytes(path));
});
test('admin can read any photo; an assigned coach can read only a participant who has granted them visibility', async () => {
  const mine = 'profilePhotos/participant-1/avatar.jpg';
  await env.withSecurityRulesDisabled((ctx) => uploadBytes(ref(ctx.storage(), mine), jpeg, jpegMeta));
  await assertSucceeds(getBytes(ref(storage('admin-1'), mine)));
  await assertFails(getBytes(ref(storage('coach-2'), mine)));
  await seedContact('participant-1', ['coach-1']);
  await assertSucceeds(getBytes(ref(storage('coach-1'), mine)));
  await assertFails(getBytes(ref(storage('coach-2'), mine)));
});
test('owner can delete their own photo; another user cannot', async () => {
  const mine = ref(storage('participant-1'), 'profilePhotos/participant-1/avatar.jpg');
  await env.withSecurityRulesDisabled((ctx) => uploadBytes(ref(ctx.storage(), mine.fullPath), jpeg, jpegMeta));
  await assertFails(deleteObject(ref(storage('participant-2'), mine.fullPath)));
  await assertSucceeds(deleteObject(mine));
});

test('venue photos require admin claim AND active profile; authenticated users can read', async () => {
 const path='venues/court-one/photo.jpg';
 await assertSucceeds(uploadBytes(ref(storage('admin-1'),path),jpeg,jpegMeta));
 await assertSucceeds(getBytes(ref(storage('participant-1'),path)));
 await assertFails(uploadBytes(ref(storage('participant-1'),path),jpeg,jpegMeta));
 await assertFails(uploadBytes(ref(storage('coach-1'),path),jpeg,jpegMeta));
 await assertFails(uploadBytes(ref(storage('admin-1','participant'),path),jpeg,jpegMeta));
 await assertSucceeds(getBytes(ref(env.unauthenticatedContext().storage(),path)));
 await assertFails(uploadBytes(ref(storage('admin-1'),'venues/court-one/code.html'),jpeg,{contentType:'text/html'}));
 await seedProfile('admin-1','participant');
 await assertFails(uploadBytes(ref(storage('admin-1'),path),jpeg,jpegMeta));
});

test('session photos are public; admin-only writes enforce MIME, size and revoked access',async()=>{
 const path='sessions/session-one/photo.jpg';
 await assertSucceeds(uploadBytes(ref(storage('admin-1'),path),jpeg,jpegMeta));
 await assertSucceeds(getBytes(ref(env.unauthenticatedContext().storage(),path)));
 await assertFails(uploadBytes(ref(storage('participant-1'),path),jpeg,jpegMeta));
 await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(),path),jpeg,jpegMeta));
 await assertFails(uploadBytes(ref(storage('admin-1'),path),jpeg,{contentType:'text/plain'}));
 await assertFails(uploadBytes(ref(storage('admin-1'),path),new Uint8Array(5*1024*1024+1),jpegMeta));
 await seedProfile('admin-1','participant');
 await assertFails(uploadBytes(ref(storage('admin-1'),path),jpeg,jpegMeta));
});
