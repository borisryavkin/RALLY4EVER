# Legacy member migration — design, not executed

No legacy backend export, API credentials, schema or old Admin app source has been supplied. The audited baseline prototype has local JSON program assets and remote OpenStreetMap tiles, without a member backend API or persistent accounts. This is not evidence that the separately distributed legacy apps have no backend. Obtain their source/configuration or a sanitized export before implementing an importer. Do not invent legacy field mappings or copy the demo seed into a real project.

## Proposed mapping

| Legacy record | New model | Decision |
|---|---|---|
| Member / coach person | `users/{canonicalUid}` | One canonical profile per verified normalized email. Preserve source IDs in a restricted migration map. Name, mobile, emergency details and injuries map only after schema review. |
| Email | `emailIdentities/{normalizedEmail}` | Trim and lowercase using the existing normalizer; never strip plus tags or provider dots. Identity ownership must be verified; an email supplied by a coach is not proof of ownership. |
| Login | Firebase Auth with canonical UID | Import password hashes only if supported and approved. Otherwise require a verified sign-in/reset flow. Never use the emulator fixture password for members. Google Workspace accounts retain a single canonical profile. |
| Coach/admin privileges | Trusted admin-issued claims + protected profile fields | Review membership explicitly; never infer privilege from email domain. Assign `events.coachUids` separately. |
| Program/session | `events/{eventId}` | Stable source-to-target map, explicit venue coordinates, timezone and start/end timestamps. No secrets from old QR codes are reused. |
| Registration/intention | `rsvps/{eventId}_{uid}` | Intent only; source and cancellation history retained. Do not count registrations as attendance. |
| Actual attendance | `checkins/{eventId}_{uid}` | Only proven attendance becomes confirmed. Preserve original time/source and uncertainty; missing coordinates are not fabricated as a scan. Review legacy import schema before applying. |
| Signed forms | `consents/{uid}_{formId}` | Carry over only matching, documented form versions and evidence. Otherwise prompt for the current version. |
| Feedback | `feedback/{eventId}_{uid}` | Resolve duplicate event/person records by a reviewed policy; preserve originals in the encrypted export. |
| Duplicate profiles | `mergedInto` + `mergeAudits` | Choose a canonical UID, rewrite related IDs transactionally with collision handling, keep a tombstone and complete audit; never delete source evidence. |

See [DATA_MODEL.md](DATA_MODEL.md), [FUNCTIONS.md](FUNCTIONS.md) and the existing emulator-only `scripts/merge-profiles.mjs`. That script is not a production importer.

## Dry-run importer design

Proposed CLI (not implemented): `node scripts/import-legacy.mjs --input /secure/export.json --project APPROVED_PROJECT --dry-run --report /secure/report.json`.

1. Read an immutable, encrypted, access-controlled export; record SHA-256 and schema version. Default to dry-run. Reject unrecognized fields/types, ambiguous local dates, malformed emails, privileged records and missing provenance into a review queue.
2. Build a deterministic normalized-email index across all coaches and existing Firebase identities. Concurrent creation must use the same transactional identity reservation as `registerIdentity`. Missing/shared/family emails and contradictory identities require human resolution; no automatic merges based only on names or phone numbers.
3. Generate stable UID/event maps, counts, duplicate groups, field conflicts, RSVP/check-in ID collisions, consent version gaps and proposed merge decisions. Redact health/contact data from ordinary logs. A repeat dry-run must produce the same operation IDs and proposed changes.
4. Exercise the plan against synthetic data in isolated emulators first: cross-coach duplicate, case-variant email, shared email, merged user login, conflicting attendance, forms and rerun/idempotency. Reconcile counts and per-event attendance totals with source.
5. Before any real writes, obtain explicit approval for the exact project, source hash and plan hash. A future `--apply --approved-plan ...` path must refuse a stale plan, back up every touched record, use preconditions/transactions and bounded batches, and record a checkpoint and before/after hashes for each operation. Never change Auth providers or send mass emails as an import side effect.
6. Reconcile each source record as imported, merged, excluded or unresolved. Prove that a coach-added RSVP is visible to the same member UID and that duplicate registrations under two coaches resolve to one identity. Only then claim legacy duplication is fixed.

## Cutover and rollback

During internal testing, isolate synthetic staging records from all live members. Do not change the old backend, DNS, auth providers or public app version. Test the same-ID app on dedicated tester devices: a tester install can replace their existing installed app.

For a later approved migration, snapshot both systems, establish a short write freeze or explicitly logged delta replay, and keep the old backend available throughout reconciliation. Capture existing claims, identity maps, form versions and changed documents. Do not overwrite the legacy store.

Rollback restores only migration-owned operations whose after-hashes still match, in reverse dependency order; restore updated documents and claims from before-images, quarantine newly provisioned accounts, preserve audit evidence, and never remove later legitimate member writes. Stop and request review on conflicts. Auth imports/password changes are not generally reversible from Firestore backups; retain a separately approved Auth recovery plan before applying. A database rollback does not roll back an installed binary: expire/remove the tester build, restore the previously approved client, and direct testers back to the unchanged legacy service. A new store build would require a higher build number.

No production migration or deletion is authorized by this design.

## Confirmed first onboarding-page denial — 19 November 2026

Read-only inspection of the real `rally4ever-3adaf` Rules release found it was last updated on 17 November (`2026-11-17T12:10:35.563779Z`). It lacks `private/contact` and `photoUpdatedAt`, and expects legacy `currentActivity`/`referral`/single-string cultural answers plus phone/emergency contact on the main profile. The new first-page save sends name/postcode and a normalized `about` map even when everything is prefilled. This is a schema/rules mismatch, not a request for the member to re-enter correct details.

Updating only rules is insufficient: current `validProfile` also rejects legacy top-level phone/contact fields. Existing records need a coordinated migration, and new registrations must use the matching updated `registerIdentity` implementation. New check-in/add-walk-in/roster code must read the private contact model too. Do not loosen ownership, role, verification or attendance rules to work around this.

Prepared tools (not run against real member data):

- `scripts/profile-schema.mjs`: pure planner; preserves UID, email, role, name, postcode, age, timestamps and original rollback values. Moves phone/emergency contact, converts recognized legacy answers, skips merged profiles, and stops conflicting/unsupported fields for review. No accounts or duplicate profiles are created.
- `scripts/preview-profile-upgrade.mjs`: offline dry-run of `[{profile, contact}]` snapshot JSON. Console output contains counts, not names, emails or contact details.
- `scripts/migrate-profile-schema.mjs`: default read-only preview; explicit project/environment guards, maximum 1000 profiles, all-conflict preflight, exclusive mode-600 backup outside git, per-profile transactions, stale-data checks and `mergeAudits` entries. A failure can stop after some transactions; retain the backup to recover those records. It does not change Auth providers, claims, event IDs, attendance or RSVPs.

Free local preview (offline input; no Firebase requests):

```sh
node scripts/preview-profile-upgrade.mjs /private/path/profile-snapshot.json
```

Against the disposable local emulators (default dry-run):

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
node scripts/migrate-profile-schema.mjs --project=demo-rally4ever --dry-run
```

Real-project rollout requires separate owner approval before deployment/migration:

1. Verify project/billing and budget alert (AUD $20 alert, AUD $100 total cap). Use existing credentials only. Read-only preview first, count affected accounts, and stop on conflicts. This preview reads up to 1000 profile/contact pairs and may consume Firestore read quota.
2. Back up the live rules release and existing deployed Functions versions/artifacts. Review/deploy only the compatible Functions and Firestore rules; **never** bare `firebase deploy`, which could also enable Storage deployment. Do not enable Storage, SMS or a new service. Allow a short internal-testing maintenance window; old clients must update before editing migrated profiles.
3. Apply the reviewed migration with a private backup, then test the exact prefilled first-page save, subsequent private-contact page, verification, and participant/coach permissions. Sign out/in to refresh client Auth state. Ensure existing event/coach contact-visibility relationships are reviewed before granting any additional coach access.
4. If rollback is needed, explicitly authorize it. Each record is restored only if its current hash still matches the migration output; later edits are refused for manual review rather than overwritten. Previously unchanged/unapplied rows are skipped. Restore matching old backend/rules artifacts if reverting the model; do not leave a mixed deployment.

Commands for a reviewed real rollout (documentation only; **not executed**):

```sh
# Requires existing authorized Application Default Credentials; never commit credentials.
node scripts/migrate-profile-schema.mjs --staging --project=rally4ever-3adaf --dry-run

# STOP: only after reviewing preview/counts and obtaining migration approval.
node scripts/migrate-profile-schema.mjs --staging --project=rally4ever-3adaf \
  --apply --confirm-project=rally4ever-3adaf \
  --backup=/private/path/r4e-profile-v2-backup.json

# STOP: rollback also needs explicit approval; never run automatically.
node scripts/migrate-profile-schema.mjs --staging --project=rally4ever-3adaf \
  --apply --confirm-project=rally4ever-3adaf \
  --rollback=/private/path/r4e-profile-v2-backup.json
```

Planning allowance for a small staging rollout: **AUD $0–5 incremental**, not a guaranteed quote or hard billing cap. Migration reads/writes and Functions build/artifact/usage can be billed outside included quotas. Verify the existing plan and alert before execution; no billing upgrade is authorized by these instructions. Free alternative: leave real staging unchanged and use the emulator regression. See [Firebase pricing](https://firebase.google.com/pricing) and [Functions deployment costs](https://firebase.google.com/docs/functions/faq-and-troubleshooting).

Validation: `npm run test:catalogue` includes the legacy-prefilled first-page denial/success case, preserved identity/age/postcode, ownership/role denials, migration dry-run/apply/idempotency, exact timestamp rollback and refusal to overwrite a later edit. All use isolated demo emulator ports, not live data or the running development emulator.
