import XLSX from 'xlsx';
import { parseTimeRange, weekdayFromDate, isoFromYMD } from './import-lib.mjs';

// Sheet name -> {state, universityName}. The in-cell title on two sheets
// (Griffith, Deakin) is a stale "University of Wollongong" copy-paste left
// over from a template -- the sheet name is used instead; see
// docs/import/programs-mapping.md §4.
export const UNIVERSITY_SHEETS = {
  'NSW - UNSW': { state: 'NSW', universityName: 'UNSW' },
  'NSW - Macquarie University': { state: 'NSW', universityName: 'Macquarie University' },
  'NSW - University of Sydney': { state: 'NSW', universityName: 'University of Sydney' },
  'NSW - Western Sydney University': { state: 'NSW', universityName: 'Western Sydney University' },
  'University of Wollongong': { state: 'NSW', universityName: 'University of Wollongong' },
  'QSL - Griffith University': { state: 'QLD', universityName: 'Griffith University' },
  'VIC - Deakin University': { state: 'VIC', universityName: 'Deakin University' },
};

function isFormattedNumber(cell) {
  return !!cell && cell.t === 'n' && cell.w !== undefined && cell.w !== String(cell.v);
}

function findCellRow(aoa, predicate) {
  for (let r = 0; r < aoa.length; r++) {
    if (predicate(aoa[r])) return r;
  }
  return -1;
}

function mode(values) {
  const counts = new Map();
  for (const v of values) {
    if (v == null) continue;
    counts.set(v, (counts.get(v) ?? 0) + 1);
  }
  let best = null, bestCount = 0;
  for (const [v, c] of counts) {
    if (c > bestCount) { best = v; bestCount = c; }
  }
  return { value: best, count: bestCount, total: values.filter((v) => v != null).length };
}

/** Parses one per-university "working notebook" sheet. Only three parts
 * are read (see docs/import/programs-mapping.md §4): the single "NOTES:"
 * cell, the Facility/Location block (venue name + address), and the
 * tabular Schedule block (Date | Day of Week | Time | Location | Coach).
 * Everything else (contacts, pricing, freeform scratch notes below the
 * Schedule block) is deliberately not parsed. */
export function parseUniversitySheet(ws, sheetName, fileName) {
  const meta = UNIVERSITY_SHEETS[sheetName];
  const aoa = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null });
  const review = [];

  const notesLabelRow = findCellRow(aoa, (row) =>
    row.some((v) => typeof v === 'string' && v.trim().toLowerCase() === 'notes:'));
  let notes = null;
  if (notesLabelRow !== -1) {
    const col = aoa[notesLabelRow].findIndex((v) => typeof v === 'string' && v.trim().toLowerCase() === 'notes:');
    notes = aoa[notesLabelRow + 1]?.[col] ?? null;
  }

  const facilityHeaderRow = findCellRow(aoa, (row) =>
    row.some((v) => typeof v === 'string' && v.trim().toLowerCase() === 'location') &&
    row.some((v) => typeof v === 'string' && v.trim().toLowerCase() === 'address'));
  let venueName = '', address = '';
  if (facilityHeaderRow !== -1) {
    const locCol = aoa[facilityHeaderRow].findIndex((v) => typeof v === 'string' && v.trim().toLowerCase() === 'location');
    const addrCol = aoa[facilityHeaderRow].findIndex((v) => typeof v === 'string' && v.trim().toLowerCase() === 'address');
    const dataRow = aoa[facilityHeaderRow + 1] ?? [];
    venueName = (dataRow[locCol] ?? '').toString().trim();
    address = (dataRow[addrCol] ?? '').toString().trim();
  } else {
    review.push({ reason: 'no Facility/Location block found' });
  }

  const scheduleHeaderRow = findCellRow(aoa, (row) =>
    row.some((v) => typeof v === 'string' && v.trim().toLowerCase() === 'date') &&
    row.some((v) => typeof v === 'string' && v.trim().toLowerCase().startsWith('day of week')));
  const scheduleRows = [];
  if (scheduleHeaderRow !== -1) {
    const header = aoa[scheduleHeaderRow];
    const dateCol = header.findIndex((v) => typeof v === 'string' && v.trim().toLowerCase() === 'date');
    const dayCol = header.findIndex((v) => typeof v === 'string' && v.trim().toLowerCase().startsWith('day of week'));
    const timeCol = header.findIndex((v) => typeof v === 'string' && v.trim().toLowerCase().startsWith('time'));
    const coachCol = header.findIndex((v) => typeof v === 'string' && v.trim().toLowerCase().startsWith('coach'));
    let consecutiveBlanks = 0;
    for (let r = scheduleHeaderRow + 1; r < aoa.length; r++) {
      const row = aoa[r] ?? [];
      const dateCell = cellAtAoa(ws, r, dateCol);
      if (!dateCell || dateCell.v == null) {
        consecutiveBlanks++;
        if (consecutiveBlanks > 3) break; // past the schedule block entirely
        continue;
      }
      consecutiveBlanks = 0;
      if (!isFormattedNumber(dateCell)) continue; // not a real date cell; stop trusting this as schedule data
      const { y, m: mo, d } = XLSX.SSF.parse_date_code(dateCell.v);
      const iso = isoFromYMD(y, mo, d);
      if (!iso) continue;
      scheduleRows.push({
        date: iso,
        dateWeekday: weekdayFromDate(new Date(`${iso}T00:00:00Z`)),
        dayText: row[dayCol] != null ? String(row[dayCol]).trim() : null,
        time: row[timeCol] != null ? String(row[timeCol]).trim() : null,
        coach: row[coachCol] != null ? String(row[coachCol]).trim() : null,
      });
    }
  }

  // Unlike the master spreadsheet (an explicit Status column), the
  // university matrix has no row-level "this is live" signal at all --
  // every university program from this source is imported as a draft for
  // admin review, regardless of how complete its schedule data looks.
  // See docs/import/programs-mapping.md §4.
  if (scheduleRows.length === 0) {
    return {
      sheetName, name: `Pickleball at ${meta.universityName}`, state: meta.state, sport: 'pickleball',
      // No distinct suburb is available from this source (only a venue
      // name + street address) -- left blank rather than reusing the
      // program's own name, which is a display label ("Pickleball at
      // ..."), not a place.
      published: false, venueName, address, suburb: '', day: null, startTime: null, endTime: null, frequency: null,
      review: [...review, { reason: 'no usable Schedule rows (dates marked "need to confirm" or missing)' }],
      operational: { notes, coachName: null, schedule: [] },
      importSource: { file: fileName, sheet: sheetName, row: null },
    };
  }

  const mismatches = scheduleRows.filter((r) => r.dayText && r.dateWeekday && !r.dayText.toLowerCase().startsWith(r.dateWeekday.toLowerCase()));
  if (scheduleRows.length > 0 && mismatches.length / scheduleRows.length > 0.2) {
    review.push({
      reason: `Day of week column disagrees with the Date column for ${mismatches.length}/${scheduleRows.length} rows (using the date-derived weekday, not the free-typed column)`,
    });
  }
  const dayMode = mode(scheduleRows.map((r) => r.dateWeekday));
  const timeMode = mode(scheduleRows.map((r) => r.time));
  if (timeMode.total > 0 && timeMode.count / timeMode.total < 0.6) {
    review.push({ reason: `Time varies across the term (most common "${timeMode.value}" covers only ${timeMode.count}/${timeMode.total} sessions) -- see admin schedule for the full list` });
  }
  const parsedTime = timeMode.value ? parseTimeRange(timeMode.value) : { startTime: null, endTime: null, reason: 'empty' };
  if (timeMode.value && !parsedTime.startTime) {
    review.push({ reason: `could not parse representative Time value "${timeMode.value}" (${parsedTime.reason})` });
  }

  // Weekly if consecutive schedule dates are consistently ~7 days apart.
  const gaps = [];
  for (let i = 1; i < scheduleRows.length; i++) {
    gaps.push((Date.parse(scheduleRows[i].date) - Date.parse(scheduleRows[i - 1].date)) / 86400000);
  }
  const weeklyGaps = gaps.filter((g) => g === 7).length;
  const frequency = gaps.length > 0 && weeklyGaps / gaps.length >= 0.6 ? 'Weekly' : null;
  if (!frequency && gaps.length > 0) review.push({ reason: 'schedule dates are not consistently weekly; frequency left for admin to confirm' });

  const coachMode = mode(scheduleRows.map((r) => r.coach));

  return {
    sheetName, name: `Pickleball at ${meta.universityName}`, state: meta.state, sport: 'pickleball',
    published: false, venueName, address, suburb: '',
    day: dayMode.value, startTime: parsedTime.startTime, endTime: parsedTime.endTime, frequency,
    review,
    operational: { notes, coachName: coachMode.value ?? null, schedule: scheduleRows },
    importSource: { file: fileName, sheet: sheetName, row: scheduleHeaderRow + 1 },
  };
}

function cellAtAoa(ws, row0, col0) {
  return ws[XLSX.utils.encode_cell({ r: row0, c: col0 })];
}

export function parseUniversityMatrix(filePath) {
  const fileName = filePath.split('/').pop();
  const wb = XLSX.readFile(filePath, { cellDates: false });
  const records = [];
  for (const sheetName of Object.keys(UNIVERSITY_SHEETS)) {
    const ws = wb.Sheets[sheetName];
    if (!ws) {
      records.push({ sheetName, skip: true, review: [{ reason: 'sheet not found' }] });
      continue;
    }
    records.push(parseUniversitySheet(ws, sheetName, fileName));
  }
  return records;
}
