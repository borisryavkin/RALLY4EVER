# Session and venue photos

Live admin: https://rally4ever-admin-3adaf.web.app (admin claim and protected profile required).

## How to test

Mobile, using the new native build:
1. Sign in as admin → **Me → Admin → Sessions → Edit / cancel / assign coaches** (standalone sessions say **Edit session / assign coaches**).
2. The **Photo** section is first. Choose **Change photo → Choose from library / Take photo**. Processing limits the long side to 1600 px and encodes JPEG quality 80. Upload progress and save errors appear in that section. The photo saves immediately with the session revision; other fields still use Save session.
3. **Use venue photo** resumes inheritance. **Remove photo** explicitly shows the neutral branded placeholder, even when the venue has a photo. Neither action deletes an image object.
4. **Me → Admin → Venues & photos → venue** changes/removes the shared venue image. Inheriting sessions update; session overrides stay unchanged.
5. Open Manly and Chatswood as a participant. Their stored photos are distinct court photos; the old hardcoded aerial image is no longer used. No unrelated image is substituted when a photo is absent.

Web:
1. Refresh the site to load the deployed JavaScript. **Sessions → Edit → Photo** supports choosing/dropping a file, crop preview, **Replace / Upload photo**, **Use venue photo**, and **Remove photo**. Existing session photo changes save immediately. Save a new session first before uploading its own photo.
2. **Venues → Edit / upload photo** supports drag/drop, crop, **Change photo / Replace**, **Remove photo**, and **Save venue**. The existing bulk preview/upload remains available.
3. Check that admin table times read like **Thu 19 Nov, 1:12 pm**, in the row's stated timezone. Mobile session fields are grouped under Photo, Venue, Time, Capacity and Notes.

## Model and security

Canonical shared image: `venues/{venueId}.photoUrl`. Session `photoUrl` is an override; `photoMode: venue` clears the override and inherits, while `photoMode: none` explicitly suppresses images. Without a mode, existing nonempty `photoUrl` is treated as an override. On venue updates, old copied URLs matching the embedded venue photo are treated as inherited. Canonical venue matching uses the explicit venue ID; legacy exact name/coordinate matching is used only if no ID exists. A different venue is never a fallback.

New public media URLs are tokenless Firebase Storage download URLs. Uploads use `sessions/{sessionId}/{timestamp}.jpg` or `venues/{venueId}/{timestamp}.jpg`. Old objects remain, permitting rollback by restoring references. Revision checks reject concurrent edits. Server timestamps and actor/before/after audits accompany changes; photos can be changed after a session has started without changing scan coordinates or attendance.

Existing bucket `rally4ever-3adaf.firebasestorage.app` was confirmed **AUSTRALIA-SOUTHEAST1**, REGIONAL. No bucket, region or paid plan was created. Existing Firebase billing applies to storage/requests/egress; this verification used one small test image. No purchase or store upload occurred.

`storage.rules`: venue/session images public read; create/update only verified admin claim AND current protected admin profile, supported MIME JPEG/PNG/WebP, maximum 5 MiB. Profile photos retain their private owner/assigned-staff rules. Public media contains no profile photo data. `adminSetPhoto` repeats admin checks and validates record/path/revision/image metadata; participants cannot save photo references through it.

## Proof and tests

Real project (`docs/verification/catalogue-photo-staging.json`): admin Storage upload 200; participant upload 403; unauthenticated download 200; admin photo-save callable 200 with revision 2; participant callable 403 / `admin-claim-required`. SHA-256 comparison confirms the rejected write did not alter the image. The synthetic QA venue/image is marked demo. The one new QA Auth/profile account was retained, returned to participant, refresh tokens revoked, and Auth disabled (`catalogue-photo-cleanup.json`). No existing profile or Auth user was modified or deleted.

Passed: Flutter analyze; 148 Flutter tests (one existing skip), including actual JPEG resize/invalid-image, fallback, photo controls and timezone formatting; 9 Storage emulator tests; 51 combined catalogue/rules emulator tests plus 5 source/profile tests; 16 function unit tests; 8 web helper tests; 10 release guards. Refreshed the two affected screenshot baselines intentionally. Hosting's live asset hash was compared to the built local asset.

Build receipts: `catalogue-photos-android21.json`, `catalogue-photos-android22.json`, `catalogue-photos-ios21.json`. Android 21 is retained as requested, but Play already contains a different uploaded code 21; upload the code 22 AAB. iOS uses the normal export plist. Neither store was uploaded to during this task.

## Backups and deployment

Before editing: `backups/session-photos-1795133120/` contains source/test snapshots, earlier artifacts, and the actual deployed Storage rules (`deployed-storage-rules.json`). `ios-workspace-state-before-repair.json` preserves the original Xcode cache metadata.

Before the isolated real-project writes: `backups/photo-probe-initial-1795134405237.json`, `photo-probe-role-before-1795134405237.json`, `photo-proof-1795134405237.json`, `photo-probe-before-revoke-1795134405237.json` (all local/ignored). Existing live court photos were inspected and retained. The demo audit found no stored bundled placeholder URLs needing removal; the bad aerial image was a client fallback, not those venue photos.

Only this real project was touched. Scoped deployments: Storage rules; attendance codebase `adminSetPhoto`, `adminSaveVenue`, `saveSession`; Hosting target `admin`. Default/check-in Hosting sites were not deployed. Image removal only clears references; restoring an earlier URL/revision through the admin endpoint is reversible. Never restore the temporary QA admin claim as a rollback action.
