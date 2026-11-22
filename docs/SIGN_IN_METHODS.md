# One account with Google and email

Google sign-in does not give Rally4Ever the person's Google password. A Google-created account can set its own app password through **Me → Sign-in methods → Enable email sign-in**. Recent Google verification is requested on the same UID when Firebase requires it. Passwords are sent only to Firebase Auth, never Firestore or logs. Roles/profile/RSVP/check-ins stay on the original UID.

A verified password-first member can choose Continue with Google using the same email: Firebase links the trusted identity to the existing UID. `account-exists-with-different-credential` retains the pending credential only in memory and asks for the existing app password; it is linked only after successful authentication of the matching email. Wrong-account collisions are rejected; no account/profile is deleted or merged automatically. An unverified password-only identity may have its old password removed by Firebase when ownership is proven through Google; set a new app password after Google sign-in in that case.

`registerIdentity` continues to use the authenticated, verified normalized email and a transaction on emailIdentities. Existing different-UID mappings, merged profiles needing manual resolution, disabled users and credentials already owned by another UID are not silently linked. Admin merge remains a dry-run/review workflow.

The real project account-linking setting is applied through Identity Platform PATCH `signIn.allowDuplicateEmails=false` (with the quota-project header); no account or password was changed by that operation. Equivalent console path: Firebase Console → Authentication → Settings → User account linking → Link accounts that use the same email. Email/password was already enabled. API responses are reduced to booleans; never embed project Admin config/hash parameters in a client.

Emulator proofs cover Google-first → set password → both logins, verified password-first → Google → password, and an existing Google credential owned by another UID being rejected. UID, claims, profile, RSVP and email mapping are retained. Native Google device OAuth is still a hardware/manual check. This source change is not in TestFlight build 12; it is included in the next requested participant build.


## Android tester audit — 22 November 2026

`google_sign_in` is **7.2.0**. Existing `ensureGoogleSignInInitialized` caches a single initialization future, starts in repository.restore at app startup, and is awaited by authenticate. It uses the `GOOGLE_SERVER_CLIENT_ID` dart define, with the existing public Web OAuth client ID as fallback. Both ignored staging platform configs were verified/updated to the client_type 3 value in the current SDK download. No service-account key, password or secret was hardcoded. The existing all-code exception mapping is retained and now renders a neutral cream/navy banner and navy actions, including canceled/code 16, with details only in debugPrint.

`android/app/google-services.json` was missing in this worktree. Downloaded the existing app's SDK config (read-only Firebase Management API; no Firebase mutation) into that ignored location. Its package is **org.raly4ever**, a client_type 3 Web OAuth entry exists, and **certificate_hash entries are empty**. Firebase's certificate list for that same Android app is also empty. Web client ID (public): `55117668228-rf3r7a555us3ueufb73q122pej0bqe4h.apps.googleusercontent.com`.

All four local certificate fingerprints below are missing from Firebase:

| Key | Algorithm | Fingerprint |
| --- | --- | --- |
| Upload | SHA-1 | `11:51:C4:0F:AF:82:97:8B:80:1D:BF:D5:3F:1E:44:E7:EB:0F:AF:AD` |
| Upload | SHA-256 | `FD:8C:AD:E2:B0:13:8F:2B:F4:76:66:24:D5:C6:6E:EF:7A:0D:9E:1D:02:39:08:41:46:BF:23:D3:1C:87:0D:AB` |
| Debug | SHA-1 | `91:79:EB:71:A2:8A:BD:AA:88:BC:6B:B8:AD:8D:B1:79:89:89:DE:32` |
| Debug | SHA-256 | `0B:AE:C9:F8:78:C8:CD:9E:85:2E:BF:D9:5D:65:F7:BF:C5:B3:1D:8E:8C:7F:52:AD:99:9D:21:24:91:21:4E:E6` |

Upload values were read using keytool against the existing upload keystore without printing passwords. Debug values were read from `./gradlew signingReport` (stagingDebug). No signing key was generated or changed. Add these under Firebase Project settings → General → Android **org.raly4ever** → SHA certificate fingerprints. Also add the separate **Play app-signing** SHA-1/SHA-256 from Play Console → App integrity → App signing; it cannot be derived from the local upload/debug keystores. Local upload fingerprints identify the upload key, not Play's signing key.

Re-download google-services.json after registering the fingerprints. The just-downloaded file still has no Android OAuth/certificate entries. No provider settings, certificate registrations, profiles, Auth users, releases or uploads were changed by this audit. Google device sign-in is not proven fixed until the signing fingerprints are registered; canceled/code 16 does not establish user cancellation.


## 22 November 2026 — configuration corrected and entry unified

Unsigned app launches now open Welcome back on both platforms, independent of the device's hasSignedInBefore history. Create account still opens the same shared entry/email verification/seven About you steps. The original difference came from local first-install history, not separate platform sign-up implementations. Brand back icons now use the iOS rounded chevron on both platforms, with explicit standard density and padded touch targets; OS Google account pickers/keyboards retain native behavior. Forty phone/tablet sign-up renders are compared between iOS and Android in signup_platform_parity_test.dart. Full Flutter suite: 230 passed, one skipped; analyze clean.

Firebase Management API read confirmed ZERO SHA entries for Android org.raly4ever. Added existing debug and upload SHA-1/SHA-256, then downloaded Play's public certificates from App signing. Added all three supplied Play signing certificates (deployment, hybrid classical and hybrid PQC), both SHA types, for ten total verified entries. Re-downloaded ignored android/app/google-services.json; it now contains the matching Android OAuth clients as well as the existing Web client. No keys were generated and no Auth user/profile was deleted. Config and certificate backups are ignored under backups/android-google-20261122. Native Google account selection is still an interactive device check; do not mistake configuration validation or unit tests for an end-to-end Google login.

Play certificate fingerprints registered:

| Certificate | SHA-1 | SHA-256 |
|---|---|---|
| Deployment | 90:51:FE:CD:0A:64:51:B9:A4:98:67:9E:52:C9:37:25:8C:BE:20:F2 | 27:10:CE:16:BC:A6:C5:4F:C6:13:FF:D2:AC:4D:03:22:59:83:E3:80:34:76:3B:76:75:00:BB:44:3E:6E:CC:C2 |
| Hybrid classical | 94:FD:C0:78:A5:4C:A1:97:79:3C:89:E5:6D:AE:54:3B:20:7A:AC:FB | EF:CA:78:C5:5B:2F:75:EF:3B:1F:68:D2:33:B2:08:26:A8:09:15:43:D5:89:4F:94:3B:50:74:A9:81:36:A5:97 |
| Hybrid PQC | 0D:E2:69:B2:7B:DC:41:2C:9E:09:23:BD:88:B3:61:1F:2E:71:D8:83 | D7:B6:31:33:D9:FC:AD:99:8F:4A:0A:89:16:AF:95:21:15:66:87:08:40:12:DE:82:96:09:B9:B0:1C:A9:47:81 |

Sign-in logs also revealed registerIdentity HTTP 400: the deployed function still accepted only the older payload while clients send firstNameHint. Deployed the existing tested compatible registerIdentity implementation to rally4ever-3adaf. Client fallback for older functions remains. No weakening of verified-email checks or duplicate-profile protections.
