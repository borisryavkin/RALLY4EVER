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
