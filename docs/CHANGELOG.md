## Tester release preparation — 17 November 2026

- Preserved `org.rally4ever` on both platforms. Raised `1.0.1+2` to `1.0.1+5` after the owner confirmed TestFlight build 4 is highest; Android historical code/package reuse still needs confirmation because its old app was removed. No store records were changed.
- Added Android `emulator`/`staging` flavors, matching iOS shared schemes/configurations and Podfile mappings. Native preflight plus Dart guards reject real config in emulator artifacts and emulator/LAN flags in staging; staging is restricted to owner-specified candidate `rally4ever-3adaf`. No real Firebase configuration is checked into this preparation commit; concurrent ignored configs appeared later and were inspected only for project/flavor/placeholder status.
- Kept existing signing keys/settings; honored configured Android key password with PKCS12 fallback. Initial audit found an Apple project/export team mismatch (`7HGT5BT6KT` vs `565ZMX3G2X`); concurrent work aligned the original export plist to `7HGT5BT6KT`, which the separate internal export now follows. Added a separate local-export plist with `testFlightInternalTestingOnly=true`; the existing external TestFlight group `rally4ever` is explicitly excluded.
- Added HTTPS QR app-link declarations, associated-domain entitlements, strict queued deep-link handling through login, foreground location explanation and emulator-only HTTP/local-network configuration. Website association templates are unpublished and require actual signing prefixes/certificates.
- Added `MIGRATION.md` with source-schema limitations, canonical email/UID mappings, dry-run importer design, conflict review, reconciliation and rollback. Added `RELEASE.md` with exact local build and approval-gated upload commands, internal-only tracks, App Distribution alternative, manual prerequisites and AUD estimates.
- Validation: analyzer clean; 57 Flutter tests passed on the final shared working tree (including two concurrent repository error-message tests), one browser-only test skipped; three native build guard tests, five LAN tests and 14 Functions unit tests passed on the final shared working tree (including concurrent backend-guard updates). Xcode lists both schemes; Android emulator debug APK and iOS emulator simulator app built successfully and report `org.rally4ever`, `1.0.1`, build `5`. Native Gradle staging preflight correctly refuses missing configuration. Plist checks pass. This task performed no staging signing, physical-device verification, store upload, deployment, provider change, new key, billing change or payment. Concurrent staging IPA/AAB files were found and statically inspected; their source freshness and runtime behavior remain unverified. Emulator integration suites were not rerun against the occupied development instance to preserve its restored fake data.
- Remaining gates: actual owning Apple team, Firebase project data classification/app configs, native OAuth and link-domain setup, Android package availability/highest historical code/certificate, staging backend deployment readiness and explicit cost/upload approvals. Existing user changes to `pubspec.lock` and concurrent backend/seed/signing/error-handling changes remain outside these commits. RELEASE.md distinguishes those changes and deployment notes from this task.

# Change log

# Change log

## 2026-11-17 — opt-in development LAN testing

- Kept default emulator bindings on loopback. Added an explicit LAN_TESTING=true / LAN_HOST launcher that validates an assigned private IPv4 address, generates a temporary config for Auth/Firestore/Functions on 0.0.0.0 and keeps the privileged emulator UI/hub/logging local.
- Added matching debug-only app host/project validation and a persistent development warning on all screens. Public/ambiguous hosts, mismatched hosts, non-demo project IDs and release/profile LAN builds are rejected. Small-screen introduction scrolling accommodates the banner.
- Updated email-link callback/Auth emulator origins for the phone-reachable host and port 57602. Documented exact commands, trusted-network exposure, HTTP camera/location restrictions and separate HTTPS staging/proxy alternatives without weakening the private-host guards.
- Validation: 5 launcher/config tests, 12 Functions unit tests, and isolated matching-SDK Flutter analysis/50 tests pass. The browser-only test remains opt-in. A fresh emulator regression launch was blocked by occupied existing Auth/Firestore ports; that instance and its data were left untouched. No physical Wi-Fi phone test or actual LAN exposure was performed by the agent.
- Preserved the pre-existing lockfile/generated-plugin edits and mixed-SDK package configuration; Flutter verification used a disposable copy rather than rewriting those files or either SDK. No production services, staging project, tunnel or billing changes.

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
