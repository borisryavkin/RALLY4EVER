import { createHash } from 'node:crypto';

/** Lowercase, trim, collapse whitespace, strip punctuation and the given
 * filler words -- for COMPARISON only, never for display/storage. */
export function normalizeVenueName(name, { stripFiller = true } = {}) {
  let s = String(name ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (stripFiller) {
    for (const filler of ['tennis club', 'tennis centre', 'tennis center']) {
      s = s.replace(new RegExp(`\\b${filler}\\b`, 'g'), '').replace(/\s+/g, ' ').trim();
    }
  }
  return s;
}

export function slug(s) {
  return String(s ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** Matches the existing real `programs` collection's own ID convention
 * (nsw-tennis-armidale, vic-pickleball-albury-wodonga, ...) -- reused so a
 * freshly-computed ID matches an already-imported program instead of
 * minting a parallel duplicate ID scheme. */
export function programId(state, sport, name) {
  const key = `${state}-${sport}-${slug(name)}`.toLowerCase();
  if (key.length <= 120) return key;
  const hash = createHash('sha256').update(key).digest('hex').slice(0, 8);
  return `${key.slice(0, 110)}-${hash}`;
}

/** Deterministic venue ID for a NEWLY-created venue only -- an existing
 * venue is always matched and reused by its own (often unrelated-looking)
 * existing ID; this is never used to look an existing venue up. */
export function venueId(name, state) {
  const key = `${slug(name)}-${String(state ?? '').toLowerCase()}`;
  if (key.length <= 120) return key;
  const hash = createHash('sha256').update(key).digest('hex').slice(0, 8);
  return `${key.slice(0, 110)}-${hash}`;
}

export function importKey(parts) {
  return createHash('sha256').update(parts.join('|')).digest('hex');
}

const DAY_MAP = {
  sun: 'Sun', sunday: 'Sun',
  mon: 'Mon', monday: 'Mon',
  tue: 'Tue', tues: 'Tue', tuesday: 'Tue', tueaday: 'Tue',
  wed: 'Wed', weds: 'Wed', wednesday: 'Wed',
  thu: 'Thu', thur: 'Thu', thurs: 'Thu', thursday: 'Thu',
  fri: 'Fri', friday: 'Fri',
  sat: 'Sat', saturday: 'Sat',
};
const DAY_INDEX = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** Returns a canonical 'Sun'..'Sat' token, or null if the text isn't a
 * single recognisable day (multi-day text like "Tuesday & Thursday" and
 * garbage like "??" both return null -- never guessed at). */
export function parseDay(raw) {
  if (raw == null) return null;
  const key = String(raw).trim().toLowerCase();
  return DAY_MAP[key] ?? null;
}

/** The authoritative day-of-week for a real calendar Date, for
 * cross-checking a free-typed "Day of week" column against the Date
 * column it's supposed to describe. */
export function weekdayFromDate(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  return DAY_INDEX[date.getUTCDay()];
}

function to24h(hour, minute, meridiem) {
  let h = hour % 12;
  if (meridiem === 'pm') h += 12;
  return `${String(h).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

/** Parses readable ranges like "2-3pm", "5.30-6.30pm", "11am-12pm",
 * "10-11.30am", "9-10:30" (no am/pm anywhere -- ambiguous, returns null),
 * "after school" (stays text, returns null so the caller keeps it as-is,
 * never as a time). A plain Date/string that looks like a corrupted
 * spreadsheet datetime (the caller passes isCorruptedDatetime) is never
 * parsed here -- see parseTimeCell. */
export function parseTimeRange(raw) {
  if (raw == null) return { startTime: null, endTime: null, reason: 'empty' };
  const text = String(raw).trim().toLowerCase();
  if (!text) return { startTime: null, endTime: null, reason: 'empty' };
  if (/after\s*school|to\s*be\s*(advised|confirmed)|tba|varies/.test(text)) {
    return { startTime: null, endTime: null, reason: 'non-time-text' };
  }
  // e.g. "2-3pm", "5.30-6.30pm", "11am-12pm", "10-11.30am", "9-10:30",
  // "1:00-2:30", "12:30 pm - 2:00 pm", "11-12:30"
  const m = text.match(
    /^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\s*-\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?$/,
  );
  if (!m) return { startTime: null, endTime: null, reason: 'unrecognised-format' };
  const [, h1, m1, mer1, h2, m2, mer2] = m;
  const startHour = Number(h1), endHour = Number(h2);
  const startMin = m1 ? Number(m1) : 0, endMin = m2 ? Number(m2) : 0;
  // Already unambiguous 24-hour notation (e.g. "13:00-14:00", as produced
  // by some of the university schedule's Time column) needs no am/pm.
  if (startHour >= 13 || endHour >= 13 || (startHour === 0 || endHour === 0)) {
    if (startHour > 23 || endHour > 23) return { startTime: null, endTime: null, reason: 'unrecognised-format' };
    return {
      startTime: `${String(startHour).padStart(2, '0')}:${String(startMin).padStart(2, '0')}`,
      endTime: `${String(endHour).padStart(2, '0')}:${String(endMin).padStart(2, '0')}`,
      reason: null,
    };
  }
  // Need an am/pm somewhere to resolve either end unambiguously. If only
  // one side states it, the other end shares it unless the numbers imply
  // otherwise (e.g. "11-12pm" means 11am-12pm, "2-3pm" means 2pm-3pm):
  // an end hour of 12 with an explicit pm, and a start hour that is NOT
  // 12, means the start is actually am (11am-12pm), while every other
  // combination shares the stated meridiem across both ends.
  let meridiem = mer1 ?? mer2;
  if (!meridiem) return { startTime: null, endTime: null, reason: 'no-am-pm' };
  let startMeridiem = mer1 ?? meridiem;
  let endMeridiem = mer2 ?? meridiem;
  if (!mer1 && mer2 === 'pm' && endHour === 12 && startHour !== 12) {
    startMeridiem = 'am';
  }
  const startTime = to24h(startHour, startMin, startMeridiem);
  const endTime = to24h(endHour, endMin, endMeridiem);
  return { startTime, endTime, reason: null };
}

/** `frequency` is free text in the spreadsheet ("Weekly", "Monthly",
 * "Fortnightly", "1st Tuesday of the month", ...). Maps the handful of
 * single-word values onto the existing frequency vocabulary and leaves
 * anything longer/descriptive as-is (folded into scheduleText, not
 * dropped). */
export function normalizeFrequency(raw) {
  const text = String(raw ?? '').trim();
  const lower = text.toLowerCase();
  if (lower === 'weekly') return 'Weekly';
  if (lower === 'monthly') return 'Monthly';
  if (lower === 'fortnightly') return 'Fortnightly';
  return text || null;
}

/** Builds 'YYYY-MM-DD' from already-validated integer parts (e.g. from
 * XLSX's own serial-date decoder, which is timezone-independent -- unlike
 * a JS Date built from a spreadsheet library's date conversion, which can
 * shift by a day depending on the machine's local timezone). Returns null
 * for a calendar-invalid combination (which also catches overflowed
 * month/day from a bad decode) rather than silently normalizing it. */
export function isoFromYMD(year, month, day) {
  if (![year, month, day].every(Number.isInteger)) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    return null;
  }
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/** A Start Date spreadsheet cell that is plain text (not a real date
 * serial -- see isoFromYMD for that path). Only an unambiguous DD/MM/YYYY
 * string is parsed; "2021" (year only), "TBA", "7/1072025" (clearly
 * mistyped) and anything else never-guessable returns null, with the
 * original text preserved by the caller in rawStartDate. */
export function parseStartDateText(raw) {
  if (raw == null || raw === '') return null;
  const text = String(raw).trim();
  const m = text.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return null;
  const [, d, mo, y] = m;
  return isoFromYMD(Number(y), Number(mo), Number(d));
}
