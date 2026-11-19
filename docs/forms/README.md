# Approved legal forms

The four `.txt` files are the authoritative text pasted by Boris on 20 November 2026. The program introduction is excluded. Wording, punctuation, spelling, blank paragraph separators and spaces at the ends of text lines are preserved. Each file has one terminal newline. Do not regenerate these files from HTML: the pasted text supersedes the earlier extraction.

`manifest.json` records the reviewed UTF-8 SHA-256 hashes. The display component styles lines without rewriting their content. Conduct and waiver are mandatory; photo release and data collection are displayed alongside them and can be accepted individually.

Preview with `node scripts/publish-forms.mjs`. Publish with `node scripts/publish-forms.mjs --apply`. A changed body must use a new reviewed version (`--version=YYYY-MM-DD`), never overwrite an accepted version silently. The script backs up target documents before writes and compares every stored body to the file after writing. Existing app builds receive compatibility `content` and `formType` fields alongside canonical `body` and `id`.

Published in `rally4ever-3adaf`, version `2026-11-20`. Receipt: `docs/verification/forms-published.json`. Backup: `backups/forms-before-1795130926965.json` (local, ignored by Git).

Humanitix import: only Ultimo and UNSW venue programs. Reused `nsw-pickleball-ultimo`, created `humanitix-unsw-pickleball`, two venue records, and 36 published occurrences. Sydney timezone and actual published DST offsets are retained. No statewide listings were imported. Capacity is unknown and coaches are unassigned; no names or availability counts were invented. UNSW eligibility is currently enrolled students only. Reviewed coordinates were confirmed by Boris before import. Backup: `backups/humanitix-before-1795131033961.json`. Import script defaults to dry-run and retains existing imported sessions on repeat runs.

Verification: 16 function unit tests, 35 function emulator tests, 21 rules emulator tests, 119 Flutter tests (one existing skip), the new legal-rendering widget test and two source/import guards passed. Flutter analyze reports no issues. Updated Firestore rules and the `checkIn`/`addWalkIn` functions were deployed successfully. No native app was built or uploaded during this change.
