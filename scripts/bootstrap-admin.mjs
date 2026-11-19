import { pathToFileURL } from 'node:url';
import { randomBytes } from 'node:crypto';
import { initializeApp, deleteApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { requireRealStagingProject, projectId } from './seed-staging.mjs';

// Grants the admin role to one *existing* Auth user on the real staging
// project, by email. There is no in-app way to create the first admin --
// setUserRole requires an existing admin to call it.
// This script is the trusted, out-of-band bootstrap for that first account.
export async function bootstrapAdmin(email) {
  requireRealStagingProject();
  if (!email) {
    throw new Error('Usage: node scripts/bootstrap-admin.mjs <email>');
  }
  const app = initializeApp(
    { credential: applicationDefault(), projectId },
    `bootstrap-admin-${Date.now()}`,
  );
  const auth = getAuth(app),
    db = getFirestore(app);
  try {
    let account;
    try {
      account = await auth.getUserByEmail(email);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        throw new Error(
          `No Auth account for ${email} on ${projectId} yet. Sign in at least once in the app with this email first, then re-run this script.`,
        );
      }
      throw error;
    }
    const targetUid = account.uid;
    const profileRef = db.doc(`users/${targetUid}`);
    const profile = await profileRef.get();
    if (!profile.exists) {
      throw new Error(
        `No users/${targetUid} profile yet for ${email}. Complete onboarding in the app first, then re-run this script.`,
      );
    }
    if (profile.data().mergedInto != null) {
      throw new Error(
        `users/${targetUid} is a merged, inactive profile (mergedInto is set) -- find the active profile for this person instead.`,
      );
    }

    // Preserve any existing coach grant; admin and coach are independent.
    const previousClaims = account.customClaims ?? {};
    const roles = new Set(
      Array.isArray(previousClaims.roles) ? previousClaims.roles : [],
    );
    roles.add('participant');
    roles.add('admin');
    const now = Timestamp.now();
    const operationId = randomBytes(16).toString('hex');

    await auth.setCustomUserClaims(targetUid, {
      ...previousClaims,
      role: 'admin',
      roles: [...roles],
    });
    // Firestore rules' role() and functions' actor() both prefer the
    // profile's `role` field over the Auth claim, so the claim alone is
    // not enough -- see firestore.rules' role()/admin().
    await profileRef.update({ role: 'admin', updatedAt: now });
    // Visible in the existing admin audit trail alongside callable-driven
    // coach-role changes, even though this one ran outside the app.
    await db.doc(`roleAudits/${operationId}`).create({
      operationId,
      actorUid: 'bootstrap-admin-script',
      targetUid,
      reason: 'Bootstrapped via scripts/bootstrap-admin.mjs, run by an operator with ADC project access',
      action: 'admin-role',
      enabled: true,
      status: 'applied',
      createdAt: now,
      appliedAt: now,
    });

    return {
      uid: targetUid,
      email,
      roles: [...roles],
      auditId: operationId,
      refreshRequired: true,
    };
  } finally {
    await deleteApp(app);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await bootstrapAdmin(process.argv[2]);
  console.log(JSON.stringify(result, null, 2));
}
