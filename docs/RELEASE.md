# Tester release preparation

Status: local preparation only. This release-preparation task has performed no upload, deployment, store-track change, new key, billing upgrade or payment. Concurrent workspace edits contain separate backend deployment notes; their authorization and live results have not been verified in this task. Distribution is restricted to a NEW TestFlight internal group and Google Play Internal testing. The existing external TestFlight group **`rally4ever` has real testers: never add these builds to it**, and never enable automatic distribution to that group.

## Audit and known store state (17 November 2026)

| Item | Repository / supplied evidence |
|---|---|
| iOS bundle ID | `org.rally4ever`, unchanged in all Runner configurations |
| App Store Connect | Apple ID `6816826035`; user reports version `1.0.0`, never publicly released; build 4 is being tested externally |
| Android applicationId / namespace | `org.rally4ever`, unchanged; no current Play app, user reports old app removed 6 November. User must check package reuse in the new app. No replacement ID will be chosen without instruction. |
| Version before preparation | `1.0.1+2` from pubspec; native builds consume Flutter version values |
| Prepared version | `1.0.1+5`: above supplied iOS `1.0.0` / build 4. Android has no current release; confirm historical highest versionCode and whether package reuse is allowed before upload. Never reuse a previously consumed code. |
| Android signing | Release config reads ignored `android/key.properties`; configured keystore exists. Existing alias/passwords are not printed or copied. Uses configured `keyPassword`, with the existing PKCS12 store-password fallback. Verify this is the key Play expects before uploading. |
| Apple signing | Owner confirmed `7HGT5BT6KT` is the correct team (17 November 2026). `ios/ExportOptions.plist` and `ios/ExportOptions.internal.plist` previously read `565ZMX3G2X`; both corrected to `7HGT5BT6KT` to match Runner Debug/Profile/Release and derived-flavor `DEVELOPMENT_TEAM`. No certificate/profile generated. |
| Existing APIs | Current app uses demo Firebase Auth/Firestore/Functions and OpenStreetMap raster tiles. Audited prototype baseline has bundled program JSON and no persistent member API. Legacy published-app backend is unknown; old Admin app absent. |
| Firebase candidate | User supplied `rally4ever-3adaf`, their only project. Owner confirmed (17 November 2026) it is empty/safe for staging use. Registered iOS (`1:55117668228:ios:5e47b3910d5846d92607d1`) and Android (`1:55117668228:android:678ee9fc62957bf42607d1`) apps via `firebase apps:create`; filled `config/staging.ios.json` and `config/staging.android.json` (both git-ignored) with the real API key/app ID/sender ID per platform. `GOOGLE_SERVER_CLIENT_ID` and `FIREBASE_IOS_CLIENT_ID` remain placeholders — no OAuth client exists yet because Google Sign-In has not been enabled on the project. No native config files were added under `ios/Runner` or `android/app/src` — a first pass with `flutterfire configure` did this and was reverted immediately because it tripped the emulator-flavor native guard; only the Firebase-console app registrations from that pass were kept. |

## Flavor isolation

Android product flavors and shared Xcode schemes are `emulator` and `staging`, with Debug/Profile/Release configurations; no application ID suffixes are added. These installs replace each other because IDs are intentionally unchanged. The original Runner scheme remains available. CocoaPods mappings include every derived configuration.

Native Gradle/Xcode preflight validation runs before packaging and rejects real Firebase config in emulator artifacts and emulator flags in staging artifacts. Keep registered native config files out of Runner/app resources; use ignored Dart configuration files.

`emulator` retains explicit `USE_FIREBASE_EMULATORS=true` opt-in, fixed `demo-rally4ever` options and local/LAN restrictions. It rejects real Firebase project/API/app config. It contains no registered real Firebase config files. Only the emulator Android manifest permits cleartext HTTP; its iOS plist permits local networking and explains local-network access. LAN still requires a debug build, so it is not a TestFlight transport.

`staging` uses real Firebase SDK options and never calls `use*Emulator`. It rejects USE_FIREBASE_EMULATORS, LAN_TESTING, LAN_HOST and FIREBASE_EMULATOR_HOST; requires FIREBASE_PROJECT_ID and explicit STAGING_PROJECT_ID to both equal the owner-supplied candidate `rally4ever-3adaf`. That allowlist is a configuration assertion, not proof a project is nonproduction. The owner must classify and approve it first. There is no production flavor or fallback.

Copy the credential-free `config/staging.example.json` into ignored `config/staging.ios.json` and `config/staging.android.json`, with the separately registered app ID per platform. Fill from the registered Firebase apps for exactly `org.rally4ever`. Do not add service accounts, APNs private keys, store credentials or passwords. Client API keys are shipped with Firebase clients, so enforce rules/provider restrictions rather than treating them as authorization. Keep the local files outside git. This task did not create real client config files; concurrent work has since supplied ignored platform files.

**Staging readiness remains unverified:** at initial audit Functions were hardcoded to the demo project. Concurrent edits now resolve the runtime project, allowlist `rally4ever-3adaf`, and include notes claiming a real deployment. This task has not deployed or validated that live backend, and leaves those changes outside its commits. No-app email auth remains emulator-only and notification delivery still records `emulatorPushes` rather than sending FCM. A separate staging seed script also appeared concurrently; do not run it until data classification and real writes are explicitly approved. Review project targeting, rules/indexes, schedules, notification delivery, billing and actual deployed code before distributing testers. No command in this guide deploys the backend.

Native Google sign-in also needs the existing registered iOS OAuth client and reversed client-ID URL scheme, Android SHA fingerprints (Play signing certificate as well as local upload certificate where appropriate), approved Google provider and authorized link domains. Native email-link return routing and APNs/FCM require physical-device validation. Emulator verified fixture accounts/passwords must never be seeded into staging.

## Local validation and builds

Use the compatible installed SDK, not an older PATH entry:

```sh
cd /Users/borisryavkin/technical/flutter/rally4ever/rally4ever
export PATH="/Users/borisryavkin/technical/flutter/flutter/bin:$PATH"
flutter --version
flutter pub get
flutter analyze
flutter test
npm run test:lan
npm run test:functions
python3 -m unittest discover -s tests/release_guard -v
# Run ONLY against fresh isolated emulators; the suite clears local fixture data.
npm run test:all:emulator
```

For local emulator devices:

```sh
flutter run --flavor emulator --dart-define=USE_FIREBASE_EMULATORS=true
# Android emulator networking:
flutter run --flavor emulator --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

Use the opt-in phone-web commands in [SETUP.md](SETUP.md) for LAN. Emulator builds are not the tester-store artifact.

After all blockers are resolved, compile staging with platform-specific local config, NO emulator flags, and a build number rechecked against both consoles immediately before build:

```sh
unset LAN_TESTING LAN_HOST FIRESTORE_EMULATOR_HOST FIREBASE_AUTH_EMULATOR_HOST
# Confirm 5 is still unused; substitute a larger approved number if necessary.
flutter build ipa --release --flavor staging \
  --dart-define-from-file=config/staging.ios.json \
  --build-name=1.0.1 --build-number=5 \
  --export-options-plist=ios/ExportOptions.internal.plist

flutter build appbundle --release --flavor staging \
  --dart-define-from-file=config/staging.android.json \
  --build-name=1.0.1 --build-number=5
```

`ios/ExportOptions.internal.plist` exports locally (`destination=export`) and sets `testFlightInternalTestingOnly=true`: Xcode marks this build ineligible for external TestFlight or App Store distribution. It follows the current local project/export team; actual app ownership still needs confirmation.

The IPA command is blocked until the original owning Apple team is confirmed and the existing signing team is verified against app 6816826035. Do not use `-allowProvisioningUpdates` as a shortcut. Do not generate new signing material. Android must retain the existing local keystore; inspect the release bundle certificate against the expected upload certificate in Play Console without printing passwords. A previously published/removed Android package can have a historical versionCode higher than 5; recheck before building.

Expected artifacts: `build/ios/ipa/*.ipa` and `build/app/outputs/bundle/stagingRelease/app-staging-release.aab`. Inspect actual IPA bundle ID, version, build, entitlements, signing team and endpoint config; inspect AAB manifest/package/version/signature. Confirm no demo users, emulator endpoints, accidental real-data access or secrets. Exercise real sign-in, QR camera, GPS, forms, RSVP vs attendance, coach confirmation and revoked roles on physical iOS/Android devices. Unsigned local compilation alone is not a tester-ready artifact.

## QR links and permissions

Camera and foreground location permissions are declared. iOS text explains coach QR scanning and venue checks; Android uses runtime camera/location permission prompts. No new background-location behavior was introduced; the previous iOS Always usage-description key is retained.

Android has a verified HTTPS intent filter for `https://rally4ever.org/c/*`; iOS flavor configurations attach `applinks:rally4ever.org` entitlements. The app queues strict valid QR URLs through login and opens the scan screen for the same validated check-in flow. No URL grants attendance by itself. Query secret/time/distance/forms checks remain server-side.

Before links can verify, the domain owner must review and publish (separate explicit approval) the templates in `docs/release-templates` at HTTPS `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json`, without redirects. Confirm the actual Apple application-identifier prefix (not blindly a guessed team ID), existing website associations and Play **app-signing** SHA-256, not just the upload key. Preserve all existing associations. Domain control and associated-domain capability/profile must be confirmed with the existing team. Do not redirect existing member traffic to an unapproved staging backend. Cold/warm link tests on devices remain required.


## Existing artifacts found during final verification

Concurrent work produced `build/ios/ipa/rally4ever.ipa` and `build/app/outputs/bundle/stagingRelease/app-staging-release.aab`. This task verified the IPA's embedded bundle/version/build as `org.rally4ever`, `1.0.1`, `5`, the archived app's signing team as `7HGT5BT6KT`, and the AAB JAR signature. Jarsigner reports the usual untrusted/self-signed certificate-chain warning; signature verification alone does not prove Play accepts that upload certificate. These pre-existing staging artifacts were not freshly rebuilt by this task after the concurrent repository error-handling changes. Review them against the intended source revision before any upload.

Both ignored client config files identify `rally4ever-3adaf`, APP_ENV=staging, without USE_FIREBASE_EMULATORS. The Android file still contains OAuth client-ID placeholders at verification; native coach Google sign-in must be configured and tested before calling that build ready. Website link association, physical permissions/QR/GPS, live backend flow and internal-store acceptance remain unverified. No upload is authorized by finding these artifacts.

## Upload — STOP for approval first

No upload steps below have been run. Obtain explicit approval naming the artifact checksum, version/build, app record and internal group/track before either upload. Recheck highest builds and signing again.

**iOS:** open `build/ios/archive/Runner.xcarchive` in Xcode Organizer → Distribute App → App Store Connect → Upload, or use Apple Transporter to upload the prepared IPA to existing app `6816826035`. Select the existing owning team; choose TestFlight Internal Only where available. Upload is not an App Store production submission. After processing/export-compliance answers, create a new internal group (suggested `R4E Staging Internal`), add only authorized App Store Connect users, and manually assign the approved build. Do NOT add it to external group `rally4ever`, enable external auto-distribution or submit for public release. [Apple internal-testing guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

**Android:** owner first creates/checks the new Play app and confirms whether `org.rally4ever` is accepted; an existing removed package might remain reserved, so do not assume it is reusable. Verify upload certificate and Play App Signing status without replacing the existing key. In Play Console choose Testing → Internal testing → Create release; upload only the reviewed staging AAB, add tester email list, review the page showing **Internal testing**, then roll out to internal testing only after approval. Share its opt-in link with approved testers separately; this task does not authorize sending invitations. Never promote to open/closed/production tracks. A personal account may have additional verification requirements; internal testing is the only requested route. [Google internal-testing guide](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en).

## Firebase App Distribution alternative (documented, not authorized)

This is an optional faster feedback path, not an enabled replacement for the requested stores. It still uploads externally and requires separate approval. Android can distribute a signed APK without a store release:

```sh
flutter build apk --release --flavor staging \
  --dart-define-from-file=config/staging.android.json \
  --build-name=1.0.1 --build-number=5
# UPLOAD ONLY AFTER APPROVAL; use the actual registered Android Firebase app ID.
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-staging-release.apk \
  --project rally4ever-3adaf --app "$STAGING_ANDROID_FIREBASE_APP_ID" \
  --groups r4e-internal --release-notes "Internal staging testing only"
```

For iOS, an App Store signed IPA cannot simply be installed through App Distribution. Existing approved Ad Hoc provisioning, registered tester UDIDs and signing are needed; do not create a new key/profile silently. With those approved prerequisites:

```sh
flutter build ipa --release --flavor staging \
  --dart-define-from-file=config/staging.ios.json \
  --build-name=1.0.1 --build-number=5 --export-method=ad-hoc
# UPLOAD ONLY AFTER APPROVAL; actual registered iOS Firebase app ID required.
firebase appdistribution:distribute build/ios/ipa/rally4ever.ipa \
  --project rally4ever-3adaf --app "$STAGING_IOS_FIREBASE_APP_ID" \
  --groups r4e-internal --release-notes "Internal staging testing only"
```

Check the actual IPA filename rather than assuming it. [Firebase iOS CLI](https://firebase.google.com/docs/app-distribution/ios/distribute-cli), [Firebase Android CLI](https://firebase.google.com/docs/app-distribution/android/distribute-cli).

## Manual steps and AUD costs

| Action | AUD estimate / approval |
|---|---|
| Local preparation, compilation, emulator tests | $0; completed checks recorded in CHANGELOG |
| Reuse active Apple/Play accounts and existing keys; TestFlight/Play internal uploads | $0 incremental platform fee; upload approval still required |
| Apple membership if expired | Planning allowance ~AUD $160/year (Apple quotes US$99 or local price; exact AUD checkout required). Exceeds the $100 budget: STOP, no renewal. Reuse active membership/free emulator alternative. [Apple membership](https://developer.apple.com/support/compare-memberships/) |
| Google Play account | Existing account: $0. New account is not requested; US$25 is roughly AUD $40 planning allowance, exact FX/tax unknown. STOP before any charge; use existing account or local APK instead. [Play registration](https://support.google.com/googleplay/android-developer/answer/6112435?hl=en-GB) |
| Firebase client setup/Auth/Firestore within Spark quotas | $0; confirm project data and providers before configuration. Do not enable SMS. |
| Functions, Cloud Scheduler, builds/artifact storage after Blaze | No fixed bill guaranteed; proposed small-test planning envelope AUD $0–20, subject to measured usage and actual quotas. This is not a quote or a cost cap. STOP before enabling/deploying; provide a workload estimate and free emulator alternative for approval. |
| Budget alert | Configure AUD $20 alert only with approved billing setup and appropriate permissions/currency. Alerts are not a hard spending cap; total budget remains AUD $100. No alert or billing account was created here. |
| Firebase App Distribution | No-cost service; signing/account prerequisites still apply. Upload separately approved. [Firebase pricing](https://firebase.google.com/pricing) |
| Existing rally4ever.org association files | No new domain purchase; $0 incremental if existing hosting supports them. Any paid hosting/domain change: quote first; local links/emulators remain free alternative. |
| Camera/GPS, APNs/FCM key reuse | $0 service/setup fee; supply existing keys privately, do not generate/commit keys. Notification infrastructure deployment may incur the above backend usage. |

Remaining owner inputs/actions: confirm Apple team, staging project data classification and registered Firebase app configs; confirm Android package availability, historical version codes and upload certificate; review app privacy disclosures/Data Safety, support/privacy URLs and encryption/export compliance; enable needed capabilities with existing signing; supply Google OAuth URL configuration and SHA fingerprints; approve backend readiness/costs; approve website association changes; nominate new internal testers/group. No existing external testers are to receive these builds.

See [MIGRATION.md](MIGRATION.md) before connecting existing member data. This preparation task performed no legacy production migration, distribution or deployment; concurrent backend deployment notes are separate and unverified here.
