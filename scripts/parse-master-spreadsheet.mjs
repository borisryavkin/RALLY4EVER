import XLSX from 'xlsx';
import {
  parseDay,
  parseTimeRange,
  parseStartDateText,
  isoFromYMD,
  normalizeFrequency,
} from './import-lib.mjs';

const SHEETS = {
  'Active Tennis Programs': { sport: 'tennis' },
  ' Active Pickleball Programs': { sport: 'pickleball' },
  'Prospective programs': { sport: null }, // inferred per-row, see below
  'On Hold Inactive': { sport: null },
};

// Column name -> canonical field, per sheet (matches the real headers
// confirmed in docs/import/programs-mapping.md -- not assumed).
const COLUMNS = {
  'Active Tennis Programs': {
    locationName: 'State/Suburb ', state: 'State', status: 'Status',
    scName: 'SC Name', scActivities: 'SC Activities', attendance: 'Attendance',
    communityServices: 'Community Services Associated', communityContact: 'Community Contact',
    subsidised: 'Subsidised ', startDate: 'Start Date', day: 'Day', frequency: 'Frequency (During School Term)',
    time: 'Time', venueName: 'Tennis Centre', address: 'Address',
    coachName: 'Coach name', coachNumber: 'Coach Number', contactName: 'Contact Name ',
    contactNumber: 'Contact number', contactEmail: 'Contact Email',
    notes: 'Notes (Bernadette phone calls end of 2025). Next columns on the right are part of survey run at the same time',
    howItsGoing: 'How the program is going, # of participants', equipmentNeeded: 'Equipment or merchandise needed',
    issues: 'Any issues - with coaches, participants', whatsapp: 'Is there a WhatsApp group set up?',
  },
  ' Active Pickleball Programs': {
    locationName: 'Location', state: 'State', status: 'Status',
    scName: 'SC Name', scActivities: 'SC Activities', communityServices: 'Community Services Associated',
    communityContact: 'Community Contact', startDate: 'Start Date', day: 'Day', frequency: 'Occurance (During School Term)',
    time: 'Time', venueName: 'Facility Name/Org', address: 'Address',
    coachName: 'Coach', coachNumber: 'Coach Contact', contactName: 'Contact Name First',
    contactNumber: 'Contact #', contactEmail: 'Contact Email', subsidised: 'Subsidised ',
    attendance: 'Attendance', notes: 'Notes',
  },
  'Prospective programs': {
    locationName: 'Location', state: 'State', status: 'Status',
    scName: 'SC Name', scActivities: 'SC Activities', attendance: 'Projected Attendance',
    communityServices: 'Community Services Associated', communityContact: 'Community Contact',
    startDate: 'Expected Start Date', contactName: 'Contact name', contactNumber: 'Phone ',
    contactEmail: 'Contact email', venueName: 'Tennis Club/ Location', notes: 'Notes',
  },
  'On Hold Inactive': {
    locationName: 'State/Suburb ', state: 'State', status: 'Status',
    scName: 'SC Name', scActivities: 'SC Activities', attendance: 'Prior Attendance',
    communityServices: 'Community Services Associated', communityContact: 'Community Contact',
    startDate: 'Started date', day: 'Day', frequency: 'Frequency (During School Term)', time: 'Time',
    venueName: 'Tennis Centre', address: 'Address', coachName: 'Coach name', coachNumber: 'Coach Number',
    contactName: 'Contact Name ', contactNumber: 'Contact number', contactEmail: 'Contact Email',
    subsidised: 'Subsidised ',
  },
};

// Strip a trailing bare sport word from a locality name -- the real
// project's existing "Condobolin Tennis" -> "Condobolin" program shows
// this cleanup already happened once; reused here so the same spreadsheet
// row derives the same name (and therefore the same program ID) again.
function cleanName(raw) {
  return String(raw ?? '')
    .trim()
    .replace(/\s+(tennis|pickleball)$/i, '')
    .trim();
}

function inferSportFromText(text) {
  const lower = text.toLowerCase();
  const hasTennis = /\btennis\b/.test(lower);
  const hasPickle = /\bpickleball\b|\bpickle ball\b/.test(lower);
  if (hasTennis && !hasPickle) return 'tennis';
  if (hasPickle && !hasTennis) return 'pickleball';
  return null;
}

/** True when a numeric cell's own formatted display differs from its raw
 * value -- i.e. Excel applied a number format (almost always a date/time
 * format for the columns this importer reads) rather than showing the
 * plain number a person typed. Checking the cell this way is fully
 * timezone-independent, unlike converting through a JS Date object (the
 * xlsx package's own cellDates conversion was found to shift by a day
 * depending on the machine's local timezone -- see tests/import-lib). */
function isFormattedNumber(cell) {
  return !!cell && cell.t === 'n' && cell.w !== undefined && cell.w !== String(cell.v);
}

function cellAt(ws, row0, col0) {
  return ws[XLSX.utils.encode_cell({ r: row0, c: col0 })];
}

/** Reads the Time column cell at the given (0-based) row/col. Returns
 * {startTime, endTime, rawTime, review} -- never guesses. A cell that
 * looks like a corrupted date (see isFormattedNumber) is never treated as
 * a time; rawTime keeps its formatted display (e.g. "11-12") for the
 * admin-only field, and a review reason is always added so it surfaces in
 * needs-review.csv. */
function readTimeCell(ws, row0, col0) {
  const cell = cellAt(ws, row0, col0);
  if (!cell || cell.v == null || cell.v === '') return { startTime: null, endTime: null, rawTime: null, review: null };
  if (isFormattedNumber(cell)) {
    return {
      startTime: null, endTime: null, rawTime: cell.w,
      review: `Time column held a datetime, not a time (Excel corruption): raw "${cell.w}"`,
    };
  }
  const text = String(cell.v);
  const parsed = parseTimeRange(text);
  return {
    startTime: parsed.startTime, endTime: parsed.endTime, rawTime: text,
    review: !parsed.startTime && parsed.reason !== 'non-time-text'
      ? `could not parse Time value "${text}" (${parsed.reason})` : null,
  };
}

/** Reads a Start Date/Expected Start Date/Started date cell. A cell
 * formatted as a real date is decoded via XLSX's own timezone-independent
 * serial-date decoder (SSF.parse_date_code); a plain string is parsed as
 * DD/MM/YYYY; anything else (a bare year, "TBA", a mistyped string) is
 * left unparsed with the original text preserved for rawStartDate. */
function readStartDateCell(ws, row0, col0) {
  const cell = cellAt(ws, row0, col0);
  if (!cell || cell.v == null || cell.v === '') return { startDate: null, rawStartDate: null, review: null };
  if (isFormattedNumber(cell)) {
    const { y, m, d } = XLSX.SSF.parse_date_code(cell.v);
    const iso = isoFromYMD(y, m, d);
    if (iso) return { startDate: iso, rawStartDate: null, review: null };
    return { startDate: null, rawStartDate: cell.w, review: `could not parse Start Date value: "${cell.w}"` };
  }
  const text = String(cell.v);
  const iso = parseStartDateText(text);
  if (iso) return { startDate: iso, rawStartDate: null, review: null };
  return { startDate: null, rawStartDate: text, review: `could not parse Start Date value: ${JSON.stringify(text)}` };
}

function parseSheet(fileName, sheetName, sport, ws, headerRow, dataRows, colLetterOf) {
  const cols = COLUMNS[sheetName];
  const records = [];
  dataRows.forEach((dataRow, i) => {
    const sheetRow0 = i + 1; // 0-based; header occupies row 0
    const rowNumber = sheetRow0 + 1; // 1-based, matches what a human sees in Excel
    if (dataRow.every((v) => v == null)) return;
    const obj = {};
    headerRow.forEach((h, idx) => { if (h != null) obj[h] = dataRow[idx] ?? null; });
    const get = (key) => (cols[key] ? obj[cols[key]] : undefined);
    const rawName = get('locationName');
    if (rawName == null || String(rawName).trim() === '') return;
    const name = cleanName(rawName);
    const state = String(get('state') ?? '').trim().toUpperCase();
    const review = [];

    let rowSport = sport;
    if (!rowSport) {
      const combinedText = [get('scActivities'), get('notes'), name].filter(Boolean).join(' ');
      rowSport = inferSportFromText(combinedText);
      if (!rowSport) {
        records.push({
          sheetName, rowNumber, name, state, skip: true,
          review: [{ reason: 'cannot determine sport (tennis/pickleball) from row text' }],
        });
        return;
      }
    }

    const statusRaw = get('status') == null ? '' : String(get('status'));
    const published = statusRaw.trim().toLowerCase() === 'active';

    const dayRaw = get('day');
    const day = parseDay(dayRaw);
    if (dayRaw != null && String(dayRaw).trim() !== '' && day == null) {
      review.push({ reason: `unrecognised Day value: ${JSON.stringify(dayRaw)}` });
    }

    let startTime = null, endTime = null, rawTime = null;
    if (cols.time) {
      const timeCol = colLetterOf(cols.time);
      if (timeCol != null) {
        const t = readTimeCell(ws, sheetRow0, timeCol);
        ({ startTime, endTime, rawTime } = t);
        if (t.review) review.push({ reason: t.review });
      }
    }

    let startDate = null, rawStartDate = null;
    if (cols.startDate) {
      const dateCol = colLetterOf(cols.startDate);
      if (dateCol != null) {
        const d = readStartDateCell(ws, sheetRow0, dateCol);
        ({ startDate, rawStartDate } = d);
        if (d.review) review.push({ reason: d.review });
      }
    }

    const frequency = normalizeFrequency(get('frequency'));
    const venueName = get('venueName') ? String(get('venueName')).trim() : '';
    const address = get('address') ? String(get('address')).trim() : '';

    records.push({
      sheetName, rowNumber, name, state, sport: rowSport, published, statusRaw: statusRaw.trim(),
      day, dayRaw: dayRaw == null ? null : String(dayRaw),
      startTime, endTime, rawTime,
      startDate, rawStartDate,
      // This sheet's own locality column doubles as both the program's
      // display name and the venue's suburb -- unlike the university
      // matrix, which has no comparable per-row suburb at all.
      frequency, venueName, address, suburb: name,
      review,
      operational: {
        scName: get('scName') ?? null,
        communityContact: get('communityContact') ?? null,
        coachName: get('coachName') ?? null,
        coachNumber: get('coachNumber') ?? null,
        contactName: get('contactName') ?? null,
        contactNumber: get('contactNumber') ?? null,
        contactEmail: get('contactEmail') ?? null,
        notes: get('notes') ?? null,
        howItsGoing: get('howItsGoing') ?? null,
        equipmentNeeded: get('equipmentNeeded') ?? null,
        issues: get('issues') ?? null,
        whatsapp: get('whatsapp') ?? null,
        attendance: get('attendance') ?? null,
        subsidised: get('subsidised') ?? null,
      },
      importSource: { file: fileName, sheet: sheetName, row: rowNumber },
    });
  });
  return records;
}

export function parseWorkbook(wb, fileName) {
  const all = [];
  for (const [sheetName, { sport }] of Object.entries(SHEETS)) {
    const ws = wb.Sheets[sheetName];
    if (!ws) {
      all.push({ sheetName, rowNumber: null, skip: true, review: [{ reason: 'sheet not found' }] });
      continue;
    }
    const rows = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null });
    const [headerRow, ...dataRows] = rows;
    const colLetterOf = (headerName) => {
      const idx = headerRow.indexOf(headerName);
      return idx === -1 ? null : idx;
    };
    all.push(...parseSheet(fileName, sheetName, sport, ws, headerRow, dataRows, colLetterOf));
  }
  return all;
}

export function parseMasterSpreadsheet(filePath) {
  const fileName = filePath.split('/').pop();
  const wb = XLSX.readFile(filePath, { cellDates: false });
  return parseWorkbook(wb, fileName);
}
