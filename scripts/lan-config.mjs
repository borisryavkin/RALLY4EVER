import { networkInterfaces } from "node:os";

export function isPrivateIPv4(host) {
  if (typeof host !== "string") return false;
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
export function makeLanConfig(base, env) {
  if (env.LAN_TESTING !== "true")
    throw new Error("Explicit LAN_TESTING=true is required");
  if (!isPrivateIPv4(env.LAN_HOST))
    throw new Error("LAN_HOST must be the Mac’s private IPv4 address");
  for (const key of [
    "GCLOUD_PROJECT",
    "GOOGLE_CLOUD_PROJECT",
    "FIREBASE_PROJECT_ID",
  ]) {
    if (env[key] && env[key] !== "demo-rally4ever")
      throw new Error("Only demo-rally4ever is allowed");
  }
  if (env.NODE_ENV === "production" || env.GOOGLE_APPLICATION_CREDENTIALS)
    throw new Error(
      "LAN mode is development-only; do not load production credentials",
    );
  if (env.FIREBASE_CONFIG) {
    const config = JSON.parse(env.FIREBASE_CONFIG);
    if (config.projectId && config.projectId !== "demo-rally4ever")
      throw new Error("Production Firebase config is forbidden");
  }
  const config = structuredClone(base);
  for (const service of ["auth", "firestore", "functions"]) {
    if (!config.emulators?.[service])
      throw new Error(`Missing ${service} emulator config`);
    config.emulators[service].host = "0.0.0.0";
  }
  // Keep the privileged emulator UI, discovery hub and logs on the Mac only.
  config.emulators.ui = { ...config.emulators.ui, host: "127.0.0.1" };
  config.emulators.hub = { host: "127.0.0.1", port: 4400 };
  config.emulators.logging = { host: "127.0.0.1", port: 4500 };
  return config;
}
export function requireLocalInterface(host, interfaces = networkInterfaces()) {
  if (
    !Object.values(interfaces)
      .flat()
      .some((i) => i && !i.internal && i.address === host)
  )
    throw new Error(
      "LAN_HOST is not an address assigned to this Mac; check Wi-Fi IPv4 settings",
    );
}
