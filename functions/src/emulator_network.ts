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
export function assertEmulatorNetwork(
  env: NodeJS.ProcessEnv = process.env,
): void {
  if (
    env.FUNCTIONS_EMULATOR !== "true" ||
    env.GCLOUD_PROJECT !== "demo-rally4ever"
  )
    throw new Error("Demo emulators required");
  for (const key of ["GOOGLE_CLOUD_PROJECT", "FIREBASE_PROJECT_ID"])
    if (env[key] && env[key] !== "demo-rally4ever")
      throw new Error("Production project forbidden");
  if (env.FIREBASE_CONFIG) {
    const config = JSON.parse(env.FIREBASE_CONFIG);
    if (config.projectId && config.projectId !== "demo-rally4ever")
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
export function authEmulatorOrigin(): string {
  return `http://${lanHost() ?? "127.0.0.1"}:9099`;
}
export function developmentWebOrigin(): string {
  const lan = lanHost();
  return lan ? `http://${lan}:57602` : "http://localhost:7357";
}
