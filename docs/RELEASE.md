# Tester release preparation

Builds through 6 have now been uploaded to internal testing; see [UPLOADS.md](UPLOADS.md). Use the guarded scripts below for the next build (7 or higher, after checking both consoles). Earlier sections retain historical preparation details.

## Upload update — 17 November 2026

Both uploads are now confirmed; see [UPLOADS.md](UPLOADS.md) for the delivery record and remaining tester setup.

Owner subsequently authorized “upload them all” and specified the Android package **`org.raly4ever`** (one “l” in “raly”). This supersedes the earlier Android package assumption below. iOS remains **`org.rally4ever`**. Only Android `applicationId` changed; the source namespace/MainActivity remain `org.rally4ever`. The domain association template now targets the corrected Android package.

Registered the matching Android Firebase client `1:55117668228:android:effa8a7b07f1dbd52607d1` in the existing `rally4ever-3adaf` project, kept the old registration, and updated only the ignored Android client config. No key was generated and no backend deployed in this upload task.

Transporter confirmed iOS `1.0.1 (5)` delivered to app `6816826035` at 20:38 Sydney time; Apple processing was pending at that observation. The exported artifact has `testFlightInternalTestingOnly=true`; no external-group assignment was made. Android's new app record is `4975028595777084434`, with the UI explicitly showing Create internal testing release. See [UPLOADS.md](UPLOADS.md) for final upload status and artifact checksums.

The corrected Android release was built by Gradle with versionName `1.0.1`, versionCode `5`, and the existing upload signing key. Flutter's post-build verification returned failure because Android SDK cmdline-tools/apkanalyzer is missing. Independently verified all six `libflutter.so`/`libapp.so` ABI libraries have no `.debug_*` sections, separate `.sym` metadata exists for each, and jarsigner verifies the bundle. No check was disabled or SDK license accepted. Installing the official Android command-line tools later will allow Flutter's own check to run; do not infer a native stripping failure from this generic message alone.


Preparation snapshot (before the upload update above): local preparation only. This release-preparation task has performed no upload, deployment, store-track change, new key, billing upgrade or payment. Concurrent workspace edits contain separate backend deployment notes; their authorization and live results have not been verified in this task. Distribution is restricted to a NEW TestFlight internal group and Google Play Internal testing. The existing external TestFlight group **`rally4ever` has real testers: never add these builds to it**, and never enable automatic distribution to that group.

## Audit and known store state (17 November 2026)

| Item | Repository / supplied evidence |
|---|---|
| iOS bundle ID | `org.rally4ever`, unchanged in all Runner configurations |
| App Store Connect | Apple ID `6816826035`; user reports version `1.0.0`, never publicly released; build 4 is being tested externally |
| Android applicationId / namespace | Owner specified `org.raly4ever` for the new Play app; source namespace remains `org.rally4ever`. Code 5 is now uploaded to Internal testing. |
| Version before preparation | `1.0.1+2` from pubspec; native builds consume Flutter version values |
| Prepared version | `1.0.1+5`: above supplied iOS `1.0.0` / build 4. Android has no current release; confirm historical highest versionCode and whether package reuse is allowed before upload. Never reuse a previously consumed code. |
| Android signing | Release config reads ignored `android/key.properties`; configured keystore exists. Existing alias/passwords are not printed or copied. Uses configured `keyPassword`, with the existing PKCS12 store-password fallback. Verify this is the key Play expects before uploading. |
| Apple signing | Owner confirmed `7HGT5BT6KT` is the correct team (17 November 2026). `ios/ExportOptions.plist` and `ios/ExportOptions.internal.plist` previously read `565ZMX3G2X`; both corrected to `7HGT5BT6KT` to match Runner Debug/Profile/Release and derived-flavor `DEVELOPMENT_TEAM`. No certificate/profile generated. |
| Existing APIs | Current app uses demo Firebase Auth/Firestore/Functions and OpenStreetMap raster tiles. Audited prototype baseline has bundled program JSON and no persistent member API. Legacy published-app backend is unknown; old Admin app absent. |
| Firebase candidate | User supplied `rally4ever-3adaf`, their only project. Owner confirmed (17 November 2026) it is empty/safe for staging use. Registered iOS (`1:55117668228:ios:5e47b3910d5846d92607d1`) and Android (`1:55117668228:android:effa8a7b07f1dbd52607d1`) apps via `firebase apps:create`; filled `config/staging.ios.json` and `config/staging.android.json` (both git-ignored) with the real API key/app ID/sender ID per platform. `GOOGLE_SERVER_CLIENT_ID` and `FIREBASE_IOS_CLIENT_ID` remain placeholders — no OAuth client exists yet because Google Sign-In has not been enabled on the project. No native config files were added under `ios/Runner` or `android/app/src` — a first pass with `flutterfire configure` did this and was reverted immediately because it tripped the emulator-flavor native guard; only the Firebase-console app registrations from that pass were kept. |

## Flavor isolation

Android product flavors and shared Xcode schemes are `emulator` and `staging`, with Debug/Profile/Release configurations; no application ID suffixes are added. These installs replace each other because IDs are intentionally unchanged. The original Runner scheme remains available. CocoaPods mappings include every derived configuration.

Native Gradle/Xcode preflight validation runs before packaging and rejects real Firebase config in emulator artifacts and emulator flags in staging artifacts. Keep registered native config files out of Runner/app resources; use ignored Dart configuration files.

`emulator` retains explicit `USE_FIREBASE_EMULATORS=true` opt-in, fixed `demo-rally4ever` options and local/LAN restrictions. It rejects real Firebase project/API/app config. It contains no registered real Firebase config files. Only the emulator Android manifest permits cleartext HTTP; its iOS plist permits local networking and explains local-network access. LAN still requires a debug build, so it is not a TestFlight transport.

`staging` uses real Firebase SDK options and never calls `use*Emulator`. It rejects USE_FIREBASE_EMULATORS, LAN_TESTING, LAN_HOST and FIREBASE_EMULATOR_HOST; requires FIREBASE_PROJECT_ID and explicit STAGING_PROJECT_ID to both equal the owner-supplied candidate `rally4ever-3adaf`. That allowlist is a configuration assertion, not proof a project is nonproduction. The owner must classify and approve it first. There is no production flavor or fallback.

Copy the credential-free `config/staging.example.json` into ignored `config/staging.ios.json` and `config/staging.android.json`, with the separately registered app ID per platform. Fill from the registered Firebase apps for iOS `org.rally4ever` and Android `org.raly4ever`. Do not add service accounts, APNs private keys, store credentials or passwords. Client API keys are shipped with Firebase clients, so enforce rules/provider restrictions rather than treating them as authorization. Keep the local files outside git. This task did not create real client config files; concurrent work has since supplied ignored platform files.

**Staging readiness remains unverified:** at initial audit Functions were hardcoded to the demo project. Concurrent edits now resolve the runtime project, allowlist `rally4ever-3adaf`, and include notes claiming a real deployment. This task has not deployed or validated that live backend, and leaves those changes outside its commits. No-app email auth remains emulator-only and notification delivery still records `emulatorPushes` rather than sending FCM. A separate staging seed script also appeared concurrently; do not run it until data classification and real writes are explicitly approved. Review project targeting, rules/indexes, schedules, notification delivery, billing and actual deployed code before distributing testers. No command in this guide deploys the backend.

Native Google sign-in also needs the existing registered iOS OAuth client and reversed client-ID URL scheme, Android SHA fingerprints (Play signing certificate as well as local upload certificate where appropriate), approved Google provider and authorized link domains. There is no email-link ("magic link") sign-in to route; APNs/FCM still require physical-device validation. Emulator verified fixture accounts/passwords must never be seeded into staging.

## Local validation and builds

Build 5 has now been uploaded on both platforms. The commands below use **build 6 for the next upload**; recheck the consoles first to ensure it is unused. The release record remains version `1.0.1`, build `5`.

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

Release and profile builds now fail at build time without explicit staging Firebase configuration. Emulator mode is debug-only: an unflavored release/profile build cannot fall back to it. Xcode validates before Flutter compilation; Gradle passes each variant's build mode to the same guard. A constant-evaluation check also rejects invalid non-debug Dart compilations, including web. Missing config, mixed emulator/LAN flags, and the wrong project are rejected without contacting Firebase.

Use the scripts so flavor/config flags cannot be forgotten. They validate the ignored platform JSON before invoking Flutter, require an unused build number, and never upload or deploy. Builds through **6** have been uploaded; recheck both stores before choosing **7 or higher**:

```sh
./scripts/build-ios-staging.sh --build-number 7
./scripts/build-android-staging.sh --build-number 7

# Validate configuration only; no compilation, signing or upload:
./scripts/build-ios-staging.sh --build-number 7 --check-only

# Local profile build (not a TestFlight artifact):
./scripts/build-ios-staging.sh --build-number 7 --mode profile
./scripts/build-android-staging.sh --build-number 7 --mode profile
```

Defaults: release mode, version `1.0.1`, and `config/staging.ios.json` or `config/staging.android.json`. Use `--config /private/path/config.json` for another local config, `--build-name` for an approved version, and `FLUTTER_BIN=/path/to/flutter` for a specific SDK. Keep config and signing keys out of git. Profile photos are optional: `FIREBASE_STORAGE_BUCKET` may name an existing configured bucket, but must not be guessed. Without it, Auth/Firestore/Functions still start; photo actions report that photos are unavailable. Do not enable paid Storage just to unblock sign-in. Startup failures now stay on a retryable connection screen with a support code, rather than displaying emulator instructions in TestFlight.

Required defines: `APP_ENV=staging`, `STAGING_PROJECT_ID=rally4ever-3adaf`, `FIREBASE_PROJECT_ID=rally4ever-3adaf`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, and `FIREBASE_MESSAGING_SENDER_ID`. Supply the registered client for each platform. Emulator/LAN settings must be absent or disabled.

Equivalent explicit release commands (the native guard still runs):

```sh
flutter build ipa --release --flavor staging \
  --dart-define-from-file=config/staging.ios.json \
  --build-name=1.0.1 --build-number=7 \
  --export-options-plist=ios/ExportOptions.internal.plist

flutter build appbundle --release --flavor staging \
  --dart-define-from-file=config/staging.android.json \
  --build-name=1.0.1 --build-number=7
```

Run guard regressions with `python3 -m unittest discover -s tests/release_guard -v`. They exercise the Dart compiler in release/profile modes, native build hooks, missing/mixed config, and script flag forwarding without building/uploading store artifacts.

`ios/ExportOptions.internal.plist` exports locally (`destination=export`) and sets `testFlightInternalTestingOnly=true`: Xcode marks this build ineligible for external TestFlight or App Store distribution. It follows the current local project/export team; actual app ownership still needs confirmation.

The IPA command is blocked until the original owning Apple team is confirmed and the existing signing team is verified against app 6816826035. Do not use `-allowProvisioningUpdates` as a shortcut. Do not generate new signing material. Android must retain the existing local keystore; inspect the release bundle certificate against the expected upload certificate in Play Console without printing passwords. A previously published/removed Android package can have a historical versionCode higher than 5; recheck before building.

Expected artifacts: `build/ios/ipa/*.ipa` and `build/app/outputs/bundle/stagingRelease/app-staging-release.aab`. Inspect actual IPA bundle ID, version, build, entitlements, signing team and endpoint config; inspect AAB manifest/package/version/signature. Confirm no demo users, emulator endpoints, accidental real-data access or secrets. Exercise real sign-in, QR camera, GPS, forms, RSVP vs attendance, coach confirmation and revoked roles on physical iOS/Android devices. Unsigned local compilation alone is not a tester-ready artifact.

## QR links and permissions

Camera and foreground location permissions are declared. iOS text explains both uses (finding nearby sessions on Play/Map, and checking you're at the venue when you check in); Android uses runtime camera/location permission prompts. Only `ACCESS_COARSE_LOCATION`/`ACCESS_FINE_LOCATION` (foreground, "while using the app") are requested; there is no background-location behavior. The previously-declared, unused iOS "Always" usage-description key was removed -- the app never requests Always authorization, and leaving an unused description in place is exactly the kind of mismatch App Privacy/Data Safety review flags.

**Location and the App Privacy / Play Data Safety forms**: the device's current position is used only on-device, to centre the Play list, the map, and distance sorting -- it is never written to Firestore, logs, or any analytics/third-party service. Only a reverse-geocoded suburb label (e.g. "Near Bondi Junction") is ever shown in the UI, never raw coordinates, and that label itself is never stored either. The existing check-in geofence flow is unrelated and separate: it submits the device's precise position to the `checkIn` callable specifically to verify venue proximity for that one attendance record, server-side -- it is a different request, with its own existing disclosure, not changed by the Play/Map browsing feature. When filling in the store forms: Location -> "App functionality" (finding nearby sessions) and separately the existing check-in disclosure; "Data not linked to you" / not collected for the browsing use, since it never leaves the device.

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
  --build-name=1.0.1 --build-number=7
# UPLOAD ONLY AFTER APPROVAL; use the actual registered Android Firebase app ID.
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-staging-release.apk \
  --project rally4ever-3adaf --app "$STAGING_ANDROID_FIREBASE_APP_ID" \
  --groups r4e-internal --release-notes "Internal staging testing only"
```

For iOS, an App Store signed IPA cannot simply be installed through App Distribution. Existing approved Ad Hoc provisioning, registered tester UDIDs and signing are needed; do not create a new key/profile silently. With those approved prerequisites:

```sh
flutter build ipa --release --flavor staging \
  --dart-define-from-file=config/staging.ios.json \
  --build-name=1.0.1 --build-number=7 --export-method=ad-hoc
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
