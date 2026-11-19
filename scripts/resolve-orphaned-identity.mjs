import { pathToFileURL } from 'node:url';
import { writeFile } from 'node:fs/promises';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { requireRealStagingProject, projectId } from './seed-staging.mjs';
import { planProfileUpgrade } from './profile-schema.mjs';

const ACTOR_UID = 'resolve-orphaned-identity-script';

// Repairs one specific stuck state: `emailIdentities/{email}` still points
// to a uid whose Firestore profile exists but whose Auth account has been
// deleted, while the person's CURRENT, live Auth session (a different uid --
// e.g. because their old account was removed and they signed in again) has
// no profile of its own. functions/src/service.ts's reserveIdentity defers
// to the mapped "canonical" uid whenever the mapping exists, so this live
// session can never get a profile and every write it makes is denied by
// firestore.rules' active()/own() (both require an existing profile doc).
// This is NOT the normal two-real-accounts merge case (that's
// MergeService.mergeProfiles, used by admins through the app) -- here the
// source account is already gone, so there's no conflicting live identity to
// arbitrate, just a stale pointer to clean up. Never deletes the orphaned
// profile; only marks it mergedInto and repoints the email mapping.
export async function resolveOrphanedIdentity({ email, apply = false, backup } = {}) {
  requireRealStagingProject();
  const app = initializeApp(
    { credential: applicationDefault(), projectId },
    `resolve-identity-${Date.now()}`,
  );
  const db = getFirestore(app);
  const auth = getAuth(app);
  try {
    const mappingRef = db.doc(`emailIdentities/${email}`);
    const mapping = await mappingRef.get();
    if (!mapping.exists) return { status: 'no-mapping', note: 'Nothing to resolve; registerIdentity will create a fresh profile normally on next sign-in.' };
    const canonicalUid = mapping.data().uid;

    const currentAccount = await auth.getUserByEmail(email);
    const currentUid = currentAccount.uid;
    if (canonicalUid === currentUid) return { status: 'already-canonical', uid: currentUid };

    const canonicalAccount = await auth.getUser(canonicalUid).catch((e) => ({ error: e.code }));
    if (!canonicalAccount.error) {
      return {
        status: 'canonical-still-active',
        note: 'The mapped uid still has a live Auth account -- this is a real two-account merge decision for an admin (MergeService.mergeProfiles), not an automatic repair.',
        canonicalUid,
        currentUid,
      };
    }

    const canonicalProfileRef = db.doc(`users/${canonicalUid}`);
    const canonicalProfile = await canonicalProfileRef.get();
    if (!canonicalProfile.exists) return { status: 'no-orphan-profile', canonicalUid, currentUid };
    if (canonicalProfile.data().mergedInto !== null) return { status: 'already-merged', canonicalUid, currentUid };

    const currentProfileRef = db.doc(`users/${currentUid}`);
    const currentProfile = await currentProfileRef.get();
    if (currentProfile.exists) {
      return {
        status: 'target-already-exists',
        note: 'The live uid already has its own profile; use the admin console\'s merge tool instead of this script.',
        canonicalUid,
        currentUid,
      };
    }

    const canonicalContactRef = db.doc(`users/${canonicalUid}/private/contact`);
    const canonicalContact = await canonicalContactRef.get();
    const upgrade = planProfileUpgrade(canonicalProfile.data(), canonicalContact.exists ? canonicalContact.data() : null);

    const plan = {
      status: 'dry-run',
      email,
      canonicalUid,
      currentUid,
      willDo: [
        `Create users/${currentUid} for the live session, carrying over and schema-upgrading the orphaned profile's real answers`,
        `Create users/${currentUid}/private/contact from the orphaned contact (or its legacy top-level mobile/emergencyContact)`,
        `Set users/${canonicalUid}.mergedInto = '${currentUid}' (kept on disk, never deleted)`,
        `Repoint emailIdentities/${email}.uid from '${canonicalUid}' to '${currentUid}'`,
      ],
      orphanProfilePreview: canonicalProfile.data(),
      upgradedProfilePreview: { ...upgrade.profile, uid: currentUid },
    };
    if (!apply) return plan;
    if (!backup) throw new Error('--backup is required before any writes');

    await writeFile(
      backup,
      JSON.stringify(
        {
          version: 1,
          email,
          canonicalUid,
          currentUid,
          orphanProfile: canonicalProfile.data(),
          orphanContact: canonicalContact.exists ? canonicalContact.data() : null,
          mapping: mapping.data(),
          savedAt: new Date().toISOString(),
        },
        null,
        2,
      ),
      { flag: 'wx', mode: 0o600 },
    );

    const now = Timestamp.now();
    const newProfile = {
      ...upgrade.profile,
      uid: currentUid,
      email,
      emailLower: email,
      createdAt: canonicalProfile.data().createdAt ?? now,
      updatedAt: now,
    };
    const newContact = { ...upgrade.contact, updatedAt: now };

    await db.runTransaction(async (tx) => {
      const [freshOld, freshNew] = await Promise.all([tx.get(canonicalProfileRef), tx.get(currentProfileRef)]);
      if (freshOld.data().mergedInto !== null) throw new Error('Orphan profile was merged concurrently; aborting without writing');
      if (freshNew.exists) throw new Error('Target profile was created concurrently; aborting without writing');
      tx.create(currentProfileRef, newProfile);
      tx.create(db.doc(`users/${currentUid}/private/contact`), newContact);
      tx.update(canonicalProfileRef, { mergedInto: currentUid, updatedAt: now });
      tx.update(mappingRef, { uid: currentUid, updatedAt: now });
      tx.create(db.collection('mergeAudits').doc(), {
        type: 'orphaned-identity-resolution',
        sourceUid: canonicalUid,
        targetUid: currentUid,
        reason: `${canonicalUid}'s Auth account no longer exists; ${currentUid} is ${email}'s live signed-in session`,
        actorUid: ACTOR_UID,
        createdAt: now,
      });
    });
    return { status: 'applied', canonicalUid, currentUid, backup };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = new Map(process.argv.slice(2).map((a) => a.split('=')));
  const email = args.get('--email');
  if (!email) throw new Error('Usage: node scripts/resolve-orphaned-identity.mjs --email=<email> [--apply --backup=<path>]');
  const result = await resolveOrphanedIdentity({ email, apply: args.has('--apply'), backup: args.get('--backup') });
  console.log(JSON.stringify(result, null, 2));
}
