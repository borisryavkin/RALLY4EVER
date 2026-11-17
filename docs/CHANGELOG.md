# Change log

## 2026-11-17 — participant UI and Google Workspace coach access

- Replaced fake email/social sign-in and static session routing with emulator-backed Auth, verified signup/email-link/Google sign-in, registerIdentity and published Firestore events. Preserved one canonical profile/UID across participant and coach views.
- Added S01–S24 participant screens: tiered persistent profile, separate intent/attendance states, RSVP/cancel, private first-name projection, strict event QR parsing, details/forms, waiting/confirmed/rejected, feedback, form/history profile and help. Retained discovery assets, sport/location selection, map and reusable widgets; made program assets portable and bundled Inter/Figtree/OFL fonts.
- Added server rate limits and one-time Firebase email-link proof for returning no-app identities with prior check-ins; new identities remain unverified pending walk-ins. Documented email-only/GPS risks and mandatory coach review evidence.
- Coach access now requires an admin-issued claim plus protected active gate; domain or profile role alone cannot grant it. Added admin-only user listing by email, audited coach grant/revoke and event assignment, and read-only coach arrivals showing scan time/distance/verification. Revoked coaches lose access even with a stale token.
- Added 26 screenshot goldens, UI state tests, rules/callable Workspace tests and a real browser emulator journey through RSVP, QR, details/forms, coach decision and visible confirmation. Manual native OAuth/camera/GPS/FCM setup remains in SETUP.md. No deployment, production changes or paid services.

- Validation: analyzer clean; 45 Flutter tests pass (browser-only test skipped in VM), 11 Functions unit tests, 18 rules/Auth tests, 27 Functions emulator tests, and the separate Chrome participant emulator test pass.

## 2026-11-17 — Functions stage: emulator-only backend

- Added TypeScript `registerIdentity`, `rotateEventSecret`, `checkIn`, `coachDecision`, `correctAttendance`, `addWalkIn`, and `mergeProfiles`. Runtime guards refuse non-emulator execution; no UI or deployment.
- Updated identity document IDs to literal normalized emails per the latest request (old stage-3 keys were hashes); updated fixture paths without touching real data. Transaction tests verify one profile across concurrent registration/candidate UIDs and two-coach walk-in creation. No claim about legacy backend duplicates.
- Check-in transaction enforces server time/geofence/QR/forms/details/deterministic attendance ID. Coach/admin decisions and reasoned corrections preserve original scan fields. Manual walk-ins keep unknown location/distance null; profile decoder supports nulls.
- Merges default to dry-run; apply requires a fresh unchanged plan by the same admin, refuses collisions/privileged profiles, preserves full originals in mergeAudits and leaves source profile with mergedInto. Added emulator-only dry-run CLI.
- Added real Firestore pending-check-in trigger and five-minute feedback job (+40 min, confirmed only, deterministic inbox dedupe, bounded selection, retry leases). Push transport is a local test double, not real FCM.
- Validation: Flutter analyzer clean; 6 Flutter tests, 10 Functions unit tests, 17 rules/Auth emulator tests and 20 Functions emulator tests pass under Node 24. Scheduler SDK handler is exercised against emulator data; CLI 15.36 cannot dispatch its v2 signature through Pub/Sub. No claim of automated wall-clock scheduler delivery or real device push.
- Functions package dependency audit reports zero vulnerabilities. Existing root CLI-tooling moderate advisories remain documented in SETUP.md. No paid services enabled, no production migration, no existing UI feature removed.

## 2026-11-17 — stage 3: data/security foundation

- Added `demo-rally4ever` Auth/Firestore emulator configuration, rules and composite index definitions. No deployment, billing or production access.
- Added user/event/intent/attendance models, explicit emulator-only initialization, normalized-email Auth repository with protected role precedence, and scoped read repositories. No UI is added or integrated yet.
- Added strict ownership/role boundaries, protected identity/role fields, separate intent/actual records, current-version consent and confirmed-attendee feedback validation. All attendance and QR-secret client writes remain denied, including admin; trusted callables follow in the next stage.
- Added repeatable seed (13 accounts, 3 events), local-only guards, Auth token integration and rules tests, model/guard tests. Tests verify canonical UID visibility for a seeded coach-added RSVP; concurrent duplicate prevention/merge remains for Functions, and no legacy bug-fix claim is made.
- Added schema/access review, approved plan and manual setup guide. Audit findings are retained historically.
- Validation: `flutter analyze` clean; `flutter test` passes 6 tests (including original welcome test); Auth/Firestore emulator suite passes 17 tests under Node 24.22.3 (15 rules scenarios plus 2 Auth/seed integration tests). Expected permission-denied logs come from negative assertions. No native Firebase runtime build or deployed-index validation performed.

## 2026-11-17 — stage 2: analyzer cleanup (`3a9b5b0`)

- Fixed five missing-brace lints, two deprecated radio properties via equivalent `RadioGroup` selection binding, unused callback wildcard naming, and optional `Help` widget key. Only `lib/main.dart` changed; no business behavior changed.
- Before: `flutter analyze` exit 1, nine info findings; `flutter test` passed (1).
- After: `flutter analyze` clean; `flutter test` passed (1).

## 2026-11-17 — stage 1: app repository (`071698b`)

- Created independent app Git boundary, baseline commit `baseline: prototype as audited`, then `feature/qr-attendance`. Parent Flutter SDK Git repository was not modified.
- Kept prototype source and audit; excluded build output, local credentials and signing keys. No existing feature deleted.
