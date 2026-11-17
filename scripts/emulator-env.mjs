export const projectId = 'demo-rally4ever';

// Never allow Admin SDK fallback to application-default credentials/production.
export function requireEmulators() {
  const expected = {
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
    FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  };
  for (const [name, value] of Object.entries(expected)) {
    if (process.env[name] !== value) throw new Error(`${name} must be ${value}`);
  }
  for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
    if (process.env[name] && process.env[name] !== projectId) {
      throw new Error(`${name} must be ${projectId}`);
    }
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) throw new Error('Do not load credentials for emulator work');
  return projectId;
}
