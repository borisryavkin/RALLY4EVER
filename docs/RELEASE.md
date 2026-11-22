# Tester feedback batch — 1.0.3 (23)

Prepared locally on 20 November 2026 in an isolated git worktree (`fix/tester-feedback-batch`), merged back into `feature/qr-attendance`; not uploaded. Full detail in the CHANGELOG entry of the same name. Build 21 is already consumed on Play (per the section below); build 22 was separately prepared by a concurrent process for its own photo work. This build uses **23** to stay clear of both.

```sh
export PATH="/Users/borisryavkin/technical/flutter/flutter/bin:$PATH"
./scripts/build-android-staging.sh --build-name 1.0.3 --build-number 23
./scripts/build-ios-staging.sh --build-name 1.0.3 --build-number 23 --export-options normal
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar \
  --package org.raly4ever --version-name 1.0.3 --version-code 23
```

- Android AAB: `build/app/outputs/bundle/stagingRelease/app-staging-release.aab`, 80,108,115 bytes, SHA-256 `b6141d7579f9d9e576112ecb251358885b8f77aba163bf2ba438a703554fb97a`. Package `org.raly4ever`, version `1.0.3 (23)`, `rally4ever-3adaf` present in all three ABIs' `libapp.so`, existing upload certificate (`11:51:C4:0F:AF:82:97:8B:80:1D:BF:D5:3F:1E:44:E7:EB:0F:AF:AD`) and JAR signature verified.
- iOS IPA: `build/ios/ipa/rally4ever.ipa`, 39.8MB. Bundle `org.rally4ever`, version `1.0.3 (23)` confirmed from the archived `Info.plist`; `rally4ever-3adaf` present 3× in `App.framework/App`; `codesign --verify --deep --strict` passed; normal (external-testing-capable) `ios/ExportOptions.plist`, team `7HGT5BT6KT`.
- Next build must use **24 or higher** -- `scripts/build-staging.py`'s floor is updated accordingly.
- Not uploaded: no App Store Connect API key or Play service account is configured in this environment.

---

# Session and venue photos — prepared 20 November 2026

Current photo-fix artifacts are **Android 1.0.3 (22)** (`org.raly4ever`) and **iOS 1.0.3 (21)** (`org.rally4ever`). No store upload was performed. The Play Console was observed already containing code 21, so the requested rebuilt code 21 is retained locally for review but **cannot replace the uploaded code 21**. Use the new code 22 AAB for upload. This section supersedes the older records below.

- Uploadable AAB: `build/app/outputs/bundle/stagingRelease/app-staging-release.aab` — 79,959,633 bytes. Existing upload signature, package, code 22 and real Firebase marker in all ABI libraries verified.
- Requested code 21 photo build, local review only: `build/releases/rally4ever-1.0.3-21-photo-changes.aab` — 79,959,635 bytes.
- IPA: `build/ios/ipa/rally4ever.ipa` — 39,180,057 bytes. Apple Distribution signature and deep/strict exported IPA verification passed, team `7HGT5BT6KT`, build 21, real Firebase marker. Exported with **normal `ios/ExportOptions.plist`**, without internal-only restriction. Do not assign it to an external group automatically.

```sh
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter \
  ./scripts/build-android-staging.sh --build-name 1.0.3 --build-number 22
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter \
  ./scripts/build-ios-staging.sh --build-name 1.0.3 --build-number 21 --export-options normal
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar \
  --version-name 1.0.3 --version-code 22 --package org.raly4ever
```

Use a fresh unused build code for any subsequent changed upload. Both builds use ignored real platform configs for `rally4ever-3adaf`, staging flags, existing signing keys and the native release guards. `pubspec.yaml` now defaults to `1.0.3+22`; the iOS command deliberately overrides build 21.

The admin site is live at https://rally4ever-admin-3adaf.web.app . See [CATALOGUE_PHOTOS.md](CATALOGUE_PHOTOS.md) for exact taps, fallback/removal semantics, real-project HTTP proofs, tests and backups.

---

## Earlier preparation records

# Android internal tester bundle — 1.0.3 (21)

Prepared locally on 20 November 2026; not uploaded. **Corrects build 20.** Build 20's own section here (and its CHANGELOG entry) claimed a "latest owner instruction" to switch Android to `org.rally4ever` -- no such instruction exists in this task's record, and Google Play rejected the build 20 upload with its standard package-mismatch error, because the existing Play app (`4975028595777084434`, Internal testing track `4701651234356647750`) is registered for `org.raly4ever` and always has been (builds 5, 6, 9, 10 all shipped under it). `android/app/build.gradle.kts`'s `applicationId` and the ignored `config/staging.android.json`'s `FIREBASE_APP_ID` are both back to `org.raly4ever` / `...effa8a7b...` (the app actually registered for that package, per build 9's record below) -- see the CHANGELOG entry for the full diagnosis.

`pubspec.yaml`: **version: 1.0.3+21** (20 was never accepted by Play, but isn't reused, to avoid any ambiguity). Existing upload keystore reused -- same certificate as every prior accepted build. No Firebase data or Auth accounts changed. No upload/deploy or spending.

```sh
cd /Users/borisryavkin/technical/flutter/rally4ever/rally4ever
export PATH="/Users/borisryavkin/technical/flutter/flutter/bin:$PATH"
flutter clean
flutter pub get
# Guarded wrapper; validates configuration before Flutter:
./scripts/build-android-staging.sh --build-name 1.0.3 --build-number 21
# Once built, inspect with the official bundletool jar already downloaded locally:
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar \
  --package org.raly4ever --version-name 1.0.3 --version-code 21
```

Do not reuse code 21 for a later changed upload. `scripts/validate-build.py`, wired to Gradle pre-build, refuses release/profile without real staging config and refuses emulator/LAN settings. Missing config also fails before Flutter through the wrapper. No config files, credentials or keystores are committed.

Toolchain fix (from build 20, unaffected by this correction): official Mac ARM Android command-line tools at `~/Library/Android/sdk/cmdline-tools/latest`, licences accepted, NDK `28.2.13676358`. Doctor reports a healthy Android toolchain; clean release build succeeds with standard symbol stripping, no `keepDebugSymbols` workaround.

Verified AAB: `build/app/outputs/bundle/stagingRelease/app-staging-release.aab`, **79,887,857 bytes**. `bundletool validate`, manifest package (`org.raly4ever`)/version, every ABI's `libapp.so` staging project marker, JAR signature and existing upload keystore comparison passed. Full hash/results: `docs/verification/android21-bundle.json`.

Upload SHA-1: `11:51:C4:0F:AF:82:97:8B:80:1D:BF:D5:3F:1E:44:E7:EB:0F:AF:AD` (same certificate as builds 5/6/9/10). Firebase has **no SHA entries** registered for the `org.raly4ever` app (`1:55117668228:android:effa8a7b07f1dbd52607d1`) -- a pre-existing, unchanged gap, not introduced by this fix. Obtain the Play app-signing SHA-1 from Play Console → Setup/App integrity → App signing, then add both it and the upload SHA-1 in Firebase → Project settings → General → that Android app → Add fingerprint. Google Sign-In on a Play-installed Android build remains unproven until that's done; it does not block this upload. Receipt: `docs/verification/android21-firebase-sha.json`.

Layout/screenshot fixes from build 20 are unaffected by this correction and remain in this build: removed the global 520 px app constraint, fixed Help contact-row wrapping, screenshots under `docs/screenshots/android20/`.

Upload manually only to **Play Internal testing**, selecting the AAB file above. No production track. No new costs incurred. Future rebuilds use a new code after checking Play Console.

---

## Historical release records (superseded by the Android section above)

Current iOS tester build: **1.0.2 (13)**, delivered 19 November 2026 at 21:18 Sydney time and verified **Testing** in internal group **boris** (1 tester). Exported using normal `ios/ExportOptions.plist`; external-capable artifact, with no external group assignment. Source `7904cf2`, real Firebase project `rally4ever-3adaf`. The next build must be **14 or higher**, after checking both consoles.

For the next iOS staging build (after rechecking the unused number):

```sh
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter ./scripts/build-ios-staging.sh --build-name 1.0.2 --build-number 14
```

This validates `config/staging.ios.json` and uses normal `ios/ExportOptions.plist` by default; do not omit staging config or enable emulator flags. Android's equivalent remains `./scripts/build-android-staging.sh --build-name 1.0.2 --build-number 14` using `config/staging.android.json`, but no Android upload was requested/performed for this staff-tools increment.

# Tester release preparation

Version **1.0.2 (10)** is uploaded: TestFlight shows Testing in internal group `boris`, and Play Internal testing shows Active. See [UPLOADS.md](UPLOADS.md). The next build must be **11 or higher**, after checking both consoles; scripts now default to version `1.0.2`. Earlier sections retain historical preparation details.

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

Use the scripts so flavor/config flags cannot be forgotten. They validate the ignored platform JSON before invoking Flutter, require an unused build number, and never upload or deploy. Build 6 has been uploaded; 7 and 8 were built but not uploaded; recheck both stores before choosing **10 or higher** for the next one:

```sh
./scripts/build-ios-staging.sh --build-number 11
./scripts/build-android-staging.sh --build-number 11

# Validate configuration only; no compilation, signing or upload:
./scripts/build-ios-staging.sh --build-number 11 --check-only

# Local profile build (not a TestFlight artifact):
./scripts/build-ios-staging.sh --build-number 11 --mode profile
./scripts/build-android-staging.sh --build-number 11 --mode profile
```

Defaults: release mode, version `1.0.2`, and `config/staging.ios.json` or `config/staging.android.json`. Use `--config /private/path/config.json` for another local config, `--build-name` for an approved version, and `FLUTTER_BIN=/path/to/flutter` for a specific SDK. Keep config and signing keys out of git. Profile photos are optional: `FIREBASE_STORAGE_BUCKET` may name an existing configured bucket, but must not be guessed. Without it, Auth/Firestore/Functions still start; photo actions report that photos are unavailable. Do not enable paid Storage just to unblock sign-in. Startup failures now stay on a retryable connection screen with a support code, rather than displaying emulator instructions in TestFlight.

Required defines: `APP_ENV=staging`, `STAGING_PROJECT_ID=rally4ever-3adaf`, `FIREBASE_PROJECT_ID=rally4ever-3adaf`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, and `FIREBASE_MESSAGING_SENDER_ID`. Supply the registered client for each platform. Emulator/LAN settings must be absent or disabled.

Equivalent explicit release commands (the native guard still runs):

```sh
flutter build ipa --release --flavor staging \
  --dart-define-from-file=config/staging.ios.json \
  --build-name=1.0.2 --build-number=11 \
  --export-options-plist=ios/ExportOptions.internal.plist

flutter build appbundle --release --flavor staging \
  --dart-define-from-file=config/staging.android.json \
  --build-name=1.0.2 --build-number=11
```

Run guard regressions with `python3 -m unittest discover -s tests/release_guard -v`. They exercise the Dart compiler in release/profile modes, native build hooks, missing/mixed config, and script flag forwarding without building/uploading store artifacts.

`ios/ExportOptions.internal.plist` exports locally (`destination=export`) and sets `testFlightInternalTestingOnly=true`: Xcode marks this build ineligible for external TestFlight or App Store distribution. It follows the current local project/export team; actual app ownership still needs confirmation.

The IPA command is blocked until the original owning Apple team is confirmed and the existing signing team is verified against app 6816826035. Do not use `-allowProvisioningUpdates` as a shortcut. Do not generate new signing material. Android must retain the existing local keystore; inspect the release bundle certificate against the expected upload certificate in Play Console without printing passwords. A previously published/removed Android package can have a historical versionCode higher than 5; recheck before building.

Expected artifacts: `build/ios/ipa/*.ipa` and `build/app/outputs/bundle/stagingRelease/app-staging-release.aab`. Inspect actual IPA bundle ID, version, build, entitlements, signing team and endpoint config; inspect AAB manifest/package/version/signature. Confirm no demo users, emulator endpoints, accidental real-data access or secrets. Exercise real sign-in, QR camera, GPS, forms, RSVP vs attendance, coach confirmation and revoked roles on physical iOS/Android devices. Unsigned local compilation alone is not a tester-ready artifact.

## Apple notices on build 10

Build `1.0.2 (10)` was accepted, processed, and observed Testing in internal group `boris`. Apple reported warnings `90725` (iOS 27 SDK/Xcode 27 required from April 2027) and `90683` (missing `NSLocationAlwaysAndWhenInUseUsageDescription`, referenced by a linked location SDK). The missing description is now added to source with an explicit foreground-only explanation; no background-location capability or request was added. **Build 10 does not contain that metadata correction**; include it in build 11 or later. The SDK warning needs an appropriate future Xcode upgrade.

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
  --build-name=1.0.2 --build-number=11
# UPLOAD ONLY AFTER APPROVAL; use the actual registered Android Firebase app ID.
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-staging-release.apk \
  --project rally4ever-3adaf --app "$STAGING_ANDROID_FIREBASE_APP_ID" \
  --groups r4e-internal --release-notes "Internal staging testing only"
```

For iOS, an App Store signed IPA cannot simply be installed through App Distribution. Existing approved Ad Hoc provisioning, registered tester UDIDs and signing are needed; do not create a new key/profile silently. With those approved prerequisites:

```sh
flutter build ipa --release --flavor staging \
  --dart-define-from-file=config/staging.ios.json \
  --build-name=1.0.2 --build-number=11 --export-method=ad-hoc
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

### Build 12 export questionnaire

Build 12 was initially Missing Compliance because its Info.plist does not contain an export declaration. Inspected Runner and confirmed BoringSSL is bundled through dependencies. Declared standard encryption in addition to OS encryption, with no France distribution for this Australia-only internal build. Revisit this classification before any broader distribution, changed crypto dependencies or France availability. Do not blindly add an OS-only/no-encryption assertion. [Apple documentation](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/).


## 22 November 2026 — tester-feedback build 24

Owner authorized rebuilding and uploading the current tester-fixes branch to both internal-testing stores. Source implementation: b4e8794 (including 6bd7337 About you changes), branch fix/tester-feedback-batch. Both stores were checked before build: highest observed build/code 21, so 24 was unused. Version 1.0.3, build 24 on both platforms. Existing signing keys and Apple team reused.

Commands used (explicit current Flutter SDK):

```sh
export FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./scripts/build-android-staging.sh --build-number 24
./scripts/build-ios-staging.sh --build-number 24 --export-options normal
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar --version-name 1.0.3 --version-code 24
```

**24 is now consumed; do not rerun an upload with this build number. Recheck both stores and choose 25 or higher for the next upload.**

Android AAB: build/app/outputs/bundle/stagingRelease/app-staging-release.aab, 80,272,512 bytes; SHA-256 9cd4dbcbed7bf2ad90ab61c2f6ad64c2bd8aa0c4906de38def5f0bf0ff736036. Bundletool, manifest org.raly4ever / 1.0.3 / 24, all three AOT project markers, JAR signature and existing upload-keystore match passed. Upload certificate SHA-1 11:51:C4:0F:AF:82:97:8B:80:1D:BF:D5:3F:1E:44:E7:EB:0F:AF:AD. Play Internal testing release 6 shows Available to internal testers (22 Nov, 2:15 pm); no promotion to other tracks.

iOS IPA: build/ios/ipa/rally4ever.ipa, 39,300,852 bytes; SHA-256 633f50a42d711e9354182f7df76099e36ab5e1b2bf68eebf77107321e6c9a0da. Embedded org.rally4ever / 1.0.3 / 24 and rally4ever-3adaf AOT marker verified; codesign deep/strict verification passed. Apple Distribution: Boris Ryavkin (7HGT5BT6KT). Normal ios/ExportOptions.plist used; distribution limited operationally to internal group boris, never external rally4ever.

Pre-upload checks: 211 Flutter tests passed, one existing skip; analyze clean; ten release-guard tests passed. Android Google Sign-In remains dependent on Firebase signing-certificate registration documented in SIGN_IN_METHODS.md; upload does not resolve that configuration. Prior binaries/store draft details/metadata backed up under ignored backups/release-24. No Firebase backend deployment or profile/Auth-user writes, no key generation, no purchase or additional platform fee.

iOS delivery observed in Transporter: Delivered with warning, 22 Nov 2026 at 2:16 pm; Apple processing started. The single warning is 90725 (future iOS 27 SDK requirement from April 2027); it did not block this upload. This is an upload to TestFlight, not an App Store production submission.

Final store verification: Apple processing completed. TestFlight lists build 24, Ready to Submit, expires in 90 days, group boris, one invite. No external group is assigned. The existing internal group's automatic distribution assigned the build without adding testers or changing access. Play Internal testing remains Available to internal testers. Both requested internal uploads are complete.


## Admin fixes — local review and future deployment (NOT RUN)

Source folder: `rally4ever-tester-fixes/web-admin`, branch `fix/tester-feedback-batch`.
Existing live site remains unchanged: https://rally4ever-admin-3adaf.web.app .
Local synthetic review: run `npm --prefix web-admin run dev -- --port 57830`, then open
http://127.0.0.1:57830/test/fixture.html?screen=Attendance (also Programs or Venues).
The fixture bypasses sign-in only within its separate test entry, uses fake data, and is not included in the production Vite build. Actual `/` retains Firebase admin-claim gating.

Local commands from the repository root:

```sh
npm --prefix web-admin run lint
npm --prefix web-admin test
npm --prefix web-admin run test:browser
npm --prefix functions run build
npm --prefix functions test
node scripts/test-catalogue.mjs
DEMO_PROJECT_ID=demo-rally4ever ./node_modules/.bin/firebase emulators:exec --project demo-rally4ever --only auth,firestore,functions 'npm --prefix functions run test:emulator'
node scripts/build-admin.mjs
```

Use Android Studio's bundled Java in JAVA_HOME for emulators if required. The build script reads the ignored staging web config; do not add generated Firebase config or config/*.json to Git. Browser tests use installed Chrome and synthetic fixtures, with external HTTPS blocked. Screenshots are under `docs/screenshots/admin-fixes/`.

Deploy backend and rules before the site: the new console requires these callable versions. These commands are documentation only; NO deployment was performed:

```sh
firebase deploy --project rally4ever-3adaf --only 'functions:attendance:adminProgramDeletion,functions:attendance:adminAttendanceCounts,functions:attendance:adminFindPeople,functions:attendance:adminPersonAttendance,functions:attendance:adminFindCoordinates,functions:attendance:adminCatalogue,functions:attendance:adminSaveSession,functions:attendance:adminSaveVenue,functions:attendance:listPrograms,functions:attendance:saveProgram,functions:attendance:listStaffSessions'
firebase deploy --project rally4ever-3adaf --only firestore:rules
firebase deploy --project rally4ever-3adaf --only hosting:admin
```

No index deployment or data migration is required. Rules changes are limited to event read visibility/legacy-safe coach assignment checks supporting item 2. Soft deletion writes deletedAt/deletedBy and restore metadata on programs; generated future sessions get deletedAt, retained older/manual sessions get hiddenAt; all linked sessions close registration and preserve previous coach assignments in deletion metadata. Restore is admin-only and revision checked. Audit entries use catalogueAudits. No profile, Auth user, form or attendance record is modified/deleted. Hard purge is not implemented.

Deletion blocks any history, even cancelled registrations or rejected scans. It refuses programs with over 300 linked sessions rather than checking incompletely. Session counts are bounded at 2,001 records per source and show a lower-bound marker if limited. Person search scans bounded pages, and history/CSV fetch remaining pages explicitly.

Coordinate lookup is admin-only, venue-address only, one request in flight globally, at least 1.1 seconds apart, with a 30-day cache in adminGeocodeCache and a lease in adminOperations/nominatim. Results are editable and attributed to OpenStreetMap. No autocomplete. Trusted server environment NOMINATIM_ENDPOINT can switch the HTTPS provider. Follow https://operations.osmfoundation.org/policies/nominatim/ . This feature uses existing Functions/Firestore billing; no new paid subscription was enabled and no cost was incurred by local testing.

Manual post-deploy checks: sign in as admin; Attendance → search a venue/date, use Today/All dates, select a result and Refresh/Export; Search a person → name/email → history/CSV. Programs → combine sport/status/search then refresh URL; create with blank capacity and with 20, verify visible invalid-capacity error; delete an unused program by typing its name, Show deleted → Restore; a program with history must offer Archive instead. Venues → Create → verify generated code, photo controls and explicit coordinate lookup. Verify participant and anonymous callable access remains denied. Do not deploy to any other project or Hosting target.


## 22 November 2026 — staging deployment and external-testing build 25

Owner authorized deploy/push/upload, then changed distribution preference to external testing. Branch fix/tester-feedback-batch pushed to https://github.com/borisryavkin/RALLY4EVER (through 96372e1 before this report). No production store track or App Store production submission targeted.

Deployed to rally4ever-3adaf only: the 11 admin functions listed above, firestore:rules and hosting:admin, followed by beginNoAppCheckIn, completeNoAppCheckIn and getNoAppForms. Firebase CLI confirmed all operations successful. Live admin HTML asset hashes match local dist. New five admin callables each return HTTP 401 UNAUTHENTICATED without authentication. No profiles/Auth users/forms/attendance were deleted or migrated.

Local checks on current participant changes: Flutter 228 passed, one skipped; functions unit 16 passed; callable emulator 40 passed. Admin-specific suites remain as documented above. Backups of previously dirty files in backups/deploy-20261122-151702; previous signed artifacts and documentation in backups/release-25 (ignored).

Signed staging artifacts, using existing keys, normal iOS export options:
- Android: build/app/outputs/bundle/stagingRelease/app-staging-release.aab; 80,295,774 bytes; SHA-256 dd43715855cc343640769996bfa4a61391505696ab1fb32caf858b49029ff2f1. org.raly4ever / 1.0.3 / 25. Bundletool validation, three compiled staging project markers, JAR signature and upload-key match passed.
- iOS: build/ios/ipa/rally4ever.ipa (also identical rally4ever-1.0.3-25.ipa); 39,302,913 bytes; SHA-256 6d6e3f19c4de013d258511aef4f6325e8efe677a779ef93cbd169b59d685dfeb. org.rally4ever / 1.0.3 / 25, staging project marker and deep/strict codesign verification passed. Highest observed TestFlight build before upload was 24.

Commands used:
```sh
export FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter
export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
./scripts/build-android-staging.sh --build-number 25
./scripts/build-ios-staging.sh --build-number 25 --export-options normal
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar --version-name 1.0.3 --version-code 25
```

Play accepted bundle 25 into Closed testing – Alpha, draft release 1, named “25 (1.0.3) — Tester feedback fixes”. Preview reports six setup errors: complete Dashboard tasks, full description missing, no countries selected, financial-features declaration, foreground-services declaration and health declaration. Release cannot be rolled out while these remain. Existing Internal build 24 remains unchanged. Bundle 25 is now consumed; do not upload a different bundle with the same versionCode.

Created separate TestFlight external group R4E Staging External (00913542-33dd-453d-a0e3-2e80c7cd1079), initially no testers or builds. Existing external group rally4ever unchanged. Requested tester recipients separately; no invitations sent. Transporter intake confirmed Rally4ever 1.0.3 (25), delivery started; final delivery/review outcome recorded below when available.

Apple Transporter confirmed build 25 DELIVERED WITH WARNING on 22 Nov 2026 at 3:29 pm; app processing. One warning is reported; detail not yet verified. This is a successful upload, not external-test approval. Existing Beta Review sign-in information predates the Firebase email-based app and must be verified/replaced with a working dedicated test account before review. Never put review credentials in Git.

Final observed distribution state: App Store Connect lists 1.0.3 (25) Processing; not yet available in the external build selector, so no Beta Review submission or external build assignment was possible. Owner-supplied tester added to R4E Staging External. Play has R4E Staging External email list selected for Alpha (one supplied tester), saved successfully, and Australia targeted; those two track setup tasks are complete. Remaining Google blockers: Dashboard setup, full description, financial-features, foreground-services and health declarations. No production release, public invite link or external rollout performed. Android emulator Medium_Phone_API_36.0 now runs staging DEBUG 1.0.3 (25) from current source, with automatic hot reload watcher active for lib/ and assets/.


## Venue deletion follow-up — 22 November 2026

Added reversible venue Delete/Restore with typed-name confirmation and server-side link checks. Blocks linked programs/sessions including archived history; never cascades or removes photos, attendance, profiles or Auth users. New callable adminVenueDeletion, plus updated adminCatalogue/adminSaveVenue/adminSaveSession/saveProgram deployed successfully to rally4ever-3adaf. Anonymous live probe returned 401 UNAUTHENTICATED. No rules/index changes. Local validation: 67 catalogue/rules emulator tests, 14 browser tests, 16 functions unit tests, 16 web helper tests; lint, TS and web build passed. Source commit 547c625 pushed. Backups: backups/venue-delete (ignored).

Deployment commands used:
```sh
firebase deploy --project rally4ever-3adaf --only 'functions:attendance:adminVenueDeletion,functions:attendance:adminCatalogue,functions:attendance:adminSaveVenue,functions:attendance:adminSaveSession,functions:attendance:saveProgram'
firebase deploy --project rally4ever-3adaf --only hosting:admin
```

Usage: refresh https://rally4ever-admin-3adaf.web.app → Venues → Delete → check linked-record counts → type the exact venue name → Delete venue. Show deleted venues → Restore reverses deletion. Linked venues must be reassigned before deletion; no historical records are removed. No mobile rebuild required.

Hosting deployment completed; live HTML asset hashes match the verified local build.


## Build 27 — 22 November 2026

Version `1.0.3+27`, source `fc62163`, pushed to `origin/fix/tester-feedback-batch`. Includes pickleball SVG and Australian racquets spelling. `flutter analyze` clean; 231 Flutter tests passed, one skipped.

```sh
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter ./scripts/build-android-staging.sh --build-number 27
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter ./scripts/build-ios-staging.sh --build-number 27 --export-options normal
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar --version-name 1.0.3 --version-code 27
```

Both signatures, IDs, version/build numbers and embedded `rally4ever-3adaf` verified. Android upload certificate matches existing upload key. Normal iOS export permits external testing. Copies/checksums and detailed verification are saved in `~/Downloads/Rally4Ever-1.0.3-27-external-testing/`.

Apple Transporter confirmed delivery (with one warning) at 4:34 pm Australia/Sydney; processing at last observation. External group assignment is blocked while build 25 of version 1.0.3 waits for Beta App Review. The original external `rally4ever` group was not changed.

Google Play accepted build 27, saved as the only artifact in Closed testing Alpha draft. Old bundles were removed from this draft only and remain in the artifact library. Rollout is blocked by Dashboard setup, full description, financial-features declaration, Foreground Service declaration and health declaration. Open testing remains unavailable until production access. No production rollout or backend/Hosting deployment was performed.



## Build 28 — anonymous +1

Version `1.0.3+28` includes the native **Skip details — count me as +1** option, explicitly accepted optional forms, and a persisted per-session retry token. Normal iOS export and real staging JSON configs were used. Existing identifiers and signing keys were retained. Both bundle signatures/version numbers and embedded `rally4ever-3adaf` were verified; the anonymous control is present in the IPA AOT library.

Copies and checksums: `~/Downloads/Rally4Ever-1.0.3-28-external-testing/`. IPA 39,307,976 bytes; AAB 80,308,591 bytes. Android package `org.raly4ever`, versionCode 28; iOS bundle `org.rally4ever`, build 28.

Apple's Xcode upload CLI confirmed **Upload succeeded / EXPORT SUCCEEDED** at 4:56 pm Australia/Sydney on 22 November 2026. Existing Xcode account/signing was used, without an API key or new credentials. The normal external-capable upload options used `destination: upload`, `manageAppVersionAndBuildNumber: false`, and `testFlightInternalTestingOnly: false`. Apple reported missing vendor framework dSYMs (including gRPC) as warnings; the app package upload succeeded.

Google accepted build 28 and saved it as the only artifact in the Closed testing Alpha draft. Build 27 was removed only from the draft and remains in the artifact library. No production release was created. Apple's existing build-25 beta-review gate and Play's full-description/dashboard/financial-features/foreground-service/health declarations still block external distribution.

The hosted anonymous check-in flow is already deployed and does not require the native app update. The native option requires build 28; build 27 cannot gain a new UI control from a backend deployment alone.


## Build 29 — three required agreement sections (22 November 2026)

Version `1.0.3+29`, same existing iOS/Android identifiers and signing keys. Code of Conduct includes the unchanged Waive and Release; Data Collection and Photo Release are required. Profile now has one Sign forms entry. Existing valid receipts are preserved; no historical consent is fabricated.

Build commands:
```sh
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./scripts/build-android-staging.sh --build-number 29
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter ./scripts/build-ios-staging.sh --build-number 29 --export-options normal
```

Backend deployment is limited to `rally4ever-3adaf`: attendance checkIn/addWalkIn/getNoAppForms/beginNoAppCheckIn/completeNoAppCheckIn plus Hosting checkin. No rules or legal document writes. Backup: ignored `backups/build29-three-forms/deployed/` (previous function settings, Hosting release, and all four legal documents). Earlier clients retain compatible document IDs but may display former optional labels; install build 29 for the correct three-section UI.


Verification: Android versionCode 29, package `org.raly4ever`, existing upload certificate matched, bundletool and JAR signature valid, staging marker in all three architectures; iOS `org.rally4ever` 1.0.3 (29), codesign valid, staging marker and new signing screen present in AOT binary. Reports: `docs/verification/android29-bundle.json` and `ios29-bundle.json`. Copies and checksums: `~/Downloads/Rally4Ever-1.0.3-29-external-testing/`.

Firebase deploy completed and all five functions are ACTIVE. Hosted check-in JS serves all three required agreement headings; legal document fields match the backups exactly. Unauthenticated checkIn/addWalkIn both return HTTP 401 UNAUTHENTICATED.

Play accepted build 29 and saved it as the only bundle in the existing Closed testing Alpha draft. Rollout is blocked by five Play Console requirements: Dashboard completion, full description, financial features declaration, foreground service declaration, and health declaration. No production release was created or changed.


Apple upload succeeded through `xcodebuild -exportArchive` using the existing Xcode account. App Store Connect visibly lists 1.0.3 (29), **Processing**, created 22 Nov 2026 5:30 pm Australia/Sydney. Normal external-capable export used (not internal-only). Vendor framework dSYM warnings were non-blocking. Existing external build 25 remains Waiting for Review; the original rally4ever group was untouched. Upload log: `/tmp/r4e-build29-xcode-upload.log`.


## Build 30 — reference Profile layout (22 November 2026)

Version `1.0.3+30`. Compact identity header, two attendance summaries, grouped current form receipts and session history, following Boris's supplied reference. Three required agreements and the five existing navigation tabs retained. Settings moved under Preferences; Admin and Coach tools remain available for their roles. No backend deployment/data migration required.

```sh
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./scripts/build-android-staging.sh --build-number 30
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter ./scripts/build-ios-staging.sh --build-number 30 --export-options normal
```

Android verified: `org.raly4ever`, versionCode 30, current upload keystore certificate matched, bundletool/JAR validation successful, staging project and new Profile screen present in all three ABIs. Report: `docs/verification/android30-bundle.json`. Local copies: `~/Downloads/Rally4Ever-1.0.3-30-external-testing/`, including `profile-preview.png`. Flutter analysis clean; 240 tests passed, 1 intentional skip.


Uploads completed: Apple Xcode CLI reported EXPORT SUCCEEDED; App Store Connect visibly lists 1.0.3 (30), Processing, created 22 Nov 2026 6:15 pm Australia/Sydney. Normal external-capable export, existing Apple signing. Vendor dSYM warnings non-blocking. iOS verification report: docs/verification/ios30-bundle.json. Play accepted 30 and saved it as the only bundle in the Closed testing Alpha draft (29 retained in artifact library). Five unchanged Play setup requirements block rollout: Dashboard completion, full description, financial features, foreground service declaration, health declaration. No production tracks changed. Apple external build 25 remains pending review; original rally4ever group untouched.

## 1.0.3 (32) — program refresh and map locations

Source: `3700453` on `fix/tester-feedback-batch`. Includes a server-backed Refresh programs button, retry/loading feedback, preserved catalogue filters, published program markers awaiting dated sessions, and All Australia map browsing. No synthetic sessions are created. Map camera padding adapts to small screens. Preferences and expanded age ranges from build 31 remain included.

Validation: Flutter analyze clean; 246 Flutter tests passed, one intentional skip. Reviewed and updated catalogue/map screenshot baselines. Android bundletool/JAR signatures and existing upload certificate match; staging project present in all three ABIs. iOS codesign, bundle/version, non-exempt encryption flag and staging/refresh AOT markers verified. Reports: `docs/verification/android32-bundle.json`, `docs/verification/ios32-bundle.json`.

```sh
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter \
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
./scripts/build-android-staging.sh --build-number 32
python3 scripts/verify-android-bundle.py --bundletool /tmp/r4e-bundletool.jar \
  --version-name 1.0.3 --version-code 32
FLUTTER_BIN=/Users/borisryavkin/technical/flutter/flutter/bin/flutter \
./scripts/build-ios-staging.sh --build-number 32 --export-options normal
```

Copies: `~/Downloads/Rally4Ever-1.0.3-32-external-testing/`. Android package remains `org.raly4ever`; iOS remains `org.rally4ever`. No production release or new signing keys. Uploading a tester build cannot force an installation on a tester's phone.

Google Play accepted versionCode 32 and saved it as the sole bundle in the existing Closed testing draft, named `32 - Program refresh and map`. Version 31 was removed from the draft only; its artifact remains in the library. Rollout is blocked by five account/listing requirements: Dashboard completion, full description, financial features declaration, foreground services declaration, and health declaration. No declarations were guessed or submitted.

Apple upload succeeded on 22 Nov 2026 at 20:49 Sydney time using the existing Xcode account and automatic signing. App Store Connect visibly lists **Version 1.0.3, Build (32), Processing**, created 20:49. Normal/external-capable export used (`testFlightInternalTestingOnly=false` for upload). Existing external groups were not modified while processing. Vendor-framework dSYM warnings were non-blocking; the uploader reported `Upload succeeded` and `EXPORT SUCCEEDED`. Android draft and Apple receipt were verified in their store consoles; neither is a production release.

## 1.0.3 (33) — Back returns to Play

Source `6207aac` includes `697a242`: program detail Back, including the unavailable-program fallback, now returns directly to Play. The 12 catalogue tests passed, including the navigation regression; Flutter analyze is clean. Existing build-32 refresh/map features remain included.

Built using `scripts/build-android-staging.sh --build-number 33` and `scripts/build-ios-staging.sh --build-number 33 --export-options normal`, with existing signing and the real staging configs. Package IDs unchanged. Verification reports: `docs/verification/android33-bundle.json`, `docs/verification/ios33-bundle.json`. Copies/checksums: `~/Downloads/Rally4Ever-1.0.3-33-external-testing/`.

Android: build 33 was accepted and saved in the Closed testing draft; external rollout remains blocked by the existing five app setup requirements. The same verified uploaded bundle was then added from the artifact library to the existing **Internal testing** track and **published at 22:31 Sydney time, 22 Nov 2026**. The console confirms `Active Latest release: 33 - Return to Play` and `Available to internal testers`. Previous build 24 is replaced on that track. Existing tester lists/access are unchanged. Opt-in link: https://play.google.com/apps/internaltest/4701651234356647750 . Play warns propagation may take one hour or occasionally longer. Production was not targeted.

Apple: CLI upload succeeded at 22:30:49 Sydney time on 22 Nov 2026 (`Upload succeeded`, `EXPORT SUCCEEDED`). Normal/external-capable export; existing Apple signing. Non-blocking vendor dSYM warnings remain.

TestFlight publication: verified build **1.0.3 (33) — Testing** in the existing internal `boris` group. Removed the superseded build 25 from Beta App Review (did not expire or delete the build), then selected build 33 for **R4E Staging External**, added focused test notes, left automatic tester notification enabled, and submitted for review. The external group's build list confirms **1.0.3 (33) — Waiting for Review**. Build 25 remains in that group as Ready to Submit; its tester history is preserved. The original `rally4ever` external group was not changed. External availability now depends on Apple's approval; internal testing is live.
