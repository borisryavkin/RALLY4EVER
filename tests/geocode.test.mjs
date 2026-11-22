import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Geocoder, withinState, haversineM } from '../scripts/geocode.mjs';

test('withinState sanity-checks a result against a generous AU bounding box', () => {
  assert.equal(withinState(-30.51, 151.66, 'NSW'), true);
  assert.equal(withinState(-37.81, 144.96, 'NSW'), false); // Melbourne, not NSW
  assert.equal(withinState(-37.81, 144.96, 'VIC'), true);
  assert.equal(withinState(-30.51, 151.66, 'ZZ'), false);
});

test('haversineM returns ~0 for identical points and a sane order of magnitude for a real pair', () => {
  assert.ok(haversineM(-33.89, 151.13, -33.89, 151.13) < 1);
  // Sydney CBD to Parramatta, roughly 20km.
  const d = haversineM(-33.8688, 151.2093, -33.8151, 151.0011);
  assert.ok(d > 15000 && d < 25000, d);
});

function fakeGeocoderFetch(responses) {
  return async (url) => ({
    ok: true,
    json: async () => {
      const q = decodeURIComponent(new URL(url).searchParams.get('q'));
      const hit = responses.find((r) => q.includes(r.match));
      return hit ? [{ lat: String(hit.lat), lon: String(hit.lng) }] : [];
    },
  });
}

let dir;
test.beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'geocode-test-'));
});
test.afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

test('geocodeVenue uses the address, marks high confidence when near the suburb centroid', async () => {
  const fetchImpl = fakeGeocoderFetch([
    { match: 'Golf Link Rd', lat: -30.5, lng: 151.66 },
    { match: 'Armidale, NSW', lat: -30.5144881, lng: 151.6656564 },
  ]);
  const g = new Geocoder({ cachePath: join(dir, 'cache.json'), fetchImpl });
  const result = await g.geocodeVenue({
    name: 'Armidale Tennis Centre',
    address: 'Golf Link Rd, Armidale, NSW 2350',
    suburb: 'Armidale',
    state: 'NSW',
  });
  assert.equal(result.geocodeConfidence, 'high');
  assert.ok(Math.abs(result.lat - -30.5) < 0.01);
});

test('geocodeVenue falls back to name+suburb+state when address is missing, marks low confidence', async () => {
  const fetchImpl = fakeGeocoderFetch([
    { match: 'Ultimo Community Centre', lat: -33.878, lng: 151.1977 },
    { match: 'Ultimo, NSW', lat: -33.879, lng: 151.198 },
  ]);
  const g = new Geocoder({ cachePath: join(dir, 'cache.json'), fetchImpl });
  const result = await g.geocodeVenue({
    name: 'Ultimo Community Centre',
    address: '',
    suburb: 'Ultimo',
    state: 'NSW',
  });
  assert.equal(result.geocodeConfidence, 'low');
  assert.notEqual(result.lat, null);
});

test('geocodeVenue rejects a result that lands in the wrong state', async () => {
  const fetchImpl = fakeGeocoderFetch([{ match: 'Fake Rd', lat: -37.81, lng: 144.96 }]);
  const g = new Geocoder({ cachePath: join(dir, 'cache.json'), fetchImpl });
  const result = await g.geocodeVenue({
    name: 'Somewhere',
    address: 'Fake Rd, Somewhere, NSW',
    suburb: 'Somewhere',
    state: 'NSW',
  });
  assert.equal(result.lat, null);
  assert.equal(result.geocodeConfidence, 'rejected-wrong-state');
});

test('geocodeVenue rejects a result implausibly far from its own suburb centroid', async () => {
  const fetchImpl = fakeGeocoderFetch([
    { match: 'Weird Address', lat: -33.0, lng: 151.0 },
    { match: 'Faraway, NSW', lat: -29.0, lng: 149.0 },
  ]);
  const g = new Geocoder({ cachePath: join(dir, 'cache.json'), fetchImpl });
  const result = await g.geocodeVenue({
    name: 'Weird Venue',
    address: 'Weird Address',
    suburb: 'Faraway',
    state: 'NSW',
  });
  assert.equal(result.lat, null);
  assert.equal(result.geocodeConfidence, 'rejected-far-from-suburb');
});

test('geocodeVenue returns none when nothing matches, and never throws', async () => {
  const fetchImpl = fakeGeocoderFetch([]);
  const g = new Geocoder({ cachePath: join(dir, 'cache.json'), fetchImpl });
  const result = await g.geocodeVenue({ name: 'Nowhere', address: '', suburb: '', state: 'NSW' });
  assert.equal(result.lat, null);
  assert.equal(result.geocodeConfidence, 'none');
});

test('every result is cached: a second identical lookup makes zero further network calls', async () => {
  let calls = 0;
  const fetchImpl = async (url) => {
    calls++;
    return fakeGeocoderFetch([
      { match: 'Golf Link Rd', lat: -30.5, lng: 151.66 },
      { match: 'Armidale, NSW', lat: -30.5144881, lng: 151.6656564 },
    ])(url);
  };
  const cachePath = join(dir, 'cache.json');
  const venue = {
    name: 'Armidale Tennis Centre',
    address: 'Golf Link Rd, Armidale, NSW 2350',
    suburb: 'Armidale',
    state: 'NSW',
  };
  const g1 = new Geocoder({ cachePath, fetchImpl });
  await g1.geocodeVenue(venue);
  await g1.save();
  const callsAfterFirstRun = calls;
  assert.ok(callsAfterFirstRun > 0);

  const g2 = new Geocoder({ cachePath, fetchImpl });
  await g2.geocodeVenue(venue);
  assert.equal(calls, callsAfterFirstRun);
});
