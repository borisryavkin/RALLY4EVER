# Local development and manual setup

## Local only — no Firebase account or billing required

Use Node 24 (`.nvmrc`), Java 21, the installed Flutter SDK and package lockfiles. Install Node dependencies with `npm ci`; Flutter dependencies with `flutter pub get`. The npm CLI tooling currently has 13 moderate transitive advisories after nonbreaking audit fixes; no high advisories remain. A scoped gRPC override updates the JS Firestore client's old 1.9.x pin to compatible 1.14.x. Avoid `npm audit fix --force`, which proposes incompatible Firebase downgrades. Reassess tooling advisories before deployment. No Node package is shipped with the Flutter UI in this stage.

Start the Auth (9099) and Firestore (8080) emulators:

```sh
npm run emulators
```

Emulator UI is `http://127.0.0.1:4000`. Default project ID is `demo-rally4ever`; no actual Firebase project exists or is required. Do not change this to a real project for development. CLI may print login/update notices; do not log in or deploy to make local tests work.

In another terminal, populate the demo fixtures:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 npm run seed
```

Seed creates 1 admin (`admin@rally4ever.org`), 2 coaches (`dan@rally4ever.org`, `mei@rally4ever.org`), 10 participants (`member1@example.test` through `member10@example.test`), three events and conduct/waiver definitions. Password for every **local-only fixture account**: `Emulator-only-Password-123!`. Seed emails are fixture identities, not invitations or sent mail. Auth users are marked verified and carry role claims; protected profiles also carry roles. One coach-added RSVP and one historic confirmed attendance fixture exercise participant visibility and feedback eligibility.

Rerunning seed does not overwrite existing Firestore fixture documents; it reapplies fixture Auth role claims. Event timestamps are relative to first seeding, so a long-lived fixture can expire. Restart the disposable emulators without import to obtain fresh fixtures. There is no production reset command or credential loader in this project.

Run checks (the emulator command starts/stops its own emulators; stop any manually running instance first):

```sh
flutter analyze
flutter test
npm run test:emulator
```

Tests deliberately clear **local demo Firestore data** in their isolated run. Seed and tests reject absent/nonlocal emulator hosts, unexpected project IDs and Google credential-file configuration. npm scripts specify the demo project explicitly. The Firebase CLI will download emulator binaries on first run.

The Dart service in `lib/data/emulator_backend.dart` is deliberately not connected to the prototype UI yet. Later integration must call `EmulatorBackend.connect` with `USE_FIREBASE_EMULATORS=true`; otherwise it throws. Only `127.0.0.1`, `localhost` and Android-emulator host `10.0.2.2` are accepted. Firestore disk persistence is disabled. Physical-device/LAN connection is not enabled in this stage. There is no production initialization fallback.

Current app UI remains the audited prototype; its email navigation is not real authentication. The new services and rules do not make that old UI a secure product until participant/coach integration replaces the prototype paths. No Android/iOS/web Firebase runtime build is claimed by the service/model tests; JS Auth integration exercises real local Auth tokens through Firestore rules.

## Manual steps later — none required for this stage

- Create/register a Firebase project/apps when deployment planning is approved. Stay on Spark for now. Configure authorized auth providers/domains deliberately; do not change a deployed provider without approval. New-account provisioning will be a trusted Function, not a Firestore client write.
- Review current Blaze/Functions/scheduled-job costs before any deployment; present AUD estimate and free emulator alternative, then wait for approval. Do not enable billing now. AUD $100 total cap; arrange AUD $20 budget alert with authorized billing access before billed services. Alert is not a hard spending limit.
- Supply APNs key/capabilities and configure FCM for iOS, Android and browser push; web service worker/VAPID; test physical device delivery. Emulators do not deliver real FCM pushes.
- Verify control of `rally4ever.org`; plan Firebase Hosting DNS/HTTPS and iOS/Android link associations. Any purchase or paid change needs advance approval. Use emulator URLs meanwhile.
- Supply approved form content, current versions, coach assignments, exact venue coordinates, event times/timezones and published app-store links. Approximate discovery coordinates must not become trusted geofence centers.
- For stores, supply signing/release access and authorize any account fees before payment. iOS camera usage text and native app links will be added with scanner integration.
- For legacy import/merge, supply old Admin app source/schema or sanitized export. Review dry-run report, backup and rollback strategy; explicit approval is required before real-data writes or deletion. The old duplicate bug remains unverified.
- Existing program JSON assets remain absolute symlinks to another local folder. Make them portable in a separate reviewed source-data change before a clean-machine app build; stage 3 does not change those assets.
