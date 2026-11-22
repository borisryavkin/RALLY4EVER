import { readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
const raw = JSON.parse(
  await readFile(
    new URL("../config/staging.web.json", import.meta.url),
    "utf8",
  ),
);
const config = {};
for (const key of [
  "apiKey",
  "authDomain",
  "projectId",
  "storageBucket",
  "messagingSenderId",
  "appId",
])
  config[key] =
    raw[key] ??
    raw["FIREBASE_" + key.replace(/[A-Z]/g, (c) => "_" + c).toUpperCase()];
if (
  config.projectId !== "rally4ever-3adaf" ||
  !config.apiKey ||
  !config.appId?.includes(":web:") ||
  !config.storageBucket
)
  throw Error("Real staging web Firebase configuration required");
// Only public Firebase client identifiers are emitted. Never copy Admin API configuration.
await writeFile(
  new URL("../web-checkin/src/firebase-config.generated.json", import.meta.url),
  JSON.stringify(config),
  { mode: 0o600 },
);
const r = spawnSync("npm", ["--prefix", "web-checkin", "run", "build"], {
  stdio: "inherit",
});
process.exit(r.status ?? 1);
