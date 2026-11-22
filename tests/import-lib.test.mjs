import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeVenueName,
  slug,
  programId,
  venueId,
  importKey,
  parseDay,
  weekdayFromDate,
  parseTimeRange,
  normalizeFrequency,
  isoFromYMD,
  parseStartDateText,
} from '../scripts/import-lib.mjs';

test('normalizeVenueName lowercases, trims, collapses whitespace, strips punctuation and filler words', () => {
  assert.equal(normalizeVenueName('  Armidale   Tennis Centre '), 'armidale');
  assert.equal(normalizeVenueName('Western Suburbs Lawn Tennis Club'), 'western suburbs lawn');
  assert.equal(normalizeVenueName('Bondi Beach Tennis Centre'), 'bondi beach');
  assert.equal(normalizeVenueName('St. Kilda, PCYC!'), 'st kilda pcyc');
  assert.equal(normalizeVenueName(null), '');
  // Same venue, two spellings, normalizes identically.
  assert.equal(
    normalizeVenueName('Primrose Park Tennis Centre'),
    normalizeVenueName('PRIMROSE   PARK   tennis centre.'),
  );
});

test('slug produces a lowercase hyphenated id-safe string', () => {
  assert.equal(slug('Albury / Wodonga'), 'albury-wodonga');
  assert.equal(slug('  Bondi Junction!!  '), 'bondi-junction');
  assert.match(slug('Café René'), /^[a-z0-9-]+$/);
});

test('programId reuses the existing real-project convention (<state>-<sport>-<slug>)', () => {
  assert.equal(programId('NSW', 'tennis', 'Armidale'), 'nsw-tennis-armidale');
  assert.equal(
    programId('VIC', 'pickleball', 'Albury / Wodonga'),
    'vic-pickleball-albury-wodonga',
  );
  assert.equal(programId('nsw', 'tennis', 'Armidale'), 'nsw-tennis-armidale');
});

test('venueId is deterministic for a new venue and reruns identically', () => {
  const id = venueId('Armidale Tennis Centre', 'NSW');
  assert.equal(id, 'armidale-tennis-centre-nsw');
  assert.equal(venueId('Armidale Tennis Centre', 'NSW'), id);
});

test('importKey is a stable deterministic hash of its parts', () => {
  const a = importKey(['file.xlsx', 'Sheet1', 'Armidale', 'Sun', '14:00']);
  const b = importKey(['file.xlsx', 'Sheet1', 'Armidale', 'Sun', '14:00']);
  const c = importKey(['file.xlsx', 'Sheet1', 'Armidale', 'Mon', '14:00']);
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^[a-f0-9]{64}$/);
});

test('parseDay maps every spreadsheet day abbreviation, rejects garbage and multi-day text', () => {
  const cases = {
    Sun: 'Sun', Mon: 'Mon', Tue: 'Tue', Tues: 'Tue', tueaday: 'Tue',
    Wed: 'Wed', Thu: 'Thu', Thur: 'Thu', Thurs: 'Thu', Fri: 'Fri', Sat: 'Sat',
    Sunday: 'Sun', monday: 'Mon', THURSDAY: 'Thu',
  };
  for (const [raw, expected] of Object.entries(cases)) {
    assert.equal(parseDay(raw), expected, raw);
  }
  assert.equal(parseDay('??'), null);
  assert.equal(parseDay('Tuesday & Thursday'), null);
  assert.equal(parseDay(null), null);
  assert.equal(parseDay(''), null);
});

test('weekdayFromDate computes the authoritative day from a real calendar date', () => {
  // 2026-09-22 is a Tuesday (UTC midnight, matching how spreadsheet dates
  // are read) -- used to cross-check a free-typed Day-of-week column that
  // can drift (observed in the real spreadsheet: an Excel fill-down bug).
  assert.equal(weekdayFromDate(new Date('2026-09-22T00:00:00Z')), 'Tue');
  assert.equal(weekdayFromDate(new Date('2026-09-23T00:00:00Z')), 'Wed');
  assert.equal(weekdayFromDate(new Date('invalid')), null);
  assert.equal(weekdayFromDate('2026-09-22'), null);
});

test('parseTimeRange parses every example from the task spec', () => {
  assert.deepEqual(parseTimeRange('2-3pm'), { startTime: '14:00', endTime: '15:00', reason: null });
  assert.deepEqual(parseTimeRange('5.30-6.30pm'), { startTime: '17:30', endTime: '18:30', reason: null });
  assert.deepEqual(parseTimeRange('11am-12pm'), { startTime: '11:00', endTime: '12:00', reason: null });
  assert.deepEqual(parseTimeRange('10-11.30am'), { startTime: '10:00', endTime: '11:30', reason: null });
  assert.deepEqual(parseTimeRange('11-12pm'), { startTime: '11:00', endTime: '12:00', reason: null });
});

test('parseTimeRange handles real spreadsheet variants (colon, spaced AM/PM, no-space ranges)', () => {
  assert.deepEqual(parseTimeRange('9-10:30'), { startTime: null, endTime: null, reason: 'no-am-pm' });
  assert.deepEqual(parseTimeRange('1:00-2:30'), { startTime: null, endTime: null, reason: 'no-am-pm' });
  assert.deepEqual(parseTimeRange('12:30 PM - 2:00 PM'), { startTime: '12:30', endTime: '14:00', reason: null });
  assert.deepEqual(parseTimeRange('6-7pm'), { startTime: '18:00', endTime: '19:00', reason: null });
});

test('parseTimeRange never guesses: no am/pm anywhere, or non-time text, both come back unparsed', () => {
  assert.equal(parseTimeRange('10.30-11.30').startTime, null);
  assert.equal(parseTimeRange('10.30-11.30').reason, 'no-am-pm');
  assert.equal(parseTimeRange('after school').reason, 'non-time-text');
  assert.equal(parseTimeRange('To be advised').reason, 'non-time-text');
  assert.equal(parseTimeRange(null).reason, 'empty');
});

test('isoFromYMD builds a date from already-decoded integer parts, timezone-independent', () => {
  // The exact case that motivated this: xlsx's own cellDates:true
  // conversion shifts by a day depending on the machine's local
  // timezone, but XLSX.SSF.parse_date_code's {y,m,d} does not -- so
  // date construction here must never round-trip through a JS Date in a
  // way that re-introduces that shift.
  assert.equal(isoFromYMD(2023, 11, 12), '2023-11-12');
  assert.equal(isoFromYMD(2025, 2, 21), '2025-02-21');
  assert.equal(isoFromYMD(2025, 13, 1), null); // invalid month
  assert.equal(isoFromYMD(2025, 2, 30), null); // invalid day-of-month
  assert.equal(isoFromYMD(null, 1, 1), null);
});

test('normalizeFrequency maps the known single-word values, keeps descriptive text as-is', () => {
  assert.equal(normalizeFrequency('Weekly'), 'Weekly');
  assert.equal(normalizeFrequency('monthly'), 'Monthly');
  assert.equal(normalizeFrequency('FORTNIGHTLY'), 'Fortnightly');
  assert.equal(normalizeFrequency('1st Tuesday of the month'), '1st Tuesday of the month');
  assert.equal(normalizeFrequency(null), null);
});

test('parseStartDateText accepts an unambiguous DD/MM/YYYY string, never guesses at the rest', () => {
  assert.equal(parseStartDateText('21/02/2025'), '2025-02-21');
  assert.equal(parseStartDateText('26/05/2025'), '2025-05-26');
  // Corrupted/unparseable examples straight from the real spreadsheet.
  assert.equal(parseStartDateText('2021'), null);
  assert.equal(parseStartDateText('2021.0'), null);
  assert.equal(parseStartDateText('TBA'), null);
  assert.equal(parseStartDateText('7/1072025'), null);
  assert.equal(parseStartDateText(null), null);
  assert.equal(parseStartDateText(''), null);
});
