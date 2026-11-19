# Hosted Rally4Ever administration

URL: **https://rally4ever-admin-3adaf.web.app**. Firebase project `rally4ever-3adaf`, Hosting target `admin`, site `rally4ever-admin-3adaf`. The default participant Hosting site is unchanged. Navy background `#001751`, Inter text, Jellee headings and the existing Rally4Ever symbol distinguish this site from the participant app.

## Access and exact steps

1. Open the URL. Use **Continue with Google** or the email/password form with an existing verified account. Google accounts can set an app password using the reset link; no second profile is created here. Provider collisions require the existing password before linking the pending Google credential, with matching email enforced.
2. The site checks the `role=admin` custom claim. A participant/coach sees **No access**. Functions also require the admin claim and an active, protected admin profile. Demoting the profile denies stale tokens immediately. Domain membership grants nothing.
3. **Sessions**: filter sport/status/venue-local date/suburb/demo. Every requested Firestore field is a table column, with horizontal scrolling and a pinned action column. **Edit** opens an editor inline under the row. **New session**, **Duplicate** (draft), **Publish/Unpublish**, **Cancel** and CSV are available. Select coaches in the editor. `bookedCount` is derived from active RSVPs; it cannot be entered. Server timestamps and revisions are automatic. Started/scanned sessions retain their original time/location/form context; notes and other permitted operational fields remain editable. Historic invalid staff/form references are preserved on unrelated edits; new assignments/publication validate them.
4. **Programs**: search/filter draft/published/archived, edit, publish/unpublish/archive. Published maps to the existing Firestore status `active`. **Generate sessions** → date range/weekday/venue-local time/duration → **Preview dates** → **Create**. Existing program/date pairs are skipped; deterministic IDs and revision checks prevent concurrent overwrites. Up to 52 future dates per preview. Each successful creation is audited; if a later date fails, refresh and preview again rather than repeating completed writes.
5. **Venues**: includes both stored venue documents and distinct legacy venues embedded in programs/sessions. **New venue** or **Edit / upload photo** → enter a unique venue code/address/coordinates → drop or choose a photo → adjust 16:9 crop/zoom/position → **Save venue and photo**. Output is a compressed 1600×900 JPEG under `venues/{venueId}/{uuid}.jpg`. `photoUrl` is a `gs://` reference; previews use authenticated SDK reads. The finalizer removes Firebase bearer download tokens from managed venue images. Saving propagates photos to linked programs/sessions; started sessions retain original coordinates. Failed post-upload saves may leave an unreferenced object for reviewed cleanup; no automatic data deletion occurs.
6. **Bulk venue photos**: name JPEG/PNG/WebP files by unique venue code, such as `BONDI-01.jpg`. Drop files or **Choose files**, review cropped previews and matched names, then **Upload matched photos** and confirm. Unknown/duplicate codes or incomplete venue details block saving. Bulk uses centre crops; use the single editor for custom crops. A partial failure retains completed saves; refresh before retrying.
7. **Users**: email-prefix search, choose participant/coach/admin, **Apply role**, confirm. Uses audited `setUserRole`, with last-admin/self-demotion protections and verified-email checks. The user refreshes their token after a role grant. Coach assignment is under **Sessions → Edit → Coaches**.
8. **Attendance**: choose a session; filter all/counted-in/checked-in/walk-ins. Scan time, distance, status and separate intent/attendance columns remain visible. Pending check-ins can be confirmed/rejected. **Export CSV** exports the current filtered view and escapes spreadsheet formulas. Large rosters explicitly warn at the existing 500-record service limit; request a complete export before reporting such totals.
9. **Sessions → Remove demo data → Preview removal**: shows counts and every document path for flagged sessions, programs and venues. Confirm the exact selection to remove it. The transaction rejects changed selections or links from non-demo records, and backs up every removed document to `demoRemovalBackups` before deletion. No users, Auth accounts, check-ins or RSVPs are deleted. Maximum 200 catalogue documents per reviewed operation. **No removal was applied to the real project during verification.**

## Collections and safeguards

- `events`: all requested fields, including venue, program, coaches, timezone, dates, capacity/derived count, geofence, form IDs, notes, image, demo metadata and revision; `createdAt`, `updatedAt`, `updatedBy` are server generated.
- `programs`: existing model, status `draft|active|archived`; revisions and catalogue audits preserved.
- `venues/{id}`: `id`, unique `code`, `name`, `address`, `suburb`, `postcode`, `state`, `lat`, `lng`, `photoUrl`, `isDemo`, `revision`, `createdAt`, `updatedAt`, `updatedBy`.
- `catalogueAudits`: actor/time/before/after for session/program/venue edits; venue records include linked-record snapshots. Demo-removal audits include exact paths/counts.
- `demoRemovalBackups/{id}`: original `path`, full original `before` document, `actorUid`, `removedAt`, optional `restoredAt`.
- Existing `users`, `rsvps`, `checkins`, `roleAudits` retain their meaning. No identity migration is part of this deployment.

Only public Firebase client identifiers enter the JavaScript bundle. Admin credentials, private keys, service-account JSON and server secrets do not. Firestore/Storage rules check roles independently. Venue Storage writes require a verified admin claim plus protected profile; authenticated verified users can read. Images are capped at 5 MB and JPEG/PNG/WebP. Existing profile-photo owner/assigned-coach restrictions are retained. App Check is optional and has not been enabled; configure and monitor it before enforcement to avoid blocking existing installs.

Catalogue reads have an explicit 1000-record safety cap; large catalogues require pagination before further editing. Venue updates refuse more than 150 linked records to stay within transaction limits. These conditions produce clear errors rather than silently hiding records.

## Local build and targeted deployments

`config/staging.web.json` is ignored by Git. It contains only the registered web app's public Firebase SDK configuration. The build script copies an explicit allowlist of six identifiers and refuses another project or missing configuration.

```sh
npm --prefix web-admin ci
node scripts/build-admin.mjs
npm --prefix web-admin test
npm --prefix web-admin run dev
# http://localhost:57830 — uses real staging; sign in with an authorized admin.

firebase deploy --project rally4ever-3adaf --only hosting:admin
```

Never use bare `firebase deploy --only hosting`, which could deploy another site. Backend/rule updates are separate and scoped:

```sh
firebase deploy --project rally4ever-3adaf --only firestore:rules,storage
firebase deploy --project rally4ever-3adaf --only functions:attendance:adminCatalogue,functions:attendance:adminSaveSession,functions:attendance:adminSaveVenue,functions:attendance:adminRemoveDemo,functions:attendance:listUsers,functions:attendance:setUserRole,functions:attendance:saveProgram,functions:attendance:getEventConsole,functions:attendance:assignEventCoaches,functions:attendance:coachDecision
```

Browser callables have a public HTTP transport for preflight/Firebase tokens, but require verified Firebase Auth and authorization in their handler; unauthenticated calls return HTTP 401, never catalogue data. Firebase Auth authorized domains includes the admin Hosting origin. The existing same-email Auth setting/providers were not changed by this admin deployment.

Authenticated browser byte reads also need bucket CORS. The reviewed allowlist is [admin-storage-cors.json.example](../config/admin-storage-cors.json.example); it permits GET/HEAD for the listed app/dev origins, not public object access. Preserve any existing rules when applying it. The Storage service agent needs `roles/firebaserules.firestoreServiceAgent` for protected-profile lookups. This missing permission was enabled for `service-55117668228@gcp-sa-firebasestorage.iam.gserviceaccount.com`, with the previous IAM policy backed up locally. References: [Firebase cross-service permissions](https://firebase.google.com/docs/rules/manage-deploy#manage_permissions_for_cross-service) and [authenticated SDK downloads/CORS](https://firebase.google.com/docs/storage/web/download-files#cors_configuration).

## Recovery and manual steps

- Hosting rollback: Firebase Console → Hosting → select **rally4ever-admin-3adaf** → release history → roll back the admin release. This does not affect the default site.
- Catalogue edits: inspect their audit before applying a compensating edit through the UI. Revisions continue increasing; never blindly overwrite a newer document from an old backup.
- Demo removal: inspect `demoRemovalBackups`, choose one backup ID, dry-run `node scripts/restore-demo-record.mjs BACKUP_ID`, then explicitly add `--apply` to restore. It refuses an existing target and preserves original Timestamp values. The read-only dry-run needs ADC access; never commit credentials. No restore/removal was run against real members.
- Local pre-verification catalogue backup: `backups/admin-web-before-proof-2026-11-19.json` (ignored, mode 0600). Original IAM and CORS backups: `backups/admin-web-before-storage-service-agent-iam.json`, `backups/admin-web-before-storage-cors.json`. Do not blindly restore an old entire IAM policy over subsequent changes.
- At initial verification, the real project had **no `forms` documents**. The editor lists available form IDs; new sessions default to currently configured forms, not nonexistent conduct/waiver IDs. Supply approved form text/versions before requiring them. Existing session form references are retained on unrelated edits. This task did not invent legal text or silently change existing requirements.
- Use `node scripts/check-admin-staging.mjs` for a localhost:57831 real-account verification. It records status codes/counts only under `/tmp`; tokens stay in memory. It must not be hosted publicly.
- Optional custom admin domain, App Check enforcement and invitation of additional admins remain manual choices. No paid domain, billing upgrade, SMS or store upload was performed.

Incremental deployment/testing allowance: **AUD $0–5 estimated**, subject to existing Firebase quotas and billing; no purchase or new plan was enabled. No additional site fee was paid. Retain the overall AUD $100 budget and AUD $20 alert requirement; this task has not independently verified the billing alert.

## Verification results

See the dated proof below for real account results and final counts. Tests cover claim/profile gates and revocation, full session field validation/revisions/audits, legacy coach/form preservation, venue propagation with original scan coordinates, exact demo previews/backups/reference protection, Storage admin-only writes/authenticated reads, timezone/DST, filters, CSV safety and bulk matching/crops.

### Real-project proof (19–20 November 2026)

The status-only receipt is [verification/web-admin.json](verification/web-admin.json); it contains no credentials or tokens.

- Existing owner Google sign-in produced a verified `role=admin` token. Hosted Sessions loaded 12 real session documents and 62 programs. The venue catalogue included legacy embedded venues, not just the new `venues` collection.
- Through the hosted **Sessions → Edit**, added a temporary verification note to `demo-tennis-bondi-now` (revision 1→2), then restored its original notes (2→3). Audits identify the actual admin. A newer revision appeared during cleanup; it was preserved, with only the original `catalogueManaged=false` compatibility flag restored in a separately audited correction (final observed revision 5). The editor now preserves that flag on legacy standalone sessions. Older installs retain their original RSVP policy. No session/program IDs were removed.
- Through hosted **Venues → New venue → Choose photo → crop preview → Save venue and photo**, created `ADMIN-VERIFY-20261119`, marked demo/test, with a clearly labelled verification image rather than a false venue photograph. Confirmed 1600×900 JPEG, 34,556 bytes, stored under that venue's ID. Authenticated preview displayed; finalization removed the bearer download token; anonymous read returned HTTP 403. No real court's photograph was replaced.
- Existing participant Google account saw **No access** on the hosted site. Actual Firebase ID-token requests returned HTTP **403 / PERMISSION_DENIED** for `adminCatalogue`, `adminSaveSession`, `adminSaveVenue`, `adminRemoveDemo`, `listUsers`, and `setUserRole`. Its Storage upload returned **403**. No role was changed for the checks. Unauthenticated admin calls returned **401 / UNAUTHENTICATED**.
- Before the test: 12 event documents, 62 program documents, 0 stored venues. Final snapshot: 12 events, 62 programs, 7 stored venues. This task created one explicitly labelled test venue; six other venue documents appeared concurrently and were preserved. The receipt records actual final counts rather than attributing concurrent writes to this work. Existing event/program IDs match the backup exactly. No demo cleanup, member deletion or profile migration was performed.
- Final checks: 48 isolated catalogue/rules tests plus 5 import/profile unit tests; 27 Functions emulator tests; 15 Functions unit tests; 8 Storage rules tests; 6 web helper tests; analyzer clean; 118 Flutter tests passed with one intentional emulator-only skip. Production web build and runtime dependency audit passed (zero reported vulnerabilities).
