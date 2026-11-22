import { localTime, displaySessionTime } from "./helpers.mjs";
export const capacityMessage =
  "Capacity must be a number from 1 to 5000, or leave it blank for unlimited.";
export function capacityValue(value) {
  if (value == null || String(value).trim() === "") return null;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 5000) throw Error(capacityMessage);
  return n;
}
export function venueInputValue(v = {}) {
  const out = { ...v };
  for (const k of ["lat", "lng"])
    out[k] = v[k] == null || String(v[k]).trim() === "" ? null : Number(v[k]);
  return out;
}
export function programInput(p) {
  return {
    name: p.name ?? "",
    sport: p.sport ?? "",
    status: p.status ?? "draft",
    venue: venueInputValue(p.venue),
    timezone: p.timezone ?? "Australia/Sydney",
    scheduleText: p.scheduleText ?? "",
    coachUids: Array.isArray(p.coachUids) ? p.coachUids : [],
    coachNames: Array.isArray(p.coachNames) ? p.coachNames : [],
    notes: p.notes ?? "",
    photoUrl: p.photoUrl ?? "",
    capacity: capacityValue(p.capacity),
    registrationStatus: p.registrationStatus || "open",
  };
}
export function programErrors(p) {
  const e = {};
  if (!p.name?.trim()) e.name = "Enter a program name.";
  if (!["tennis", "pickleball"].includes(p.sport))
    e.sport = "Choose Tennis or Pickleball.";
  if (!p.scheduleText?.trim()) e.scheduleText = "Enter the program schedule.";
  try {
    capacityValue(p.capacity);
  } catch {
    e.capacity = capacityMessage;
  }
  if (!p.venue?.name?.trim()) e["venue.name"] = "Enter a venue name.";
  if (!p.venue?.suburb?.trim()) e["venue.suburb"] = "Enter a suburb.";
  if (
    !["ACT", "NSW", "NT", "QLD", "SA", "TAS", "VIC", "WA"].includes(
      p.venue?.state,
    )
  )
    e["venue.state"] = "Choose a state.";
  const v = venueInputValue(p.venue);
  if (
    (v.lat == null) !== (v.lng == null) ||
    (v.lat !== null && (!Number.isFinite(v.lat) || Math.abs(v.lat) > 90)) ||
    (v.lng !== null && (!Number.isFinite(v.lng) || Math.abs(v.lng) > 180))
  )
    e["venue.lat"] =
      "Enter both valid latitude and longitude, or leave both blank.";
  if (
    p.photoUrl &&
    !/^https:\/\/\S+$/.test(p.photoUrl) &&
    !/^gs:\/\/rally4ever-3adaf\.firebasestorage\.app\/venues\//.test(p.photoUrl)
  )
    e.photoUrl = "Use an HTTPS photo URL or an uploaded venue photo.";
  return e;
}
export function adminError(e) {
  const reason = e?.details?.reason ?? e?.reason;
  if (reason === "invalid-capacity") return capacityMessage;
  if (reason === "program-has-attendance")
    return "This program has registrations or attendance history. Archive it instead.";
  if (String(e?.code ?? "").includes("not-found"))
    return "This admin feature is not available yet. The corresponding callable must be deployed before this site.";
  return (e?.message ?? "We could not save these changes. Please try again.")
    .replace(/\s*\[\d{3}\]/g, "")
    .replace(/\s*\([a-z]+(?:-[a-z]+)+\)/g, "")
    .replace(/^Firebase:\s*/, "")
    .trim();
}
export const errorField = (e) =>
  ({
    "invalid-capacity": "capacity",
    "invalid-photo": "photoUrl",
    "invalid-location": "venue.lat",
    "invalid-coach": "coachUids",
    "invalid-timezone": "timezone",
  })[e?.details?.reason];
export function venueCode(name, state, venues = [], ownId) {
  const base = `${
    (name ?? "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 110)
      .replace(/-$/, "") || "venue"
  }-${(state ?? "").toLowerCase()}`;
  let result = base,
    i = 2;
  while (venues.some((v) => v.id !== ownId && v.code === result))
    result = base + "-" + i++;
  return result;
}
export function dateRange(mode = "nearby", now = new Date()) {
  const date = new Date(
    localTime(now.toISOString(), "Australia/Sydney").slice(0, 10) +
      "T12:00:00Z",
  );
  const iso = (d) => d.toISOString().slice(0, 10),
    shift = (n) => {
      const d = new Date(date);
      d.setUTCDate(d.getUTCDate() + n);
      return iso(d);
    };
  if (mode === "all") return { from: "", to: "" };
  if (mode === "today") return { from: iso(date), to: iso(date) };
  if (mode === "week") {
    const offset = (date.getUTCDay() + 6) % 7;
    return { from: shift(-offset), to: shift(6 - offset) };
  }
  return { from: shift(-14), to: shift(14) };
}
export function attendanceSessions(events, programs, f, now = Date.now()) {
  const names = new Map(programs.map((p) => [p.id, p.name]));
  const term = (f.search ?? "").trim().toLowerCase();
  return events
    .filter(
      (e) =>
        !e.deletedAt &&
        !e.hiddenAt &&
        e.status !== "deleted" &&
        (!f.program || e.programId === f.program) &&
        (!f.sport || e.sport === f.sport) &&
        (!f.from || localTime(e.startsAt, e.timezone).slice(0, 10) >= f.from) &&
        (!f.to || localTime(e.startsAt, e.timezone).slice(0, 10) <= f.to) &&
        `${names.get(e.programId) ?? e.name} ${e.name} ${e.venue?.name ?? ""} ${e.venue?.suburb ?? ""} ${localTime(e.startsAt, e.timezone)} ${displaySessionTime(e.startsAt, e.timezone)}`
          .toLowerCase()
          .includes(term),
    )
    .sort(
      (a, b) =>
        Math.abs(Date.parse(a.startsAt) - now) -
          Math.abs(Date.parse(b.startsAt) - now) || a.id.localeCompare(b.id),
    );
}
export function programFilters(search) {
  const q = new URLSearchParams(search);
  return {
    search: q.get("programSearch") ?? "",
    status: q.get("programStatus") ?? "",
    sport: q.get("programSport") ?? "",
    deleted: q.get("programDeleted") === "1",
  };
}
export function programsFiltered(programs, f) {
  return programs.filter(
    (p) =>
      (f.deleted || !p.deletedAt) &&
      (!f.status || p.status === f.status) &&
      (!f.sport || p.sport === f.sport) &&
      `${p.name} ${p.venue?.name ?? ""} ${p.venue?.suburb ?? ""}`
        .toLowerCase()
        .includes(f.search.toLowerCase()),
  );
}
export function setProgramQuery(f) {
  const q = new URLSearchParams(location.search);
  q.set("page", "Programs");
  for (const [k, v] of Object.entries({
    programSearch: f.search,
    programStatus: f.status,
    programSport: f.sport,
    programDeleted: f.deleted ? "1" : "",
  })) {
    if (v) q.set(k, v);
    else q.delete(k);
  }
  history.replaceState(null, "", location.pathname + "?" + q);
}
export function downloadFile(name, body) {
  const url = URL.createObjectURL(
    new Blob([body], { type: "text/csv;charset=utf-8" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
