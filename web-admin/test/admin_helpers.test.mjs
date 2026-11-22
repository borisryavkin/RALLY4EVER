import { test } from "node:test";
import assert from "node:assert/strict";
import {
  capacityValue,
  programInput,
  programErrors,
  adminError,
  venueCode,
  dateRange,
  attendanceSessions,
  programFilters,
  programsFiltered,
} from "../src/admin_helpers.mjs";
const p = {
  name: "Pickleball at Ultimo",
  sport: "pickleball",
  scheduleText: "Thursday 11:30",
  venue: {
    name: "Ultimo",
    suburb: "Ultimo",
    state: "NSW",
    lat: null,
    lng: null,
  },
  capacity: null,
};
test("blank and null capacity stay unlimited through complete payload normalization", () => {
  for (const value of [null, undefined, "", "  "]) {
    assert.equal(capacityValue(value), null);
    assert.equal(programInput({ ...p, capacity: value }).capacity, null);
  }
  assert.equal(programInput({ ...p, capacity: "20" }).capacity, 20);
});
test("invalid capacity is blocked rather than serialized as unlimited", () => {
  for (const value of [0, -1, 5001, "abc", 1.5, NaN, Infinity])
    assert.throws(() => capacityValue(value));
  assert.ok(programErrors({ ...p, capacity: "5001" }).capacity);
});
test("optional fields and coordinates use the server contract, with explicit sport", () => {
  const value = programInput({
    ...p,
    notes: null,
    photoUrl: null,
    coachUids: "",
    coachNames: null,
    registrationStatus: "",
    venue: { ...p.venue, lat: "", lng: "" },
  });
  assert.equal(value.notes, "");
  assert.equal(value.photoUrl, "");
  assert.equal(value.venue.lat, null);
  assert.deepEqual(value.coachUids, []);
  assert.equal(value.registrationStatus, "open");
  assert.ok(programErrors({ ...p, sport: "" }).sport);
  assert.equal(programInput({ ...p, sport: "" }).sport, "");
});
test("human admin errors never include HTTP or machine reason suffixes", () => {
  assert.match(
    adminError({
      details: { reason: "invalid-capacity" },
      message: "Bad [400] (invalid-capacity)",
    }),
    /leave it blank/,
  );
  assert.equal(
    adminError({ message: "Please retry [400] (stale-program)" }),
    "Please retry",
  );
});
test("venue code derives from name/state with deterministic collisions", () => {
  assert.equal(
    venueCode("Armidale Tennis Centre", "NSW"),
    "armidale-tennis-centre-nsw",
  );
  assert.equal(
    venueCode("Armidale Tennis Centre", "NSW", [
      { id: "one", code: "armidale-tennis-centre-nsw" },
      { id: "two", code: "armidale-tennis-centre-nsw-2" },
    ]),
    "armidale-tennis-centre-nsw-3",
  );
});
test("attendance default, today, week and all-date ranges are explicit", () => {
  const now = new Date("2026-11-20T02:00:00Z");
  assert.deepEqual(dateRange("nearby", now), {
    from: "2026-11-06",
    to: "2026-12-04",
  });
  assert.deepEqual(dateRange("today", now), {
    from: "2026-11-20",
    to: "2026-11-20",
  });
  assert.deepEqual(dateRange("week", now), {
    from: "2026-11-16",
    to: "2026-11-22",
  });
  assert.deepEqual(dateRange("all", now), { from: "", to: "" });
});
test("attendance search combines program sport venue/date and sorts nearest, excluding tombstones", () => {
  const now = Date.parse("2026-11-20T02:00Z"),
    base = {
      timezone: "Australia/Sydney",
      name: "Pickleball",
      sport: "pickleball",
      programId: "p",
      venue: { name: "Ultimo Community Centre", suburb: "Ultimo" },
    };
  const rows = [
    { ...base, id: "later", startsAt: "2026-11-25T02:00Z" },
    { ...base, id: "near", startsAt: "2026-11-20T03:00Z" },
    { ...base, id: "deleted", startsAt: "2026-11-20T02:00Z", deletedAt: "now" },
  ];
  assert.deepEqual(
    attendanceSessions(
      rows,
      [{ id: "p", name: "Pickleball program" }],
      {
        search: "ultimo",
        sport: "pickleball",
        program: "p",
        from: "2026-11-19",
        to: "2026-11-26",
      },
      now,
    ).map((r) => r.id),
    ["near", "later"],
  );
  assert.equal(
    attendanceSessions(rows, [], { search: "2026-11-25" }, now).length,
    1,
  );
});
test("program sport search status and deleted filters combine and round trip URL", () => {
  const f = programFilters(
    "?programSearch=Ultimo&programSport=pickleball&programStatus=active&programDeleted=1",
  );
  const rows = [
    { ...p, status: "active" },
    { ...p, sport: "tennis", status: "active" },
    { ...p, status: "draft" },
  ];
  assert.equal(programsFiltered(rows, f).length, 1);
  assert.equal(f.deleted, true);
});

test('international program venue accepts blank region and preserves country', () => {
  const international = { ...p, venue: { ...p.venue, country: 'United Kingdom', state: '', suburb: 'London' } };
  assert.equal(programErrors(international)['venue.state'], undefined);
  assert.equal(programInput(international).venue.country, 'United Kingdom');
  assert.equal(programInput(international).venue.state, '');
  assert.equal(programErrors({ ...international, venue: { ...international.venue, country: 'Australia' } })['venue.state'], 'Choose a state.');
});
