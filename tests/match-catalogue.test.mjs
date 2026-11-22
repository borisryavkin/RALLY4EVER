import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matchVenue, matchProgram, similarity, FUZZY_VENUE_THRESHOLD } from '../scripts/match-catalogue.mjs';

const existingVenues = [
  { id: 'v-57b7e3a779ad3a9d349a', name: 'Armidale Tennis Centre', suburb: 'Armidale', state: 'NSW', isDemo: false },
  { id: 'ba462c9d-14ed-4cea-a3f1-3c0ab3c69e1d', name: 'Junction Hill Tennis Club', suburb: 'Junction Hill', state: 'NSW', isDemo: false },
  { id: '168ae1ac-cc76-4c34-bb78-243401b56129', name: 'Admin verification — test venue only', suburb: 'Sydney', state: 'NSW', isDemo: true },
  { id: 'v-d9a81dbdc3e316f7a64e', name: 'KDV', suburb: 'Southport', state: 'QLD', isDemo: true },
];

test('matchVenue reuses an existing venue ID on an exact normalized-name + state match', () => {
  const result = matchVenue({ venueName: 'Armidale Tennis Centre', state: 'NSW', suburb: 'Armidale' }, existingVenues);
  assert.equal(result.status, 'matched');
  assert.equal(result.id, 'v-57b7e3a779ad3a9d349a');
});

test('matchVenue matches despite spelling/punctuation differences via normalization', () => {
  const result = matchVenue({ venueName: '  armidale,  tennis centre!! ', state: 'nsw' }, existingVenues);
  assert.equal(result.status, 'matched');
  assert.equal(result.id, 'v-57b7e3a779ad3a9d349a');
});

test('matchVenue never matches a demo venue, even with an identical name', () => {
  const result = matchVenue({ venueName: 'KDV', state: 'QLD' }, existingVenues);
  assert.equal(result.status, 'new');
});

test('matchVenue sends a near-miss to review instead of auto-matching or silently creating new', () => {
  // One missing letter -- high similarity, but not an exact normalized
  // match (unlike a Centre/Center spelling difference, which the filler-
  // word strip already neutralizes into an exact match deliberately).
  const result = matchVenue({ venueName: 'Armadale Tennis Centre', state: 'NSW' }, existingVenues);
  assert.equal(result.status, 'review');
  assert.equal(result.candidateId, 'v-57b7e3a779ad3a9d349a');
  assert.ok(result.score >= FUZZY_VENUE_THRESHOLD);
});

test('matchVenue mints a new deterministic ID when nothing is close', () => {
  const result = matchVenue({ venueName: 'Brand New Courts', state: 'VIC' }, existingVenues);
  assert.equal(result.status, 'new');
  assert.equal(result.id, 'brand-new-courts-vic');
});

test('similarity is 1 for identical strings and drops for unrelated ones', () => {
  assert.equal(similarity('armidale', 'armidale'), 1);
  assert.ok(similarity('armidale', 'woolloomooloo') < 0.5);
});

const existingPrograms = [
  { id: 'nsw-tennis-armidale', sport: 'tennis', isDemo: false, needsVerification: false, scheduleText: 'Every Sunday · 2-3pm', venue: { name: 'Armidale Tennis Centre', state: 'NSW' } },
  { id: 'nsw-tennis-cowra', sport: 'tennis', isDemo: false, needsVerification: true, scheduleText: 'Schedule to verify', venue: { name: 'Cowra (venue to verify)', state: 'NSW' } },
  { id: 'humanitix-unsw-pickleball', sport: 'pickleball', isDemo: false, needsVerification: false, scheduleText: 'Tuesdays 13:00–14:00', venue: { name: 'UNSW Fitness & Aquatic Centre (B5), Court 1', state: 'NSW' } },
];

test('matchProgram matches by the existing deterministic ID scheme and reports whether it was already reviewed', () => {
  const reviewed = matchProgram({ name: 'Armidale', state: 'NSW', sport: 'tennis', venueName: 'Armidale Tennis Centre', day: 'Sun' }, existingPrograms);
  assert.equal(reviewed.status, 'matched');
  assert.equal(reviewed.id, 'nsw-tennis-armidale');
  assert.equal(reviewed.via, 'id');
  assert.equal(reviewed.reviewed, true);

  const unreviewed = matchProgram({ name: 'Cowra', state: 'NSW', sport: 'tennis', venueName: 'Cowra (venue to verify)', day: null }, existingPrograms);
  assert.equal(unreviewed.reviewed, false);
});

test('matchProgram falls back to venue+day when the ID scheme differs (e.g. a Humanitix-sourced program)', () => {
  const result = matchProgram(
    { name: 'Pickleball at UNSW', state: 'NSW', sport: 'pickleball', venueName: 'UNSW Fitness & Aquatic Centre', day: 'Tue' },
    existingPrograms,
  );
  assert.equal(result.status, 'matched');
  assert.equal(result.id, 'humanitix-unsw-pickleball');
  assert.equal(result.via, 'venue+day');
});

test('matchProgram sends an uncorroborated venue match to review rather than guessing', () => {
  const result = matchProgram(
    { name: 'Pickleball at UNSW (new name)', state: 'NSW', sport: 'pickleball', venueName: 'UNSW Fitness & Aquatic Centre', day: 'Fri' },
    existingPrograms,
  );
  assert.equal(result.status, 'review');
  assert.equal(result.candidateId, 'humanitix-unsw-pickleball');
});

test('matchProgram creates a new deterministic ID when nothing matches', () => {
  const result = matchProgram(
    { name: 'Brand New Town', state: 'VIC', sport: 'tennis', venueName: 'Somewhere New', day: 'Mon' },
    existingPrograms,
  );
  assert.equal(result.status, 'new');
  assert.equal(result.id, 'vic-tennis-brand-new-town');
});
