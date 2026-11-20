import { test } from "node:test";
import assert from "node:assert/strict";
import {
  localTime,
  zonedISO,
  filterSessions,
  csv,
  matchUploads,
  cropRect,
  fields,
  sessionChanges,
} from "../src/helpers.mjs";
test("timezone round-trip uses venue zone, rejects nonexistent/ambiguous times", () => {
  assert.equal(
    zonedISO("2026-11-20T18:30", "Australia/Sydney"),
    "2026-11-20T07:30:00.000Z",
  );
  assert.equal(
    localTime("2026-11-20T07:30Z", "Australia/Sydney"),
    "2026-11-20T18:30",
  );
  assert.throws(() => zonedISO("2026-10-04T02:30", "Australia/Sydney"));
  assert.throws(() => zonedISO("2026-04-05T02:30", "Australia/Sydney"));
});
test("filters use session local date and demo strict flag", () => {
  const r = {
    startsAt: "2026-11-20T23:30Z",
    timezone: "Australia/Sydney",
    sport: "tennis",
    status: "published",
    venue: { suburb: "Rose Bay" },
    isDemo: true,
  };
  assert.equal(
    filterSessions([r], { date: "2026-11-21", suburb: "rose", demo: true })
      .length,
    1,
  );
  assert.equal(filterSessions([r], { date: "2026-11-20" }).length, 0);
  assert.equal(filterSessions([r], { sport: "pickleball" }).length, 0);
});
test("CSV preserves quotes/newlines and neutralizes spreadsheet formulas", () => {
  assert.equal(
    csv([{ name: "=cmd", notes: 'a,"b"\nc' }], ["name", "notes"]),
    '"name","notes"\r\n"\'=cmd","a,""b""\nc"',
  );
});
test("bulk filenames match unique venue codes and reject duplicate or unknown files", () => {
  const files = ["COURT-A.jpg", "missing.jpg"].map((name) => ({
    name,
    type: "image/jpeg",
    size: 10,
  }));
  const v = [{ code: "court-a", state: "NSW", suburb: "Bondi" }];
  assert.equal(matchUploads(files, v)[0].venue, v[0]);
  assert.match(matchUploads(files, v)[1].error, /No matching/);
  assert.match(matchUploads([files[0], files[0]], v)[0].error, /Duplicate/);
});
test("crop stays within image and retains exact 16:9 aspect", () => {
  for (const [w, h] of [
    [4000, 2000],
    [2000, 4000],
  ])
    for (const z of [1, 2, 3]) {
      const c = cropRect(w, h, z, 0.9, 0.1);
      assert.ok(Math.abs(c.w / c.h - 16 / 9) < 1e-12);
      assert.ok(c.x + c.w <= w && c.y + c.h <= h);
    }
});
test("all requested fields visible and derived fields cannot be submitted", () => {
  assert.ok(fields.includes("bookedCount") && fields.includes("venue.lng"));
  assert.deepEqual(
    sessionChanges({
      name: "Tennis",
      bookedCount: 50,
      revision: 1,
      updatedBy: "x",
    }),
    { name: "Tennis" },
  );
});
test('photo order never borrows another venue and resize does not upscale',async()=>{
 const {resolvePhoto,photoDimensions}=await import('../src/helpers.mjs');
 const venues=[{id:'manly',photoUrl:'manly'},{id:'chatswood',photoUrl:'chatswood'}];
 assert.equal(resolvePhoto({photoUrl:'session',venueId:'manly'},venues),'session');
 assert.equal(resolvePhoto({venueId:'manly'},venues),'manly');
 assert.equal(resolvePhoto({venueId:'unknown'},venues),'');
 assert.equal(resolvePhoto({venueId:'manly',photoMode:'none'},venues),'');
 assert.equal(resolvePhoto({venueId:'manly',photoMode:'venue',photoUrl:'old'},venues),'manly');
 assert.deepEqual(photoDimensions(4000,2000),{width:1600,height:800});
 assert.deepEqual(photoDimensions(2000,4000),{width:800,height:1600});
 assert.deepEqual(photoDimensions(320,200),{width:320,height:200});
});
test('admin session dates use readable local timezone formatting',async()=>{
 const {displaySessionTime}=await import('../src/helpers.mjs');
 assert.equal(displaySessionTime('2026-11-19T02:12:33.702Z','Australia/Sydney'),'Thu 19 Nov, 1:12 pm');
});
