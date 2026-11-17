import {test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInWithEmailAndPassword, signOut, getIdTokenResult} from 'firebase/auth';
import {getFirestore, connectFirestoreEmulator, doc, getDoc, getDocs, collection, query, where} from 'firebase/firestore';
import {seed} from '../../scripts/seed.mjs';
import {accounts, demoPassword, normalizeEmail, identityKey} from '../../scripts/fixtures.mjs';
import {requireEmulators, projectId} from '../../scripts/emulator-env.mjs';

test('seed + real Auth emulator login: roles and canonical coach-added intent',async () => {
  requireEmulators();
  assert.deepEqual(await seed(),{accounts:13,events:3});
  assert.deepEqual(await seed(),{accounts:13,events:3}); // safe to rerun
  assert.equal(identityKey('  MEMBER1@EXAMPLE.TEST '),identityKey('member1@example.test'));
  const app=initializeApp({apiKey:'demo-api-key',projectId,appId:'demo-auth-test'},'auth-integration');
  const auth=getAuth(app), db=getFirestore(app);
  connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
  connectFirestoreEmulator(db,'127.0.0.1',8080);
  try {
    for (const account of [accounts[0],accounts[1],accounts[2],accounts[3]]) {
      const {user}=await signInWithEmailAndPassword(auth,normalizeEmail(` ${account.email.toUpperCase()} `),demoPassword);
      assert.equal(user.uid,account.uid); assert.equal(user.emailVerified,true);
      assert.equal((await getIdTokenResult(user)).claims.role,account.role);
      const p=await getDoc(doc(db,`users/${user.uid}`));
      assert.equal(p.data().role,account.role); assert.equal(p.data().emailLower,account.email);
      if(account.role==='participant') {
        const intent=await getDocs(query(collection(db,'rsvps'),where('uid','==',user.uid)));
        assert.equal(intent.size,1);
        assert.equal(intent.docs[0].data().source,'coach-added');
        assert.equal(intent.docs[0].data().eventId,'event-1');
      }
      await signOut(auth);
    }
    await assert.rejects(signInWithEmailAndPassword(auth,accounts[3].email,'wrong-password'));
  } finally {await deleteApp(app);}
});

test('seed fails closed without emulator configuration or with production project',async () => {
  const original=process.env.FIRESTORE_EMULATOR_HOST;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    await assert.rejects(seed(),/FIRESTORE_EMULATOR_HOST/);
    process.env.FIRESTORE_EMULATOR_HOST='firestore.googleapis.com:443';
    await assert.rejects(seed(),/FIRESTORE_EMULATOR_HOST/);
  } finally {process.env.FIRESTORE_EMULATOR_HOST=original;}
});
