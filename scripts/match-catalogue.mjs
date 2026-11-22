import { normalizeVenueName, programId as mintProgramId, venueId as mintVenueId } from './import-lib.mjs';

function levenshtein(a, b) {
  const m = a.length, n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  const row = new Array(n + 1);
  for (let j = 0; j <= n; j++) row[j] = j;
  for (let i = 1; i <= m; i++) {
    let prev = row[0];
    row[0] = i;
    for (let j = 1; j <= n; j++) {
      const temp = row[j];
      row[j] = a[i - 1] === b[j - 1]
        ? prev
        : 1 + Math.min(prev, row[j], row[j - 1]);
      prev = temp;
    }
  }
  return row[n];
}

/** 1.0 = identical, 0.0 = nothing in common. A long common prefix (e.g.
 * "UNSW Fitness & Aquatic Centre" vs. a Humanitix-sourced "UNSW Fitness &
 * Aquatic Centre (B5), Court 1") is treated as a strong match on its own
 * -- real venue names that share a clean prefix like this are the same
 * venue described at different levels of detail far more often than they
 * are two coincidentally-similarly-named different venues, and plain
 * edit-distance badly underrates it once the appended detail gets long. */
export function similarity(a, b) {
  const longer = Math.max(a.length, b.length);
  if (longer === 0) return 1;
  const base = 1 - levenshtein(a, b) / longer;
  const [shorter, longerStr] = a.length <= b.length ? [a, b] : [b, a];
  const prefixBoost = shorter.length >= 6 && longerStr.startsWith(shorter) ? 0.95 : 0;
  return Math.max(base, prefixBoost);
}

// Below this, two venue names are considered unrelated (new venue).
// At or above it but not identical, it's a fuzzy match -- reviewed, not
// auto-applied, per the task's explicit "any near-match... goes into a
// review list, not applied" instruction.
export const FUZZY_VENUE_THRESHOLD = 0.82;

/** Matches a spreadsheet row's venue against existing `venues/{id}`
 * documents. Demo/test venues (isDemo === true) are never matched
 * against. Returns one of:
 *  - {status:'matched', id, confidence:'exact'} -- reuse this ID.
 *  - {status:'review', candidateId, score} -- fuzzy match, needs a human.
 *  - {status:'new'} -- mint a new venue with the deterministic ID. */
export function matchVenue({ venueName, state, suburb }, existingVenues) {
  const normTarget = normalizeVenueName(venueName);
  const candidates = existingVenues.filter(
    (v) => !v.isDemo && (v.state ?? '').toUpperCase() === (state ?? '').toUpperCase(),
  );
  for (const v of candidates) {
    if (normalizeVenueName(v.name) === normTarget) {
      return { status: 'matched', id: v.id, confidence: 'exact' };
    }
  }
  let best = null;
  for (const v of candidates) {
    const score = similarity(normTarget, normalizeVenueName(v.name));
    if (score >= FUZZY_VENUE_THRESHOLD && (!best || score > best.score)) {
      best = { candidateId: v.id, score, name: v.name };
    }
  }
  if (best) return { status: 'review', ...best };
  return { status: 'new', id: mintVenueId(venueName, state) };
}

/** Matches a spreadsheet row's program. Primary signal: the deterministic
 * ID already used by every non-Humanitix program in the real project
 * (<state>-<sport>-<slug(name)>). Secondary signal (per the task's "match
 * ... by venue ID + day + start time, including those already imported
 * from Humanitix"): an existing program -- any ID scheme -- whose own
 * embedded venue name normalizes the same and whose scheduleText mentions
 * the same day, treated as a probable match for the SAME underlying
 * program under a different source/ID scheme. Demo programs are excluded.
 * An existing program with needsVerification === false is matched (so the
 * caller can log it) but the caller must never overwrite its content --
 * see docs/import/programs-mapping.md's central safety rule. */
export function matchProgram({ name, state, sport, venueName, day }, existingPrograms) {
  // A display name like "Pickleball at Macquarie University" would
  // otherwise double up with the sport already baked into the ID
  // template (nsw-pickleball-pickleball-at-...); strip that redundant
  // "<sport> at " prefix for ID minting only, never for the stored name.
  const idName = name.replace(new RegExp(`^${sport}\\s+at\\s+`, 'i'), '');
  const candidateId = mintProgramId(state, sport, idName);
  const byId = existingPrograms.find((p) => p.id === candidateId && !p.isDemo);
  if (byId) return { status: 'matched', id: byId.id, via: 'id', reviewed: byId.needsVerification === false };

  const normTarget = normalizeVenueName(venueName);
  const sameSportState = existingPrograms.filter(
    (p) => !p.isDemo && p.sport === sport && (p.venue?.state ?? '').toUpperCase() === (state ?? '').toUpperCase(),
  );
  // Same fuzzy-match tolerance as matchVenue: an exact normalized name is
  // never below the threshold, so this one check covers both "identical"
  // and "close enough to need a day cross-check" (e.g. the real project's
  // "UNSW Fitness & Aquatic Centre" vs. a Humanitix-sourced "UNSW Fitness
  // & Aquatic Centre (B5), Court 1").
  const scored = sameSportState
    .map((p) => ({ p, score: similarity(normTarget, normalizeVenueName(p.venue?.name ?? '')) }))
    .filter((s) => s.score >= FUZZY_VENUE_THRESHOLD)
    .sort((a, b) => b.score - a.score);
  if (scored.length > 1 && scored[0].score === scored[1].score) {
    return { status: 'review', candidateIds: scored.map((s) => s.p.id), reason: 'multiple existing programs share this venue/sport/state' };
  }
  if (scored.length >= 1) {
    const candidate = scored[0].p;
    const corroborated = day && (candidate.scheduleText ?? '').toLowerCase().includes(day.toLowerCase());
    if (corroborated) {
      return { status: 'matched', id: candidate.id, via: 'venue+day', reviewed: candidate.needsVerification === false };
    }
    return { status: 'review', candidateId: candidate.id, reason: 'same venue/sport/state, day not corroborated in scheduleText' };
  }
  return { status: 'new', id: candidateId };
}
