import { requireEmulators } from "./emulator-env.mjs";
import { demoPassword } from "./fixtures.mjs";

requireEmulators();
const args = process.argv.slice(2);
const allowed = ["--source", "--target", "--reason", "--dry-run-id", "--apply"];
for (let i = 0; i < args.length; i++) {
  if (!allowed.includes(args[i])) throw new Error(`Unknown option: ${args[i]}`);
  if (args[i] !== "--apply") i++;
}
const value = (flag) => {
  const n = args.indexOf(flag);
  return n < 0 ? undefined : args[n + 1];
};
const sourceUid = value("--source"),
  targetUid = value("--target"),
  reason = value("--reason");
if (!sourceUid || !targetUid || !reason)
  throw new Error("Required: --source UID --target UID --reason TEXT");
const dryRun = !args.includes("--apply"),
  dryRunId = value("--dry-run-id");
if (!dryRun && !dryRunId)
  throw new Error("--apply requires --dry-run-id from a reviewed plan");
const authResponse = await fetch(
  "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key",
  {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      email: "admin@rally4ever.org",
      password: demoPassword,
      returnSecureToken: true,
    }),
  },
);
const account = await authResponse.json();
if (!authResponse.ok) throw new Error("Local fixture admin sign-in failed");
const response = await fetch(
  "http://127.0.0.1:5001/demo-rally4ever/australia-southeast1/mergeProfiles",
  {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${account.idToken}`,
    },
    body: JSON.stringify({
      data: {
        sourceUid,
        targetUid,
        reason,
        dryRun,
        ...(dryRunId ? { dryRunId } : {}),
      },
    }),
  },
);
const result = await response.json();
if (result.error) {
  console.error(JSON.stringify(result.error, null, 2));
  process.exitCode = 1;
} else console.log(JSON.stringify(result.result, null, 2));
