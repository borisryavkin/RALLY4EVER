export const origin = "https://rally4ever-checkin-3adaf.web.app";
export function readLink(raw) {
  const outer = new URL(raw);
  if (outer.searchParams.has("link"))
    return readLink(outer.searchParams.get("link"));
  let source = outer;
  if (outer.searchParams.has("continueUrl")) {
    source = new URL(outer.searchParams.get("continueUrl"));
    if (source.origin !== origin)
      throw Error("Invalid verification return address");
  }
  if (
    ![origin, "https://rally4ever.org", "http://localhost:57832"].includes(
      source.origin,
    )
  )
    throw Error("Invalid check-in address");
  const match = source.pathname.match(/^\/c\/([A-Za-z0-9-]{1,128})$/);
  const secret = source.searchParams.get("k");
  if (!match || !secret || !/^[A-Za-z0-9_-]{43}$/.test(secret))
    throw Error("Scan the current QR shown by your coach to open a session.");
  return {
    eventCode: match[1],
    secret,
    requestId: source.searchParams.get("noAppRequest"),
    oobCode: outer.searchParams.get("oobCode"),
  };
}
export function friendlyError(e) {
  const reason = e.details?.reason;
  return reason === "too-far"
    ? "You are too far from the court. Move closer and try again."
    : reason === "invalid-secret"
      ? "This QR expired. Scan the current code shown by your coach."
      : reason === "rate-limit"
        ? "Too many attempts. Wait a little or ask the coach to help."
        : (e.message ??
          "Check-in could not be completed. Ask the coach for help.");
}
export function timestamp(iso, timezone) {
  return new Intl.DateTimeFormat("en-AU", {
    timeZone: timezone ?? "Australia/Sydney",
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(iso));
}
export const versionMap = (forms) =>
  Object.fromEntries(
    forms.flatMap((f) =>
      (f.sources ?? [f]).map((source) => [source.id, source.version]),
    ),
  );

const memoryTokens = new Map();
export function anonymousTokenFor(eventId, storage) {
  const key = "r4e-anonymous-checkin:" + eventId;
  let saved;
  try {
    storage ??= globalThis.localStorage;
    saved = storage?.getItem(key);
  } catch {
    /* In-memory fallback when storage is unavailable. */
  }
  if (/^[A-Za-z0-9_-]{43}$/.test(saved ?? "")) return saved;
  if (memoryTokens.has(key)) return memoryTokens.get(key);
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const token = btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  memoryTokens.set(key, token);
  try {
    storage?.setItem(key, token);
  } catch {
    /* Coach confirmation also guards headcount. */
  }
  return token;
}

export function agreementGroups(forms) {
  return [
    ["conduct", "Code of Conduct", ["conduct", "waiver"]],
    ["data-collection", "Data Collection", ["data-collection"]],
    ["photo-release", "Photo Release", ["photo-release"]],
  ].map(([id, title, ids]) => {
    const sources = ids.flatMap((key) => forms.filter((f) => f.id === key));
    if (sources.length !== ids.length)
      throw Error("A required agreement is missing. Please ask your coach.");
    return {
      ...sources[0],
      id,
      title,
      body: sources.map((f) => f.body ?? f.content ?? "").join("\n\n"),
      sources,
      required: true,
    };
  });
}
