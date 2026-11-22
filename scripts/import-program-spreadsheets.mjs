#!/usr/bin/env node
// Imports R4E_PROGRAMS_MASTER_SPREADSHEET.xlsx and
// University_PickleBall_Program_Matrix_.xlsx (both in data-private/,
// git-ignored) into the real rally4ever-3adaf Firestore project.
//
// Usage:
//   node scripts/import-program-spreadsheets.mjs                 (dry run)
//   node scripts/import-program-spreadsheets.mjs --apply          (real writes)
//
// Dry run NEVER touches Firestore for writes -- it still reads the real
// `programs`/`venues` collections (read-only) so matching/dedup is
// accurate, and geocodes new venues (also read-only against Nominatim,
// cached in data-private/geocode-cache.json).
//
// See docs/import/programs-mapping.md for the schema this reuses and the
// safety rules this script follows (never overwrite an already-reviewed
// program; never touch coachNames; demo docs are never matched against).
import { writeFile, mkdir } from 'node:fs/promises';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { parseMasterSpreadsheet } from './parse-master-spreadsheet.mjs';
import { parseUniversityMatrix } from './parse-university-matrix.mjs';
import { matchVenue, matchProgram } from './match-catalogue.mjs';
import { importKey as hashImportKey } from './import-lib.mjs';
import { Geocoder } from './geocode.mjs';

const PROJECT_ID = 'rally4ever-3adaf';
const MASTER_PATH = 'data-private/R4E_PROGRAMS_MASTER_SPREADSHEET.xlsx';
const MATRIX_PATH = 'data-private/University_PickleBall_Program_Matrix_.xlsx';
const GEOCODE_CACHE = 'data-private/geocode-cache.json';
const OUT_DIR = 'docs/import';
const BATCH_LIMIT = 400;

const apply = process.argv.includes('--apply');

function scheduleTextFor(row) {
  const parts = [];
  if (row.day) parts.push(`Every ${fullDay(row.day)}`);
  if (row.startTime && row.endTime) parts.push(`${displayTime(row.startTime)}-${displayTime(row.endTime)}`);
  // "Every <Day>" already says weekly; only append frequency when it adds
  // information ("Monthly", "1st Tuesday of the month", ...).
  if (row.frequency && row.frequency !== 'Weekly') parts.push(row.frequency);
  return parts.length ? parts.join(' · ') : 'Schedule to verify';
}
const FULL_DAYS = { Sun: 'Sunday', Mon: 'Monday', Tue: 'Tuesday', Wed: 'Wednesday', Thu: 'Thursday', Fri: 'Friday', Sat: 'Saturday' };
function fullDay(d) { return FULL_DAYS[d] ?? d; }
function displayTime(t) {
  const [h, m] = t.split(':').map(Number);
  const period = h >= 12 ? 'pm' : 'am';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return m === 0 ? `${h12}${period}` : `${h12}:${String(m).padStart(2, '0')}${period}`;
}

function dedupeMasterRows(rows, report) {
  const usable = rows.filter((r) => !r.skip);
  const skipped = rows.filter((r) => r.skip);
  const groups = new Map();
  for (const row of usable) {
    const key = `${row.state}|${row.sport}|${row.name.toLowerCase()}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  const kept = [];
  for (const [key, group] of groups) {
    if (group.length === 1) { kept.push(group[0]); continue; }
    const best = group.find((r) => r.published) ?? group[0];
    kept.push(best);
    for (const dup of group) {
      if (dup !== best) {
        report.duplicatesSkipped.push({
          key, kept: best.importSource, skipped: dup.importSource,
          reason: `duplicate of "${best.name}" (${best.state}/${best.sport}) on another sheet`,
        });
      }
    }
  }
  return { kept, skipped };
}

async function fetchCatalogue(db) {
  const [venueSnap, programSnap] = await Promise.all([
    db.collection('venues').get(),
    db.collection('programs').get(),
  ]);
  const venues = venueSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  const programs = programSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  return { venues, programs };
}

function planVenue(row, venues, createdThisRun) {
  const match = matchVenue({ venueName: row.venueName, state: row.state, suburb: row.suburb }, [
    ...venues,
    ...createdThisRun,
  ]);
  return match;
}

function buildVenueDoc(row, geocodeResult, key) {
  return {
    name: row.venueName || `${row.name} (venue to verify)`,
    address: row.address ?? '',
    suburb: row.suburb,
    postcode: '',
    state: row.state,
    lat: geocodeResult.lat,
    lng: geocodeResult.lng,
    photoUrl: '',
    isDemo: false,
    revision: 1,
    importKey: key,
    importSource: row.importSource,
    importedAt: 'SERVER_TIMESTAMP',
  };
}

/** `isUpdate` deliberately omits coachUids/coachNames/notes/photoUrl/
 * capacity/registrationStatus entirely -- these writes always use
 * {merge:true} (see applyWrites), so omitting a field preserves whatever
 * is already on the existing document instead of overwriting it with a
 * blank default. A brand-new program has no existing values to protect,
 * so those fields are included with sensible defaults. */
function buildProgramDoc(row, venueId, venueDoc, key, isUpdate) {
  const base = {
    name: row.name,
    sport: row.sport,
    status: row.published ? 'active' : 'draft',
    needsVerification: true,
    venue: {
      name: venueDoc.name, address: venueDoc.address, suburb: venueDoc.suburb,
      postcode: venueDoc.postcode, state: venueDoc.state, lat: venueDoc.lat, lng: venueDoc.lng,
    },
    timezone: 'Australia/Sydney',
    scheduleText: scheduleTextFor(row),
    importKey: key,
    importSource: row.importSource,
    importedAt: 'SERVER_TIMESTAMP',
  };
  if (isUpdate) return base;
  return { ...base, coachUids: [], notes: '', photoUrl: '', capacity: null, registrationStatus: 'open' };
}

function operationalDocFor(row, key) {
  const op = row.operational ?? {};
  const fields = {
    scName: op.scName ?? null, coachName: op.coachName ?? null, coachNumber: op.coachNumber ?? null,
    contactName: op.contactName ?? null, contactNumber: op.contactNumber ?? null, contactEmail: op.contactEmail ?? null,
    communityContact: op.communityContact ?? null, notes: op.notes ?? null, howItsGoing: op.howItsGoing ?? null,
    equipmentNeeded: op.equipmentNeeded ?? null, issues: op.issues ?? null, whatsapp: op.whatsapp ?? null,
    attendance: op.attendance ?? null, subsidised: op.subsidised ?? null,
    rawTime: row.rawTime ?? null, rawStartDate: row.rawStartDate ?? null,
    schedule: op.schedule ?? null,
    importKey: key, importSource: row.importSource, importedAt: 'SERVER_TIMESTAMP',
  };
  const hasContent = Object.entries(fields).some(([k, v]) => !['importKey', 'importSource', 'importedAt'].includes(k) && v != null && v !== '');
  return hasContent ? fields : null;
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true });
  const report = {
    generatedAt: new Date().toISOString(), mode: apply ? 'apply' : 'dry-run',
    venuesMatched: 0, venuesCreated: 0, venuesReview: 0,
    programsCreated: 0, programsUpdated: 0, programsMatchedUnchanged: 0, programsReview: 0,
    published: 0, unpublished: 0,
    missingCoordinates: 0, missingPhotos: [],
    needsReview: [], duplicatesSkipped: [], lowConfidenceGeocodes: [],
    plannedWrites: [],
  };

  const app = initializeApp({ projectId: PROJECT_ID }, `programs-import-${Date.now()}`);
  const db = getFirestore(app);
  const { venues: existingVenues, programs: existingPrograms } = await fetchCatalogue(db);

  const masterRows = parseMasterSpreadsheet(MASTER_PATH);
  const universityRows = parseUniversityMatrix(MATRIX_PATH).filter((r) => !r.skip);
  const { kept: dedupedMaster, skipped: skippedMaster } = dedupeMasterRows(masterRows, report);
  const allRows = [...dedupedMaster, ...universityRows];

  for (const row of skippedMaster) {
    report.needsReview.push({ row: row.importSource, reasons: row.review.map((r) => r.reason) });
  }

  const geocoder = new Geocoder({ cachePath: GEOCODE_CACHE, log: (m) => console.error(m) });
  const createdVenuesThisRun = [];
  const createdProgramsThisRun = [];

  for (const row of allRows) {
    if (row.review?.length) {
      for (const r of row.review) report.needsReview.push({ row: row.importSource, reasons: [r.reason] });
    }
    // A blank venue name isn't just "less data to work with": without it,
    // neither venue-fuzzy-matching nor the program venue+day fallback has
    // anything to compare against, and two completely unrelated rows that
    // both happen to have no venue name would otherwise mint the exact
    // same degenerate venue ID ("-nsw") and silently collide. Found this
    // by inspecting the dry run's own planned writes for duplicate IDs
    // before ever applying anything -- see docs/import/programs-mapping.md.
    if (!row.venueName) {
      report.needsReview.push({
        row: row.importSource,
        reasons: [
          row.address
            ? 'no venue name given (only an address) -- matching by address alone is unreliable; check by hand whether this is a new venue or an existing program under a different name'
            : 'no venue name or address at all -- cannot create a program without a venue',
        ],
      });
      continue;
    }

    const venueMatch = planVenue(row, existingVenues, createdVenuesThisRun);
    let venueId, venueDoc, venueIsNew = false;
    if (venueMatch.status === 'matched') {
      report.venuesMatched++;
      venueId = venueMatch.id;
      venueDoc = existingVenues.find((v) => v.id === venueId) ?? createdVenuesThisRun.find((v) => v.id === venueId);
    } else if (venueMatch.status === 'review') {
      report.venuesReview++;
      report.needsReview.push({
        row: row.importSource,
        reasons: [`venue "${row.venueName}" is a near-match (score ${venueMatch.score.toFixed(2)}) for existing venue ${venueMatch.candidateId} ("${venueMatch.name}") -- not auto-applied`],
      });
      continue;
    } else {
      venueIsNew = true;
      venueId = venueMatch.id;
      const geo = row.venueName || row.address
        ? await geocoder.geocodeVenue({ name: row.venueName, address: row.address, suburb: row.suburb, state: row.state })
        : { lat: null, lng: null, geocodeConfidence: 'none' };
      if (geo.lat == null) {
        report.missingCoordinates++;
        if (geo.geocodeConfidence !== 'none') {
          report.lowConfidenceGeocodes.push({ venueId, venueName: row.venueName, reason: geo.geocodeConfidence });
        }
      } else if (geo.geocodeConfidence === 'low') {
        report.lowConfidenceGeocodes.push({ venueId, venueName: row.venueName, reason: 'low' });
      }
      const key = hashImportKey([row.importSource.file, row.importSource.sheet, row.venueName, row.state]);
      venueDoc = buildVenueDoc(row, geo, key);
      venueDoc.id = venueId;
      venueDoc.geocodeConfidence = geo.geocodeConfidence;
      createdVenuesThisRun.push(venueDoc);
      report.venuesCreated++;
      report.missingPhotos.push({ id: venueId, name: venueDoc.name, address: venueDoc.address });
      report.plannedWrites.push({ type: 'venue-create', id: venueId, data: venueDoc });
    }

    const programMatch = matchProgram(
      { name: row.name, state: row.state, sport: row.sport, venueName: row.venueName, day: row.day },
      [...existingPrograms, ...createdProgramsThisRun],
    );

    let programId;
    if (programMatch.status === 'review') {
      report.programsReview++;
      report.needsReview.push({
        row: row.importSource,
        reasons: [programMatch.reason + (programMatch.candidateId ? ` (candidate: ${programMatch.candidateId})` : '')],
      });
      continue;
    }
    if (programMatch.status === 'matched' && programMatch.reviewed) {
      report.programsMatchedUnchanged++;
      programId = programMatch.id;
    } else {
      programId = programMatch.id;
      const isUpdate = programMatch.status === 'matched';
      const key = hashImportKey([row.importSource.file, row.importSource.sheet, row.venueName, row.day ?? '', row.startTime ?? '']);
      const programDoc = buildProgramDoc(row, venueId, venueDoc, key, isUpdate);
      if (programMatch.status === 'new') {
        report.programsCreated++;
        createdProgramsThisRun.push({
          id: programId, sport: row.sport, isDemo: false, needsVerification: true,
          venue: { name: row.venueName, state: row.state }, scheduleText: programDoc.scheduleText,
        });
        report.plannedWrites.push({ type: 'program-create', id: programId, data: programDoc });
      } else {
        report.programsUpdated++;
        report.plannedWrites.push({ type: 'program-update', id: programId, data: programDoc });
      }
      if (row.published) report.published++; else report.unpublished++;
    }

    const opDoc = operationalDocFor(row, hashImportKey([row.importSource.file, row.importSource.sheet, 'operational', programId]));
    if (opDoc) report.plannedWrites.push({ type: 'program-operational', id: programId, data: opDoc });
    if (venueIsNew) {
      const venueOpDoc = operationalDocFor(row, hashImportKey([row.importSource.file, row.importSource.sheet, 'venue-operational', venueId]));
      if (venueOpDoc) report.plannedWrites.push({ type: 'venue-operational', id: venueId, data: venueOpDoc });
    }
  }

  await geocoder.save();
  await writeReports(report);

  if (apply) {
    await applyWrites(db, report);
  } else {
    console.log('DRY RUN -- no Firestore writes made. See docs/import/dry-run-report.md');
  }
  console.log(JSON.stringify({
    venuesMatched: report.venuesMatched, venuesCreated: report.venuesCreated, venuesReview: report.venuesReview,
    programsCreated: report.programsCreated, programsUpdated: report.programsUpdated,
    programsMatchedUnchanged: report.programsMatchedUnchanged, programsReview: report.programsReview,
    published: report.published, unpublished: report.unpublished,
    missingCoordinates: report.missingCoordinates, missingPhotos: report.missingPhotos.length,
    needsReview: report.needsReview.length, duplicatesSkipped: report.duplicatesSkipped.length,
    lowConfidenceGeocodes: report.lowConfidenceGeocodes.length,
  }, null, 2));
}

async function writeReports(report) {
  await writeFile(`${OUT_DIR}/dry-run.json`, JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  const md = [
    `# Programs import -- ${report.mode} (${report.generatedAt})`, '',
    '## Counts', '',
    `- Venues matched to an existing document: ${report.venuesMatched}`,
    `- Venues created: ${report.venuesCreated}`,
    `- Venues sent to review (fuzzy match, not applied): ${report.venuesReview}`,
    `- Programs created: ${report.programsCreated}`,
    `- Programs updated (existing draft, not yet human-reviewed): ${report.programsUpdated}`,
    `- Programs matched but left untouched (already human-reviewed): ${report.programsMatchedUnchanged}`,
    `- Programs sent to review (ambiguous match): ${report.programsReview}`,
    `- Published (active): ${report.published}`,
    `- Unpublished (draft): ${report.unpublished}`,
    `- Missing coordinates: ${report.missingCoordinates}`,
    `- Venues needing photos: ${report.missingPhotos.length}`,
    `- Rows needing review: ${report.needsReview.length}`,
    `- Duplicate rows skipped: ${report.duplicatesSkipped.length}`,
    `- Low-confidence geocodes: ${report.lowConfidenceGeocodes.length}`,
    '',
  ].join('\n');
  await writeFile(`${OUT_DIR}/dry-run-report.md`, md, { mode: 0o600 });

  const csv = (rows, columns) => [columns.join(','), ...rows.map((r) => columns.map((c) => JSON.stringify(r[c] ?? '')).join(','))].join('\n') + '\n';
  await writeFile(`${OUT_DIR}/needs-review.csv`, csv(
    report.needsReview.map((r) => ({ file: r.row?.file, sheet: r.row?.sheet, row: r.row?.row, reasons: r.reasons.join('; ') })),
    ['file', 'sheet', 'row', 'reasons'],
  ));
  await writeFile(`${OUT_DIR}/venues-needing-photos.csv`, csv(report.missingPhotos, ['id', 'name', 'address']));
}

async function applyWrites(db, report) {
  const rollback = [];
  for (const write of report.plannedWrites) {
    const collection = {
      'venue-create': 'venues', 'program-create': 'programs', 'program-update': 'programs',
      'program-operational': 'programOperational', 'venue-operational': 'venueOperational',
    }[write.type];
    const ref = db.collection(collection).doc(write.id);
    const existing = await ref.get();
    rollback.push({ path: ref.path, existed: existing.exists, before: existing.exists ? existing.data() : null });
  }
  await mkdir('backups', { recursive: true });
  await writeFile(`backups/programs-import-rollback-${Date.now()}.json`, JSON.stringify(rollback, null, 2) + '\n', { mode: 0o600 });

  for (let i = 0; i < report.plannedWrites.length; i += BATCH_LIMIT) {
    const slice = report.plannedWrites.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const write of slice) {
      const collection = {
        'venue-create': 'venues', 'program-create': 'programs', 'program-update': 'programs',
        'program-operational': 'programOperational', 'venue-operational': 'venueOperational',
      }[write.type];
      const ref = db.collection(collection).doc(write.id);
      const data = { ...write.data };
      delete data.id;
      delete data.geocodeConfidence;
      if (data.importedAt === 'SERVER_TIMESTAMP') data.importedAt = FieldValue.serverTimestamp();
      batch.set(ref, data, { merge: write.type === 'program-update' || write.type.endsWith('operational') });
    }
    await batch.commit();
  }
  console.log(`Applied ${report.plannedWrites.length} writes in ${Math.ceil(report.plannedWrites.length / BATCH_LIMIT)} batch(es).`);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
