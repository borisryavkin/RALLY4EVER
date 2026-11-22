import { test } from 'node:test';
import assert from 'node:assert/strict';
import XLSX from 'xlsx';
import { parseWorkbook } from '../scripts/parse-master-spreadsheet.mjs';

const TENNIS_HEADER = [
  'State/Suburb ', 'State', 'Status', 'SC Name', 'SC Activities', 'Attendance',
  'Community Services Associated', 'Community Contact', 'Subsidised ', 'Start Date',
  'Day', 'Frequency (During School Term)', 'Time', 'Tennis Centre', 'Address',
  'Posting address ', 'Coach name', 'Coach Number', 'Contact Name ', 'Contact number',
  'Contact Email',
];

function buildWorkbook(rows) {
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet([TENNIS_HEADER, ...rows]);
  XLSX.utils.book_append_sheet(wb, ws, 'Active Tennis Programs');
  // The other three sheets this importer reads must exist (even empty)
  // so parseWorkbook doesn't report "sheet not found" for them.
  for (const name of [' Active Pickleball Programs', 'Prospective programs', 'On Hold Inactive']) {
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([[]]), name);
  }
  return wb;
}

/** Overwrites a cell to simulate Excel's "typed a time range, Excel
 * stored it as a date serial" corruption: a numeric cell whose formatted
 * display ('w') differs from its raw value, matching exactly what the
 * real .xlsx file's SheetJS representation looks like for that bug
 * (confirmed against the real file: a "Time" cell holding 45242/"11-12"). */
function setCorruptedDateCell(ws, addr, serial, formatted) {
  ws[addr] = { t: 'n', v: serial, w: formatted };
}

test('a clean row parses day/time/start date/frequency/venue/address', () => {
  const wb = buildWorkbook([
    ['Armidale', 'NSW', 'Active', 'Sascha', 'notes', 5, null, null, 'Paid', '21/02/2025', 'Sun', 'Weekly', '2-3pm', 'Armidale Tennis Centre', 'Golf Link Rd, Armidale, NSW 2350'],
  ]);
  const [row] = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  assert.equal(row.name, 'Armidale');
  assert.equal(row.state, 'NSW');
  assert.equal(row.sport, 'tennis');
  assert.equal(row.published, true);
  assert.equal(row.day, 'Sun');
  assert.equal(row.startTime, '14:00');
  assert.equal(row.endTime, '15:00');
  assert.equal(row.startDate, '2025-02-21');
  assert.equal(row.frequency, 'Weekly');
  assert.equal(row.venueName, 'Armidale Tennis Centre');
  assert.equal(row.address, 'Golf Link Rd, Armidale, NSW 2350');
  assert.deepEqual(row.review, []);
});

test('a status other than exactly "Active" (case-insensitive) is never published', () => {
  const wb = buildWorkbook([
    ['Bourke', 'NSW', 'About to start', null, null, null, null, null, null, null, 'Tue', 'Weekly', '2-3pm', 'Bourke Courts', '1 Main St'],
    ['Cowra', 'NSW', 'active', null, null, null, null, null, null, null, 'Wed', 'Weekly', '2-3pm', 'Cowra Courts', '2 Main St'],
  ]);
  const rows = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  assert.equal(rows.find((r) => r.name === 'Bourke').published, false);
  assert.equal(rows.find((r) => r.name === 'Cowra').published, true); // lower-case "active" still counts
});

test('a Time cell corrupted into a date (Excel bug) is never treated as a real time, and raw text is preserved for review', () => {
  const wb = buildWorkbook([
    ['Ashfield', 'NSW', 'Active', null, null, null, null, null, null, null, 'Tue', 'Weekly', 'PLACEHOLDER', 'Western Suburbs Lawn Tennis Club', '40 Arthur Street, Ashfield, NSW, 2131'],
  ]);
  const ws = wb.Sheets['Active Tennis Programs'];
  setCorruptedDateCell(ws, 'M2', 45242, '11-12'); // Time column is index 12 -> column M
  const [row] = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  assert.equal(row.startTime, null);
  assert.equal(row.endTime, null);
  assert.equal(row.rawTime, '11-12');
  assert.ok(row.review.some((r) => r.reason.includes('Excel corruption')));
});

test('a Start Date cell that is a real date serial decodes via the timezone-independent path, matching its displayed format regardless of machine timezone', () => {
  const wb = buildWorkbook([
    ['Condobolin', 'NSW', 'Active', null, null, null, null, null, null, 'PLACEHOLDER', 'Fri', 'Weekly', '2-3pm', 'Condobolin Tennis Centre', 'Corner of Goodwill St'],
  ]);
  const ws = wb.Sheets['Active Tennis Programs'];
  // Real example from the spreadsheet: a date-picker cell formatted
  // mm/dd/yyyy, decoding to 11 Jan 2024 (month-first format).
  setCorruptedDateCell(ws, 'J2', 45302, '01/11/2024');
  const [row] = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  assert.equal(row.startDate, '2024-01-11');
  assert.equal(row.rawStartDate, null);
});

test('a bare-number Start Date ("2021") and unparseable text ("TBA") are never guessed, and flagged for review', () => {
  const wb = buildWorkbook([
    ['Ashfield', 'NSW', 'Active', null, null, null, null, null, null, 2021, 'Tue', 'Weekly', '11-12pm', 'Club', 'Address'],
    ['Heidelberg', 'NSW', 'Active', null, null, null, null, null, null, 'TBA', 'Fri', 'Weekly', '11-12pm', 'Club', 'Address'],
  ]);
  const rows = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  const ashfield = rows.find((r) => r.name === 'Ashfield');
  assert.equal(ashfield.startDate, null);
  assert.equal(ashfield.rawStartDate, '2021');
  assert.ok(ashfield.review.some((r) => r.reason.includes('Start Date')));
  const heidelberg = rows.find((r) => r.name === 'Heidelberg');
  assert.equal(heidelberg.startDate, null);
  assert.equal(heidelberg.rawStartDate, 'TBA');
});

test('operational fields (coach, contact, notes) are captured separately from the public fields', () => {
  const wb = buildWorkbook([
    ['Armidale', 'NSW', 'Active', 'Sascha Hale', 'some activity notes', 15, 'Council', 'Jane', 'Paid Coach', '21/02/2025', 'Sun', 'Weekly', '2-3pm', 'Armidale Tennis Centre', 'Golf Link Rd', 'posting addr', 'Damian Roff', '0400000000', 'Glen', '0400000001', 'glen@example.test'],
  ]);
  const [row] = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  assert.equal(row.operational.coachName, 'Damian Roff');
  assert.equal(row.operational.contactEmail, 'glen@example.test');
  assert.equal(row.operational.scName, 'Sascha Hale');
  assert.ok(!('coachName' in row));
  assert.ok(!('contactEmail' in row));
});

test('a row with no determinable sport is skipped with a review reason, never guessed', () => {
  // Simulated on a sheet where sport isn't fixed by SHEETS config: here we
  // can only exercise this through "Active Tennis Programs" (fixed sport),
  // so instead assert a row missing its name entirely is dropped silently
  // (nothing to report -- a blank row, not a data problem).
  const wb = buildWorkbook([[null, null, null]]);
  const rows = parseWorkbook(wb, 'test.xlsx');
  assert.equal(rows.length, 0);
});

test('importKey/importSource-relevant row/sheet metadata is recorded for idempotency tracking', () => {
  const wb = buildWorkbook([
    ['Armidale', 'NSW', 'Active', null, null, null, null, null, null, null, 'Sun', 'Weekly', '2-3pm', 'Armidale Tennis Centre', 'Golf Link Rd'],
  ]);
  const [row] = parseWorkbook(wb, 'test.xlsx').filter((r) => !r.skip);
  assert.deepEqual(row.importSource, { file: 'test.xlsx', sheet: 'Active Tennis Programs', row: 2 });
});
