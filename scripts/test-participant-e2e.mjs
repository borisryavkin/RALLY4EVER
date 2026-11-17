import { spawn } from "node:child_process";
import { seed } from "./seed.mjs";
await seed();
const command = spawn(
  "flutter",
  [
    "test",
    "--platform",
    "chrome",
    "--dart-define=USE_FIREBASE_EMULATORS=true",
    "test/emulator/participant_flow_test.dart",
  ],
  { stdio: "inherit", env: process.env },
);
const deadline = setTimeout(() => {
  console.error("Browser emulator test exceeded 3 minutes");
  command.kill("SIGTERM");
  process.exitCode = 1;
}, 180000);
command.on("exit", (code, signal) => {
  clearTimeout(deadline);
  if (process.exitCode !== 1) process.exitCode = signal ? 1 : (code ?? 1);
});
