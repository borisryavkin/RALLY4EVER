# Build 6 internal tester upload — 18 November 2026

Owner explicitly requested build 6 uploaded to TestFlight first, then Android. Uploaded the existing validated Stage 7 artifacts without rebuilding or changing signing/IDs.

| Platform | Build | Observed result |
|---|---|---|
| iOS | `org.rally4ever`, `1.0.1 (6)`, app `6816826035` | Transporter confirmed delivered at 23:20 Sydney time. App Store Connect subsequently displayed Build 6 Internal, Missing Compliance, expires in 90 days. Upload completed; export-compliance declaration and internal-group assignment remain outstanding. |
| Android | `org.raly4ever`, `1.0.1`, code `6` | Play Internal testing displayed Active, latest release `1.0.1 (6) staging internal`, Available to internal testers, released 18 Nov at 23:25. Release ID `2`. |

- iOS SHA-256: `e19bace0e0d697d72bfa38beb81b8a75609fd613f463c1e4ba4160c98bed2cf7`. Verified embedded ID/version/build and `testFlightInternalTestingOnly=true`, team `7HGT5BT6KT` before upload.
- Android SHA-256: `0fdd98a7e2588d782f1036e4c28136f6971142dc4e96dd4e2c77241511ed49f7`. JAR signature verified; Google accepted code 6 with mapping and native symbols.
- Apple delivery warning `90725`: current artifact uses iOS 26.2 SDK; Apple's notice requires iOS 27 SDK/Xcode 27 starting April 2027. This was a warning, and delivery/processing succeeded.
- Android release notes describe staging features and disclose that coach Google sign-in requires configured OAuth. No production promotion or external TestFlight distribution was performed, and no invitations were sent.
- The internal group creation dialog did not accept text through the available Safari controls; it was cancelled, so no new internal group or tester assignment is claimed. Complete the compliance declaration for build 6, then create `R4E Staging Internal` with automatic distribution off and assign only this build and authorized internal testers. Do not use the existing external `rally4ever` group.
- No backend deployment, data import, fee, billing change, or new signing key in this upload task. Pre-build validation is recorded in CHANGELOG Stage 7. Local unrelated edits were preserved; the current uncommitted Android Gradle ID differs from the accepted artifact, so review it before any future rebuild. Build 6 is consumed; the next upload must use at least build 7 after rechecking both consoles.

---

# Internal tester upload record — 17 November 2026

The owner explicitly authorized “upload them all”, then specified Android package `org.raly4ever`. This package spelling supersedes the earlier assumption `org.rally4ever` for Android only. iOS remains `org.rally4ever`.

| Platform | Build | Destination | Observed result |
|---|---|---|---|
| iOS | `1.0.1 (5)`, `org.rally4ever` | App Store Connect app `6816826035` | Transporter displayed Delivered on 17 Nov 2026 at 20:38 Sydney time; Apple processing pending at observation. |
| Android | `1.0.1`, versionCode `5`, `org.raly4ever` | Play app `4975028595777084434`, Internal testing track `4701651234356647750` | Console displayed Active, Latest release `1.0.1 (5) staging internal`, Available to internal testers, released 17 Nov at 20:48. |

Android internal release: <https://play.google.com/console/u/0/developers/7292670672170071418/app/4975028595777084434/tracks/4701651234356647750?tab=releases>

The iOS exported IPA's `ExportOptions.plist` has `testFlightInternalTestingOnly=true`, team `7HGT5BT6KT`, method `app-store-connect`. No external TestFlight group assignment was performed. Processing completion and assignment to a new internal TestFlight group were not verified in this task. The existing external group `rally4ever` was untouched.

The Android app was created in Play Console by the owner while this task was running. An initial stale dashboard link for the removed app produced error `64B9F48A`; the developer account home worked and initially showed no apps. The new app record and Internal testing form subsequently became available. The release is on Internal testing only; no promotion to another track was performed. Tester-list membership and actual device installation remain unverified; no invitations were sent.

## Android package correction and validation

- Corrected Android `applicationId` to owner-specified `org.raly4ever`. Kept source namespace and resolved MainActivity as `org.rally4ever.MainActivity`, and left the iOS bundle ID unchanged.
- Created the matching Firebase Android client `1:55117668228:android:effa8a7b07f1dbd52607d1` in `rally4ever-3adaf`, without removing the previous client or deploying backend code. Updated only ignored `config/staging.android.json`; no credentials or keys committed, no new signing key generated.
- Built with the existing upload-key configuration. Gradle generated the signed AAB successfully, but Flutter exited 1 at its final post-build check because the local SDK lacks Android command-line tools/`apkanalyzer`. Its generic message said native symbols could not be stripped; the actual bundle was checked independently instead of disabling that check.
- Jarsigner verified the signature. NDK `llvm-readelf` verified zero `.debug_*` sections in packaged `libapp.so` and `libflutter.so` for arm64-v8a, armeabi-v7a and x86_64; each has corresponding separate `BUNDLE-METADATA` symbols. The packaged manifest reports `org.raly4ever`, version `1.0.1`, code `5`. Play accepted the bundle and displayed its native debug symbols and ReTrace mapping attachment.
- SHA-256 observed for the corrected AAB before upload: `9042a13a6bbf6ee02e65e9fa43bd6f1de40ec5cc7ed231ea7db8dea5d85bb4ff`.
- `flutter analyze --no-pub`: clean; `flutter test --no-pub`: 57 passed, one browser-only test skipped. No Dart behavior changed for this Android package correction.

The Android release notes explicitly disclose that Google coach sign-in is not configured for this Android build. The ignored Android OAuth client values were still placeholders during packaging. App links require the corrected package in the website assetlinks file, along with the Play app-signing certificate; only the repository template changed here, not the website.

No store upload fee or other payment was made. No production release, backend deployment, billing upgrade, password change or legacy data migration was performed by this upload task. Internal tester email-list enrollment and the new TestFlight internal-group assignment were not verified. Concurrent backend/signing/client-error-handling edits from other work remain outside this task's commits.
