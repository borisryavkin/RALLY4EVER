#!/usr/bin/env node
// Offline dry-run only. Deliberately has no credentials or live apply path.
import {readFile} from 'node:fs/promises';
import {planProfileUpgrade} from './profile-schema.mjs';

const [path, ...extra] = process.argv.slice(2);
if (!path || extra.length) throw new Error('Usage: node scripts/preview-profile-upgrade.mjs /private/profile-snapshot.json (dry-run only)');
const rows = JSON.parse(await readFile(path, 'utf8'));
if (!Array.isArray(rows)) throw new Error('Expected [{profile, contact}] snapshot array');
const counts = {dryRun: true, total: rows.length, upgrade: 0, unchanged: 0, merged: 0, needsReview: 0};
for (const row of rows) {
  try {
    const plan = planProfileUpgrade(row.profile, row.contact ?? null);
    counts[plan.skipped ? 'merged' : plan.changed ? 'upgrade' : 'unchanged']++;
  } catch {
    counts.needsReview++;
  }
}
// No names, emails, mobile numbers or emergency contacts go into console logs.
console.log(JSON.stringify(counts, null, 2));
if (counts.needsReview) process.exitCode = 2;
