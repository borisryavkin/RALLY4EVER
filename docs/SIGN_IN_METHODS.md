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
