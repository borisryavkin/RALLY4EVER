import { readFile, writeFile } from 'node:fs/promises';

// Approximate bounding boxes, generous on purpose -- this is a sanity
// check against an obviously wrong result (wrong state entirely), not a
// precise boundary.
const STATE_BOUNDS = {
  NSW: { minLat: -37.6, maxLat: -28.1, minLng: 140.9, maxLng: 153.7 },
  ACT: { minLat: -35.95, maxLat: -35.1, minLng: 148.7, maxLng: 149.4 },
  VIC: { minLat: -39.2, maxLat: -33.9, minLng: 140.9, maxLng: 150.1 },
  QLD: { minLat: -29.2, maxLat: -9.1, minLng: 137.9, maxLng: 153.6 },
  SA: { minLat: -38.1, maxLat: -25.9, minLng: 129.0, maxLng: 141.1 },
  WA: { minLat: -35.3, maxLat: -13.5, minLng: 112.9, maxLng: 129.1 },
  NT: { minLat: -26.1, maxLat: -10.9, minLng: 129.0, maxLng: 138.1 },
  TAS: { minLat: -43.7, maxLat: -39.5, minLng: 143.8, maxLng: 148.5 },
};

export function withinState(lat, lng, state) {
  const b = STATE_BOUNDS[state];
  if (!b) return false;
  return lat >= b.minLat && lat <= b.maxLat && lng >= b.minLng && lng <= b.maxLng;
}

export function haversineM(lat1, lng1, lat2, lng2) {
  const rad = Math.PI / 180;
  const a =
    Math.sin(((lat2 - lat1) * rad) / 2) ** 2 +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(((lng2 - lng1) * rad) / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, a))));
}

const USER_AGENT =
  'Rally4EverProgramsImport/1.0 (https://rally4ever.org; one-off admin data import, not a live service)';
const MIN_INTERVAL_MS = 1100; // Nominatim usage policy: max 1 request/second.

export class Geocoder {
  constructor({ cachePath, fetchImpl = fetch, log = () => {} } = {}) {
    this.cachePath = cachePath;
    this.fetchImpl = fetchImpl;
    this.log = log;
    this.cache = null;
    this.lastRequestAt = 0;
    this.networkCalls = 0;
  }

  async load() {
    if (this.cache) return;
    try {
      this.cache = JSON.parse(await readFile(this.cachePath, 'utf8'));
    } catch {
      this.cache = {};
    }
  }

  async save() {
    await writeFile(this.cachePath, JSON.stringify(this.cache, null, 2) + '\n', { mode: 0o600 });
  }

  async _throttledFetch(url) {
    const wait = this.lastRequestAt + MIN_INTERVAL_MS - Date.now();
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    this.lastRequestAt = Date.now();
    this.networkCalls++;
    const res = await this.fetchImpl(url, { headers: { 'User-Agent': USER_AGENT } });
    if (!res.ok) throw new Error(`Nominatim HTTP ${res.status}`);
    return res.json();
  }

  async _lookup(query) {
    await this.load();
    const key = query.trim().toLowerCase();
    if (key in this.cache) return this.cache[key];
    const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q=${encodeURIComponent(query)}`;
    let result = null;
    try {
      const rows = await this._throttledFetch(url);
      if (rows[0]) result = { lat: Number(rows[0].lat), lng: Number(rows[0].lon) };
    } catch (e) {
      this.log(`Geocode lookup failed for "${query}": ${e.message}`);
    }
    this.cache[key] = result;
    return result;
  }

  /** Geocodes a venue. Prefers the full address; falls back to
   * name+suburb+state (marked low confidence) if there's no address.
   * Cross-checks against the suburb's own centroid: outside the expected
   * state, or implausibly far (>60km) from the suburb centroid, both
   * leave coordinates empty rather than storing a wrong result. */
  async geocodeVenue({ name, address, suburb, state }) {
    const country = ', Australia';
    let primary = null, usedFallback = false;
    if (address && address.trim()) {
      primary = await this._lookup(`${address}${country}`);
    }
    if (!primary && name) {
      usedFallback = true;
      primary = await this._lookup(`${name}, ${suburb ?? ''}, ${state ?? ''}${country}`);
    }
    if (!primary) {
      return { lat: null, lng: null, geocodeConfidence: 'none' };
    }
    if (!withinState(primary.lat, primary.lng, state)) {
      return { lat: null, lng: null, geocodeConfidence: 'rejected-wrong-state' };
    }
    let confidence = usedFallback ? 'low' : 'high';
    if (suburb && suburb.trim()) {
      const suburbCentroid = await this._lookup(`${suburb}, ${state ?? ''}${country}`);
      if (suburbCentroid) {
        const distance = haversineM(primary.lat, primary.lng, suburbCentroid.lat, suburbCentroid.lng);
        if (distance > 60000) {
          return { lat: null, lng: null, geocodeConfidence: 'rejected-far-from-suburb' };
        }
        if (distance > 20000 && confidence === 'high') confidence = 'low';
      }
    }
    return { lat: primary.lat, lng: primary.lng, geocodeConfidence: confidence };
  }
}
