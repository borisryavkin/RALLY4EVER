# Approved implementation plan

Approved 17 November 2026, with subsequent instruction to stop at the end of stage 3. All development is local/emulated; no production access, paid-service activation or schema migration is authorized.

1. **Done:** independent app Git repository, `main` baseline `071698b` (`baseline: prototype as audited`), branch `feature/qr-attendance`. Parent Flutter SDK repository left alone.
2. **Done:** behavior-preserving cleanup of nine analyzer findings, commit `3a9b5b0`. Before: analyzer exit 1/nine info findings; one Flutter test passed. After: analyzer clean; same test passed. This commit changes only `lib/main.dart`.
3. **Ready for review:** data model; emulator-only Firebase configuration; shared Auth/role service contracts; owner/coach/admin Firestore rules; indexes; repeatable emulator seed; Dart model/guard tests and emulator rules/Auth tests. No new UI. See `DATA_MODEL.md`, `SETUP.md` and `firestore.rules`. **Pause here for review.**
4. **Next, after approval:** TypeScript Cloud Functions for verified identity provisioning, atomic normalized-email lookup/create, rotating event QR issuance, checkIn server validation, assigned-coach confirmation/rejection/correction and walk-ins. Dry-run merge script with `mergedInto`; two-coach identity races and merge tests. Verify window, distance, secret, consent, duplicates and error messages. Pause after the rules/functions milestone.
5. Participant flow: connect actual Auth and Firestore event instances; replace hardcoded coach email and single-session routing; persistent profile, Count me in, actual scan format, signed current forms, pending/waiting/confirmed states. Keep discovery/map/location/help. No prototype local check-in path should bypass the callable once integration begins.
6. Coach console: My events, real event-specific QR, roster and filters, confirmation queues, confirm all on time, reasoned corrections, existing-profile-first walk-ins and alerts. **Pause after coach console for review.**
7. Lightweight no-app Hosting check-in; verified email ownership; same callable; app-download links; deep-link configuration.
8. Notifications and feedback: FCM token lifecycle, coach inbox/push, event-specific routing, five-minute feedback selection at end +40 minutes for confirmed attendees only, dedupe/retry, rating/tags/comment. Document replacement of the current intent-triggered local reminder.
9. Browser admin: `/admin` role gate, event/coach feedback aggregation, intent vs actual counts, CSV, merge workflow and form versions.

After each stage run `flutter analyze`, `flutter test`, applicable Functions unit tests and Auth/Firestore emulator tests. Commit small reviewable units and update `CHANGELOG.md`. Keep audit history in `AUDIT.md`, with implementation status appendices instead of rewriting past findings as if they were already implemented at audit time.

No Blaze upgrade, domain purchase, SMS, developer-account fee or production deployment now. Before a paid action provide purpose, current AUD estimate, free alternative and request approval. Total budget AUD $100; set AUD $20 alert only with authorized billing setup before any eventual billed deployment. Alerts do not cap spending. Ask before destructive actions or real-data changes; migration scripts must default to dry-run.
