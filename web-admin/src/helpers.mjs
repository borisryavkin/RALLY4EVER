export const fields = [
  "name",
  "code",
  "sport",
  "status",
  "registrationStatus",
  "startsAt",
  "endsAt",
  "timezone",
  "capacity",
  "bookedCount",
  "coachUids",
  "coachNames",
  "venue.name",
  "venue.suburb",
  "venue.postcode",
  "venue.lat",
  "venue.lng",
  "geofenceRadiusM",
  "requiredFormIds",
  "notes",
  "photoUrl",
  "isDemo",
  "seedBatch",
  "programId",
  "revision",
];
export const at = (row, key) => key.split(".").reduce((v, k) => v?.[k], row);
export function localTime(iso, zone = "Australia/Sydney") {
  if (!iso) return "";
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(new Date(iso))
      .map((p) => [p.type, p.value]),
  );
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function zonedISO(local, zone) {
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d$/.test(local))
    throw Error("Choose a complete date and time");
  const base = Date.parse(local + "Z");
  let guess = base;
  for (let i = 0; i < 4; i++) {
    const seen = Date.parse(
      localTime(new Date(guess).toISOString(), zone) + "Z",
    );
    guess += base - seen;
  }
  if (localTime(new Date(guess).toISOString(), zone) !== local)
    throw Error("This local time does not exist due to daylight saving");
  // Reject ambiguous fall-back times rather than silently picking an occurrence.
  if (
    [-3600000, 3600000].some(
      (d) => localTime(new Date(guess + d).toISOString(), zone) === local,
    )
  )
    throw Error(
      "This time occurs twice due to daylight saving. Choose a time outside the clock change",
    );
  return new Date(guess).toISOString();
}
export function filterSessions(rows, f) {
  return rows.filter(
    (r) =>
      (!f.sport || r.sport === f.sport) &&
      (!f.status || r.status === f.status) &&
      (!f.date || localTime(r.startsAt, r.timezone).slice(0, 10) === f.date) &&
      (!f.suburb ||
        r.venue?.suburb?.toLowerCase().includes(f.suburb.toLowerCase())) &&
      (!f.demo || r.isDemo === true),
  );
}
export function csv(rows, keys) {
  const cell = (v) => {
    let s = Array.isArray(v)
      ? v.join("; ")
      : typeof v === "object" && v !== null
        ? JSON.stringify(v)
        : String(v ?? "");
    if (/^(?:[\t\r]|\s*[=+\-@])/.test(s)) s = "'" + s;
    return '"' + s.replaceAll('"', '""') + '"';
  };
  return [keys, ...rows.map((r) => keys.map((k) => at(r, k)))]
    .map((r) => r.map(cell).join(","))
    .join("\r\n");
}
export function matchUploads(files, venues) {
  const counts = new Map();
  for (const file of files) {
    const code = file.name.replace(/\.[^.]+$/, "").toLowerCase();
    counts.set(code, (counts.get(code) || 0) + 1);
  }
  return files.map((file) => {
    const code = file.name.replace(/\.[^.]+$/, "").toLowerCase(),
      found = venues.filter((v) => v.code?.toLowerCase() === code);
    return {
      file,
      venue: found.length === 1 ? found[0] : null,
      error:
        counts.get(code) > 1
          ? "Duplicate filename code"
          : found.length === 0
            ? "No matching venue code"
            : found.length > 1
              ? "Venue code is ambiguous"
              : !/^image\/(jpeg|png|webp)$/.test(file.type)
                ? "Use JPEG, PNG or WebP"
                : file.size > 20 * 1024 * 1024
                  ? "Maximum source size is 20 MB"
                  : !found[0].state || !found[0].suburb
                    ? "Complete venue state and suburb in the editor first"
                    : "",
    };
  });
}
export function cropRect(width, height, zoom = 1, x = 0.5, y = 0.5) {
  const w = Math.min(width, (height * 16) / 9) / zoom,
    h = (w * 9) / 16;
  return { x: (width - w) * x, y: (height - h) * y, w, h };
}
export function sessionChanges(row) {
  return Object.fromEntries(
    Object.entries(row).filter(([k]) =>
      [
        "name",
        "code",
        "sport",
        "status",
        "registrationStatus",
        "startsAt",
        "endsAt",
        "timezone",
        "capacity",
        "coachUids",
        "venue",
        "geofenceRadiusM",
        "requiredFormIds",
        "notes",
        "photoUrl",
        "isDemo",
        "seedBatch",
        "programId",
      ].includes(k),
    ),
  );
}
