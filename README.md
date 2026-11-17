# Rally4Ever

Flutter participant app with a shared Google/email identity, separate RSVP and attendance states, versioned forms and admin-managed coach access. Development is restricted to the local Firebase demo emulators; no production backend fallback.

See [setup and manual steps](docs/SETUP.md), [participant review](docs/PARTICIPANT.md), [function contracts/security](docs/FUNCTIONS.md), [schema](docs/DATA_MODEL.md), [screenshots](docs/SCREENSHOTS.md) and [changelog](docs/CHANGELOG.md).

```sh
npm ci
npm --prefix functions ci
flutter pub get
npm run emulators
# Seed from another terminal using the environment variables in docs/SETUP.md.
flutter run -d chrome --web-port 7357 --dart-define=USE_FIREBASE_EMULATORS=true
```

Run `flutter analyze`, `flutter test`, `npm run test:functions`, `npm run test:all:emulator` and `npm run test:participant:e2e`. Use Node 24 and Java 21. Tests reset only disposable local demo data.
