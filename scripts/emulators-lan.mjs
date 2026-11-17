import { readFile, writeFile, unlink } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { makeLanConfig, requireLocalInterface } from "./lan-config.mjs";

if (process.argv.length > 2)
  throw new Error(
    "Use LAN_TESTING and LAN_HOST environment flags; CLI overrides are not allowed",
  );
const root = fileURLToPath(new URL("../", import.meta.url));
const base = JSON.parse(
  await readFile(new URL("../firebase.json", import.meta.url), "utf8"),
);
const config = makeLanConfig(base, process.env);
requireLocalInterface(process.env.LAN_HOST);
const generated = new URL("../.firebase.lan.generated.json", import.meta.url);
await writeFile(generated, JSON.stringify(config, null, 2) + "\n", {
  mode: 0o600,
  flag: "wx",
});
let child;
const onInterrupt = () => child?.kill("SIGINT");
const onTerminate = () => child?.kill("SIGTERM");
process.on("SIGINT", onInterrupt);
process.on("SIGTERM", onTerminate);
function run(command, args) {
  return new Promise((resolve, reject) => {
    child = spawn(command, args, {
      cwd: root,
      env: { ...process.env, DEMO_PROJECT_ID: "demo-rally4ever" },
      stdio: "inherit",
    });
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve(signal ? 1 : (code ?? 1)));
  });
}
try {
  console.warn(
    `LAN TESTING: exposing DEMO Auth/Firestore/Functions on Wi-Fi (${process.env.LAN_HOST}). Use trusted Wi-Fi and synthetic data only. Emulator UI stays on loopback.`,
  );
  const build = await run("npm", ["--prefix", "functions", "run", "build"]);
  process.exitCode =
    build === 0
      ? await run(
          fileURLToPath(
            new URL("../node_modules/.bin/firebase", import.meta.url),
          ),
          [
            "emulators:start",
            "--config",
            fileURLToPath(generated),
            "--project",
            "demo-rally4ever",
            "--only",
            "auth,firestore,functions",
          ],
        )
      : build;
} finally {
  process.removeListener("SIGINT", onInterrupt);
  process.removeListener("SIGTERM", onTerminate);
  await unlink(generated);
}
