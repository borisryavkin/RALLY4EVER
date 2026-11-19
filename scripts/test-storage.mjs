import { readFile, writeFile, unlink } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const config = JSON.parse(await readFile(new URL('../firebase.json', import.meta.url), 'utf8'));
config.firestore.rules = fileURLToPath(new URL('../firestore.rules', import.meta.url));
config.firestore.indexes = fileURLToPath(new URL('../firestore.indexes.json', import.meta.url));
config.storage.rules = fileURLToPath(new URL('../storage.rules', import.meta.url));
config.emulators = {
  auth: { host: '127.0.0.1', port: 23999 },
  firestore: { host: '127.0.0.1', port: 23880 },
  storage: { host: '127.0.0.1', port: 23199 },
  ui: { enabled: false },
  hub: { host: '127.0.0.1', port: 24400 },
  logging: { host: '127.0.0.1', port: 24401 },
  singleProjectMode: true,
};
const generated = new URL('../.firebase.storage-tests.generated.json', import.meta.url);
const env = { ...process.env, GCLOUD_PROJECT: 'demo-rally4ever', GOOGLE_CLOUD_PROJECT: 'demo-rally4ever' };
for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_CONFIG', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST', 'FIREBASE_EMULATOR_HUB']) delete env[key];

let ownConfig = false;
try {
  await writeFile(generated, JSON.stringify(config, null, 2), { flag: 'wx', mode: 0o600 });
  ownConfig = true;
  const code = await new Promise((resolve, reject) => {
    const child = spawn(
      fileURLToPath(new URL('../node_modules/.bin/firebase', import.meta.url)),
      ['emulators:exec', '--project', 'demo-rally4ever', '--config', fileURLToPath(generated), '--only', 'auth,firestore,storage', 'node --test tests/storage/photo-rules.test.mjs'],
      { cwd: root, env, stdio: 'inherit' },
    );
    child.on('error', reject);
    child.on('exit', resolve);
  });
  process.exitCode = code ?? 1;
} finally {
  if (ownConfig) await unlink(generated);
}
