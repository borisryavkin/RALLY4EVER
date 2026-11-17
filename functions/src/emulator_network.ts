export function isPrivateIPv4(host: string): boolean {
  const parts = host.split(".");
  if (
    parts.length !== 4 ||
    parts.some(
      (p) => !/^\d{1,3}$/.test(p) || Number(p) > 255 || String(Number(p)) !== p,
    )
  )
    return false;
  const [a, b] = parts.map(Number);
  return (
    a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168)
  );
}
export function lanHost(env: NodeJS.ProcessEnv = process.env): string | null {
  if (env.LAN_TESTING !== "true") {
    if (env.LAN_HOST) throw new Error("LAN_HOST requires LAN_TESTING=true");
    return null;
  }
  if (env.NODE_ENV === "production" || !isPrivateIPv4(env.LAN_HOST ?? ""))
    throw new Error("LAN testing requires a private IPv4 development host");
  return env.LAN_HOST!;
}
// The demo project identity is never hardcoded here: it only exists because
// emulator/test setups export DEMO_PROJECT_ID (see root package.json). A
// deployed Cloud Function never has that variable set, so this fails closed.
export function assertEmulatorNetwork(
  env: NodeJS.ProcessEnv = process.env,
): void {
  const demoProjectId = env.DEMO_PROJECT_ID;
  if (!demoProjectId) throw new Error("DEMO_PROJECT_ID must be set to run against the demo emulators");
  if (env.FUNCTIONS_EMULATOR !== "true" || env.GCLOUD_PROJECT !== demoProjectId)
    throw new Error("Demo emulators required");
  for (const key of ["GOOGLE_CLOUD_PROJECT", "FIREBASE_PROJECT_ID"])
    if (env[key] && env[key] !== demoProjectId)
      throw new Error("Production project forbidden");
  if (env.FIREBASE_CONFIG) {
    const config = JSON.parse(env.FIREBASE_CONFIG);
    if (config.projectId && config.projectId !== demoProjectId)
      throw new Error("Production config forbidden");
  }
  const lan = lanHost(env),
    hosts = lan ? ["127.0.0.1", "0.0.0.0", lan] : ["127.0.0.1"];
  for (const [key, port] of [
    ["FIRESTORE_EMULATOR_HOST", "8080"],
    ["FIREBASE_AUTH_EMULATOR_HOST", "9099"],
  ]) {
    if (!hosts.some((host) => env[key] === `${host}:${port}`))
      throw new Error("Unexpected emulator endpoint");
  }
}
// The only real (non-emulator) project these functions are approved to run
// against for real. This is a deliberate allowlist against misdeployment to
// some other project, not an identity used to verify tokens or pick which
// project to talk to — initializeApp() in index.ts still resolves that from
// the runtime itself. GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT are set by the
// Cloud Functions runtime itself (the same signal the Admin SDK's own
// getExplicitProjectId() uses), never by a caller, so this can't be spoofed
// by request data.
const APPROVED_PRODUCTION_PROJECT_ID = "rally4ever-3adaf";

export function assertApprovedProject(env: NodeJS.ProcessEnv = process.env): void {
  if (env.FUNCTIONS_EMULATOR === "true") {
    assertEmulatorNetwork(env);
    return;
  }
  const resolved = env.GOOGLE_CLOUD_PROJECT || env.GCLOUD_PROJECT;
  if (resolved !== APPROVED_PRODUCTION_PROJECT_ID)
    throw new Error("This project is not approved to run these functions for real");
}
export function authEmulatorOrigin(): string {
  return `http://${lanHost() ?? "127.0.0.1"}:9099`;
}
export function developmentWebOrigin(): string {
  const lan = lanHost();
  return lan ? `http://${lan}:57602` : "http://localhost:7357";
}
