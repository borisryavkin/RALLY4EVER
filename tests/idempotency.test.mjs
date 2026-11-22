import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matchVenue, matchProgram } from '../scripts/match-catalogue.mjs';

/** Simulates "run the import twice": the first run's own planned creates
 * become part of the existing catalogue for the second run, exactly as
 * they would after a real apply. The second run must match everything
 * the first run created rather than creating anything new. */
test('venue + program matching is idempotent across two simulated runs', () => {
  const row = { name: 'Armidale', state: 'NSW', sport: 'tennis', venueName: 'Armidale Tennis Centre', day: 'Sun' };

  const firstVenueMatch = matchVenue({ venueName: row.venueName, state: row.state }, []);
  assert.equal(firstVenueMatch.status, 'new');
  const venueAfterFirstRun = [{ id: firstVenueMatch.id, name: row.venueName, state: row.state, isDemo: false }];

  const firstProgramMatch = matchProgram(row, []);
  assert.equal(firstProgramMatch.status, 'new');
  const programsAfterFirstRun = [{
    id: firstProgramMatch.id, sport: row.sport, isDemo: false, needsVerification: true,
    venue: { name: row.venueName, state: row.state }, scheduleText: 'Every Sunday',
  }];

  // Second run, same input, against the catalogue the first run produced.
  const secondVenueMatch = matchVenue({ venueName: row.venueName, state: row.state }, venueAfterFirstRun);
  assert.equal(secondVenueMatch.status, 'matched');
  assert.equal(secondVenueMatch.id, firstVenueMatch.id);

  const secondProgramMatch = matchProgram(row, programsAfterFirstRun);
  assert.equal(secondProgramMatch.status, 'matched');
  assert.equal(secondProgramMatch.id, firstProgramMatch.id);
  // Once imported, needsVerification stays true (not yet human-reviewed),
  // so a third run would still update it rather than silently stopping --
  // but never duplicate-create it, which is what this test actually locks in.
  assert.equal(secondProgramMatch.reviewed, false);
});

test('a program a human has since reviewed (needsVerification: false) still matches by ID on a later run, so it is never duplicated -- only its content is protected, not its matchability', () => {
  const row = { name: 'Armidale', state: 'NSW', sport: 'tennis', venueName: 'Armidale Tennis Centre', day: 'Sun' };
  const reviewed = [{
    id: 'nsw-tennis-armidale', sport: 'tennis', isDemo: false, needsVerification: false,
    venue: { name: 'Armidale Tennis Centre', state: 'NSW' }, scheduleText: 'Every Sunday (Weather Permitting) · 2-3pm',
  }];
  const match = matchProgram(row, reviewed);
  assert.equal(match.status, 'matched');
  assert.equal(match.id, 'nsw-tennis-armidale');
  assert.equal(match.reviewed, true);
});
