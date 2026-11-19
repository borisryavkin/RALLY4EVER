// Best-effort, conservative parsing of the free-text `scheduleText` on a
// program into a single weekly recurrence (one weekday, one time range).
// Real imported schedule text is inconsistent, vague ("time varies", "To be
// advised") or describes non-weekly/multi-slot patterns ("Tuesdays & Thursdays",
// "every 3rd Sunday"). Matching docs/PROGRAMS.md's existing promise that
// "school-term/weather text does not create guessed dated occurrences", this
// returns null rather than guessing whenever the text isn't confidently a
// single weekly day+time.
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const UNPARSEABLE = /\bto be (advised|confirmed)\b|\btime varies\b|schedule to verify|\bof the month\b|\bfortnightly\b|\bevery other week\b|\bevery \d+(st|nd|rd|th)\b/i;

function findWeekday(text) {
  const found = new Set();
  for (let i = 0; i < WEEKDAYS.length; i++) {
    if (new RegExp(`\\b${WEEKDAYS[i]}s?\\b`, 'i').test(text)) found.add(i);
  }
  return found.size === 1 ? [...found][0] : null;
}

const TIME_RANGE = /(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\s*-\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)/gi;

function findTimeRange(text) {
  const matches = [...text.matchAll(TIME_RANGE)];
  if (matches.length !== 1) return null;
  const [, sh, sm, sMeridiem, eh, em, eMeridiem] = matches[0];
  let startHour = Number(sh) % 12,
    endHour = Number(eh) % 12;
  const endPm = eMeridiem.toLowerCase() === 'pm';
  if (endPm) endHour += 12;
  let startPm;
  if (sMeridiem) {
    startPm = sMeridiem.toLowerCase() === 'pm';
  } else {
    // Infer the start meridiem from the end's: a same-period range (e.g.
    // "6-7pm") shares it; a range crossing noon (e.g. "11-1pm") doesn't.
    startPm = Number(sh) <= Number(eh) ? endPm : !endPm;
  }
  if (startPm) startHour += 12;
  return {
    startHour,
    startMinute: sm ? Number(sm) : 0,
    endHour,
    endMinute: em ? Number(em) : 0,
  };
}

// Returns null when the text isn't confidently a single weekly day + single
// time range, otherwise { weekday (0=Sunday..6=Saturday), startHour,
// startMinute, endHour, endMinute }.
export function parseWeeklySchedule(scheduleText) {
  const text = String(scheduleText ?? '').trim();
  if (!text || UNPARSEABLE.test(text)) return null;
  const weekday = findWeekday(text);
  if (weekday == null) return null;
  const time = findTimeRange(text);
  if (!time) return null;
  const startMinutes = time.startHour * 60 + time.startMinute,
    endMinutes = time.endHour * 60 + time.endMinute;
  if (endMinutes <= startMinutes || endMinutes - startMinutes > 24 * 60) return null;
  return { weekday, ...time };
}

// Correct wall-clock-in-timezone -> UTC conversion without a date library,
// using iterative convergence against Intl's own IANA tz data (handles DST).
function offsetMinutes(utcMillis, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(utcMillis));
  const p = Object.fromEntries(parts.map((x) => [x.type, x.value]));
  const asUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  return (asUtc - utcMillis) / 60000;
}

export function zonedTimeToUtc(year, month, day, hour, minute, timeZone) {
  let guessMillis = Date.UTC(year, month - 1, day, hour, minute);
  for (let i = 0; i < 3; i++) {
    guessMillis = Date.UTC(year, month - 1, day, hour, minute) - offsetMinutes(guessMillis, timeZone) * 60000;
  }
  return new Date(guessMillis);
}

// The next `count` occurrences of `weekday` at the given local time in
// `timeZone`, strictly after `now`, one per week starting from the soonest.
export function nextWeeklyOccurrences(weekday, hour, minute, timeZone, now, count) {
  const nowParts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  }).formatToParts(now);
  const p = Object.fromEntries(nowParts.map((x) => [x.type, x.value]));
  const todayWeekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday);
  let daysAhead = (weekday - todayWeekday + 7) % 7;
  let candidate = zonedTimeToUtc(+p.year, +p.month, +p.day + daysAhead, hour, minute, timeZone);
  if (candidate.getTime() <= now.getTime()) {
    daysAhead += 7;
    candidate = zonedTimeToUtc(+p.year, +p.month, +p.day + daysAhead, hour, minute, timeZone);
  }
  const results = [candidate];
  for (let i = 1; i < count; i++) {
    results.push(zonedTimeToUtc(+p.year, +p.month, +p.day + daysAhead + i * 7, hour, minute, timeZone));
  }
  return results;
}
