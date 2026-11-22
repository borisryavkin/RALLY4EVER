import { test } from 'node:test';
import assert from 'node:assert/strict';
import XLSX from 'xlsx';
import { parseUniversitySheet } from '../scripts/parse-university-matrix.mjs';

/** Builds a synthetic "working notebook" sheet matching the real
 * per-university sheets' shape: a NOTES: cell, a Facility/Location block,
 * and a Schedule block with real date serials (not JS Date objects --
 * see tests/parse-master-spreadsheet for why). `scheduleDates` are
 * {y,m,d} triples converted to Excel serials via XLSX's own encoder, so
 * the test exercises the exact same timezone-independent decode path the
 * importer uses. */
function buildUniSheet({ notes, venueName, address, scheduleRows }) {
  const aoa = [
    ['UNSW', null, null, null, null, null, null, null, null, 'NOTES: '],
    [null, null, null, null, null, null, null, null, null, notes ?? null],
    ['Facilitiy'],
    ['Location', null, 'Address'],
    [venueName, null, address],
    [],
    ['Schedule'],
    ['Date', 'Day of Week ', 'Time ', 'Location ', 'Coach '],
  ];
  for (const row of scheduleRows) aoa.push([null, row.dayText, row.time, venueName, row.coach]);
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  const dateColLetter = 'A';
  scheduleRows.forEach((row, i) => {
    const excelRow = 8 + i + 1; // 0-based row 8 is the first data row -> 1-based 9
    const serial = XLSX.SSF.parse_date_code === undefined ? null : dateToSerial(row.date);
    ws[`${dateColLetter}${excelRow}`] = { t: 'n', v: serial, w: row.dateDisplay ?? row.date };
  });
  // Recompute sheet range since aoa_to_sheet may not have sized for our
  // post-hoc cell writes beyond the original aoa's column count.
  ws['!ref'] = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: aoa.length - 1, c: 9 } });
  return ws;
}

// Minimal Excel-epoch day-count serial (1899-12-30 base, matching
// XLSX.SSF's own convention) -- good enough for round-tripping through
// XLSX.SSF.parse_date_code in these tests.
function dateToSerial(isoDate) {
  const [y, m, d] = isoDate.split('-').map(Number);
  const epoch = Date.UTC(1899, 11, 30);
  return Math.round((Date.UTC(y, m - 1, d) - epoch) / 86400000);
}

test('reads the NOTES cell, Facility/Location block, and a clean weekly Schedule block', () => {
  const ws = buildUniSheet({
    notes: 'Need to confirm dates and if coaches available',
    venueName: 'UNSW Fitness & Aquatic Centre',
    address: 'Gate 2 B5, High St, Kensington NSW 2052',
    scheduleRows: [
      { date: '2026-02-24', dayText: 'Tuesday', time: '13:00-14:00', coach: 'Louise' },
      { date: '2026-03-03', dayText: 'Tuesday', time: '13:00-14:00', coach: 'Elvis' },
      { date: '2026-03-10', dayText: 'Tuesday', time: '13:00-14:00', coach: null },
    ],
  });
  const record = parseUniversitySheet(ws, 'NSW - UNSW', 'matrix.xlsx');
  assert.equal(record.name, 'Pickleball at UNSW');
  assert.equal(record.state, 'NSW');
  assert.equal(record.sport, 'pickleball');
  assert.equal(record.venueName, 'UNSW Fitness & Aquatic Centre');
  assert.equal(record.address, 'Gate 2 B5, High St, Kensington NSW 2052');
  assert.equal(record.day, 'Tue');
  assert.equal(record.startTime, '13:00');
  assert.equal(record.endTime, '14:00');
  assert.equal(record.frequency, 'Weekly');
  assert.equal(record.operational.notes, 'Need to confirm dates and if coaches available');
  assert.equal(record.operational.coachName, 'Louise'); // mode of Louise/Elvis/null
  assert.equal(record.operational.schedule.length, 3);
});

test('every university-matrix program is imported as a draft (no row-level publish signal exists in this source)', () => {
  const ws = buildUniSheet({
    notes: null, venueName: 'Court', address: 'Somewhere',
    scheduleRows: [{ date: '2026-02-24', dayText: 'Tuesday', time: '13:00-14:00', coach: null }],
  });
  const record = parseUniversitySheet(ws, 'NSW - UNSW', 'matrix.xlsx');
  assert.equal(record.published, false);
});

test('a sheet with no Schedule rows at all (dates "need to confirm") is flagged for review, not invented', () => {
  const ws = buildUniSheet({
    notes: 'Need to confirm dates', venueName: 'UniActive Sports Hall', address: 'Building 13',
    scheduleRows: [],
  });
  const record = parseUniversitySheet(ws, 'University of Wollongong', 'matrix.xlsx');
  assert.equal(record.published, false);
  assert.equal(record.day, null);
  assert.ok(record.review.some((r) => r.reason.includes('no usable Schedule rows')));
});

test('a Day-of-week column that drifts from the real date (Excel fill-down bug) is cross-checked, not trusted', () => {
  // Real bug found in the live spreadsheet: Day of Week cycles through
  // all 7 days even though the dates are a genuine weekly series.
  const ws = buildUniSheet({
    notes: null, venueName: 'UNSW Fitness & Aquatic Centre', address: 'Gate 2 B5',
    scheduleRows: [
      { date: '2026-09-22', dayText: 'Tuesday', time: '13:00-14:00', coach: null }, // 2026-09-22 is a Tuesday
      { date: '2026-09-29', dayText: 'Wednesday', time: '13:00-14:00', coach: null }, // actually also a Tuesday
      { date: '2026-10-06', dayText: 'Thursday', time: '13:00-14:00', coach: null }, // actually also a Tuesday
    ],
  });
  const record = parseUniversitySheet(ws, 'NSW - UNSW', 'matrix.xlsx');
  // The authoritative, date-derived day wins regardless of the free text.
  assert.equal(record.day, 'Tue');
  assert.ok(record.review.some((r) => r.reason.includes('Day of week column disagrees')));
});

test('a Time that varies across the term uses the most common value and is flagged for review, not silently averaged', () => {
  const ws = buildUniSheet({
    notes: null, venueName: 'Court', address: 'Somewhere',
    scheduleRows: [
      { date: '2026-02-24', dayText: 'Tuesday', time: '12:00-13:30', coach: null },
      { date: '2026-03-03', dayText: 'Tuesday', time: '12:00-13:30', coach: null },
      { date: '2026-03-10', dayText: 'Tuesday', time: '15:00-16:00', coach: null },
      { date: '2026-03-17', dayText: 'Tuesday', time: '16:00-17:00', coach: null },
    ],
  });
  const record = parseUniversitySheet(ws, 'NSW - UNSW', 'matrix.xlsx');
  assert.equal(record.startTime, '12:00');
  assert.ok(record.review.some((r) => r.reason.includes('Time varies across the term')));
});

test('non-weekly schedule gaps do not get labelled Weekly', () => {
  const ws = buildUniSheet({
    notes: null, venueName: 'Court', address: 'Somewhere',
    scheduleRows: [
      { date: '2026-02-24', dayText: 'Tuesday', time: '13:00-14:00', coach: null },
      { date: '2026-03-24', dayText: 'Tuesday', time: '13:00-14:00', coach: null },
      { date: '2026-04-21', dayText: 'Tuesday', time: '13:00-14:00', coach: null },
    ],
  });
  const record = parseUniversitySheet(ws, 'NSW - UNSW', 'matrix.xlsx');
  assert.equal(record.frequency, null);
  assert.ok(record.review.some((r) => r.reason.includes('not consistently weekly')));
});
