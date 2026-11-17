# Change log

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
