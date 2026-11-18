# Local development and manual setup

## Local only — no Firebase account or billing required

Use Node 24 (`.nvmrc`), Java 21, the installed Flutter SDK and package lockfiles. Install Node dependencies with `npm ci` and `npm --prefix functions ci`; Flutter dependencies with `flutter pub get`. The npm CLI tooling currently has 13 moderate transitive advisories after nonbreaking audit fixes; no high advisories remain. A scoped gRPC override updates the JS Firestore client's old 1.9.x pin to compatible 1.14.x. Avoid `npm audit fix --force`, which proposes incompatible Firebase downgrades. Reassess tooling advisories before deployment. No Node package is shipped with the Flutter UI in this stage.

Start Auth (9099), Firestore (8080) and Functions (5001) emulators:

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
npm run test:functions
npm run test:all:emulator
```

Tests deliberately clear **local demo Firestore data** in their isolated run. Seed and tests reject absent/nonlocal emulator hosts, unexpected project IDs and Google credential-file configuration. npm scripts specify the demo project explicitly. The Firebase CLI will download emulator binaries on first run.

The app entry now connects `lib/data/emulator_backend.dart` to the participant UI only with `USE_FIREBASE_EMULATORS=true`; otherwise authentication is disabled. Direct backend initialization without explicit opt-in throws. By default only `127.0.0.1`, `localhost` and Android-emulator host `10.0.2.2` are accepted. Firestore disk persistence is disabled. The explicit development LAN mode below adds a private-IP opt-in. There is no production initialization fallback.

Participant UI now uses actual emulator authentication and data. The old email-only navigation paths are removed. Chrome UI integration exercises Auth/Firestore/Functions; native device OAuth and camera/GPS integration still require the platform setup below.

## Manual steps later — none required for this stage

- Create/register a Firebase project/apps when deployment planning is approved. Stay on Spark for now. Configure authorized auth providers/domains deliberately; do not change a deployed provider without approval. New-account provisioning is a trusted local callable, not a Firestore client write; deployment is not authorized.
- Review current Blaze/Functions/scheduled-job costs before any deployment; present AUD estimate and free emulator alternative, then wait for approval. Do not enable billing now. AUD $100 total cap; arrange AUD $20 budget alert with authorized billing access before billed services. Alert is not a hard spending limit.
- Supply APNs key/capabilities and configure FCM for iOS, Android and browser push; web service worker/VAPID; test physical device delivery. Emulators do not deliver real FCM pushes.
- Verify control of `rally4ever.org`; plan Firebase Hosting DNS/HTTPS and iOS/Android link associations. Any purchase or paid change needs advance approval. Use emulator URLs meanwhile.
- Supply approved form content, current versions, coach assignments, exact venue coordinates, event times/timezones and published app-store links. Approximate discovery coordinates must not become trusted geofence centers.
- For stores, supply signing/release access and authorize any account fees before payment. iOS camera usage text and native app links will be added with scanner integration.
- For legacy import/merge, supply old Admin app source/schema or sanitized export. Review dry-run report, backup and rollback strategy; explicit approval is required before real-data writes or deletion. The old duplicate bug remains unverified. Local normalized-email concurrency and merge tests pass; see `FUNCTIONS.md` for dry-run defaults and apply safeguards.
- Existing program JSON assets remain absolute symlinks to another local folder. Make them portable in a separate reviewed source-data change before a clean-machine app build; stage 3 does not change those assets.

## Functions-stage notes

See `FUNCTIONS.md` for all seven callable contracts, the Firestore trigger and the five-minute scheduler. Identity document IDs now use normalized email rather than the historical stage-3 hash; reset disposable old emulator fixtures if necessary. No production data was migrated.

FCM is a deterministic local delivery double (`emulatorPushes`), with no real sends. Scheduler handler tests invoke the actual SDK `.run` handler against emulator data because CLI 15.36 cannot dispatch v2 scheduled HTTP signatures through its Pub/Sub adapter. No Pub/Sub emulator or paid Scheduler service is required for the current test command. Real push setup remains a later manual step.

The Functions package passes npm audit with zero vulnerabilities at implementation time. Root local CLI-tooling advisories remain as documented above. No native UI or account provider settings changed.

## Participant app and Google Workspace access

```sh
npm ci
npm --prefix functions ci
npm run emulators
# In another terminal, seed with the two emulator environment variables above.
flutter run -d chrome --web-port 7357 --dart-define=USE_FIREBASE_EMULATORS=true
```

Without `USE_FIREBASE_EMULATORS=true`, the app can show its introduction but cannot authenticate or write data. All Firebase SDKs use the named demo app and explicit local Auth/Firestore/Functions endpoints. Android emulator host uses `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`; physical LAN hosts remain blocked unless the development-only opt-in below is enabled.

Email/password sign-up sends a **local emulator verification link**; open/copy it from the emulator terminal, then return to the app and tap “I've verified my email”. No SMTP or real email service was enabled. There is no email-link ("magic link") sign-in — only email/password and Google. Forgotten passwords use "Forgot password?" on the sign-in screen, which calls Firebase's `sendPasswordResetEmail`; the emulator prints the reset link to the terminal the same way it prints verification links.

“Continue with Google” on Flutter Web uses Firebase Auth's emulator provider popup. Select the seeded Workspace account to use its existing UID. Workspace users without the admin-issued coach claim remain participants and see “Ask your admin for coach access”. An admin signs in with the seed admin account, opens Admin view → Manage users & event coaches, searches by email, supplies a reason, grants/revokes coach access and assigns event coaches. The recipient can refresh access without creating another profile. A dual-role account switches back to participant view without signing out.

Native Android/iOS Google authentication is wired through `google_sign_in`. Before **device** testing, supply the platform OAuth client configuration (and `GOOGLE_SERVER_CLIENT_ID` where required), Android signing fingerprints and iOS URL scheme/client IDs. These settings are not included or provisioned here. Only browser Google emulation and native widget rendering have been tested; real Google device OAuth, camera/GPS hardware, APNs and store release testing remain manual. Firebase Auth still points only to emulators in this build. No production provider was enabled.

Run the full validation:

```sh
flutter analyze
flutter test
npm run test:functions
npm run test:all:emulator
npm run test:participant:e2e
```

The browser end-to-end test uses a fresh seed and an injected court GPS fix (not physical GPS). All Auth, RSVP, forms, Functions and Firestore confirmation updates are real emulator interactions. Camera acquisition is replaced by pasting the exact coach-generated QR deep link through the same parser. It verifies that intent creates no attendance and that the participant sees the coach-confirmed state live. Browser widget tests explicitly register web Firebase plugins; no production backend is used.

Program JSON assets are now real app-local files, replacing the original absolute symlinks while retaining their contents. Inter/Figtree variable fonts and OFL notices are bundled locally from [Google Fonts](https://github.com/google/fonts/tree/main/ofl). Screen captures and their exact scope are indexed in `SCREENSHOTS.md`.

## Staging data seed (real Firebase project, no emulator)

`scripts/seed-staging.mjs` writes small synthetic data directly to the real `rally4ever-3adaf` Firestore/Auth, using [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials) — run `gcloud auth application-default login` with an account that has access to the project first (or supply a service account via `GOOGLE_APPLICATION_CREDENTIALS`, which ADC also honors). It is hardcoded to `rally4ever-3adaf`; no env var can redirect it to another project, and it refuses to run if `FIRESTORE_EMULATOR_HOST`/`FIREBASE_AUTH_EMULATOR_HOST` are set or if `GCLOUD_PROJECT`/`GOOGLE_CLOUD_PROJECT` point elsewhere.

```sh
npm run seed:staging
```

It creates, all tagged with `seedSource: 'scripts/seed-staging.mjs'`:

- 2 coach and 3 participant Auth accounts under `@rally4ever-staging-seed.test` (password `Staging-seed-only-Password-123!`), with matching `users`/`emailIdentities` profiles.
- Current `forms/conduct` and `forms/waiver` documents (version 1).
- 3 upcoming `events` (two venues: Waverley Park Courts and Addison Road Courts) and 2 past `events` with confirmed `checkins` and `feedback` from two seed participants each.
- A matching `eventSecrets` document per upcoming event, hashed the same way `rotateEventSecret` does. The printed plaintext secret is only valid for 5 minutes (or until the event ends), same as a real rotation — it is for an immediate test scan, not a durable QR code. Trigger a normal in-app coach "start session" rotation for anything beyond that window.

**Before writing anything**, it reads the `users` and `events` collections. If any `events` document was not created by this script, it refuses outright — this script never seeds on top of existing program data. If any `users` document is foreign (not seed-tagged) and its `emailLower` is not in `SEED_ALLOW_EMAILS` (a comma-separated allowlist for your own pre-existing test accounts), it refuses with the list of offending document IDs rather than writing anything:

```sh
SEED_ALLOW_EMAILS="you@example.com,other-test@example.com" npm run seed:staging
```

It is idempotent: every document/account write is create-only (matching `scripts/seed.mjs`'s convention), so rerunning fills in anything missing without overwriting or duplicating existing seed data. Rerunning does **not** issue a fresh QR secret for an event that already has one — use the in-app rotation for that.

**How the 5 seed accounts authenticate, and whether that's safe to leave on a real project:** they are real email/password Auth accounts (`emailVerified: true`) on `rally4ever-3adaf`, not emulator fixtures, sharing one hardcoded password (`Staging-seed-only-Password-123!`, visible in `scripts/seed-staging.mjs` in source control). Their `@rally4ever-staging-seed.test` addresses use the `.test` TLD reserved by RFC 2606 as non-resolvable, so no one can receive mail there, register that domain, or get a password-reset email for one of these accounts — but **anyone who has read this repo already knows the password** and can sign in as one of these 2 coach / 3 participant accounts on the real project right now. Blast radius is limited (no admin account is seeded; a coach session only sees what `visibleToCoachUids` and the seeded events/catalogue expose), but it is not zero — e.g. Functions quota usage, or exposure of real participant contact details, if one of these seed UIDs is ever (even by mistake) assigned as a coach on a real event. Treat it the same as a shared staging credential: fine to leave running briefly for a specific test, not something to seed and forget. Prefer deleting the 5 seed Auth accounts and their Firestore documents (all tagged `seedSource: 'scripts/seed-staging.mjs'`) once you're done with them, rather than leaving them live indefinitely.

## Granting the first admin on staging

There is no in-app way to create the first admin: `setUserRole` (the admin console's only role-granting callable) explicitly refuses anything but a coach grant, and requires an existing admin to call it. `scripts/bootstrap-admin.mjs` is the one-time, out-of-band bootstrap for that — it grants the admin role to one **existing** Auth user on `rally4ever-3adaf` by email, using the same Application Default Credentials and real-project-only guards as `seed-staging.mjs` (hardcoded project ID, refuses if any emulator env var is set or `GCLOUD_PROJECT`/`GOOGLE_CLOUD_PROJECT` point elsewhere).

It does not create an account — the target email must already have signed in at least once (so the Auth user and its `users/{uid}` Firestore profile both exist) — and it sets both the Auth custom claim (`role`/`roles`, which the app reads for UI routing) and the Firestore profile's `role` field (which Firestore rules and Functions prefer over the claim), so the grant takes effect in both places. It also preserves any existing coach grant and writes a `roleAudits` entry so the grant is visible in the same audit trail as callable-driven role changes, tagged as having run outside the app.

Exact order for a fresh staging project:

```sh
# 1. Sign in at least once in the app with the account that should become admin
#    (creates the Auth user and its users/{uid} profile).
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=false   # or a built staging app

# 2. Grant that account the admin role.
npm run bootstrap:admin -- you@example.com

# 3. (Optional) seed synthetic coach/participant/event data -- see above.
SEED_ALLOW_EMAILS="you@example.com" npm run seed:staging

# 4. Sign out and back in (or just reload) so the app picks up the new claim.
```

Step 4 matters because the client only re-reads the role claim via a forced ID-token refresh on sign-in/`refreshAccess()` (`lib/participant/repository.dart`'s `_refreshClaims`) — a tab left open through step 2 will not see the grant until it signs out and in again.

## Opt-in phone testing over local Wi-Fi (development only)

LAN testing is **off by default**. `firebase.json` continues to bind to loopback. The separate launcher requires `LAN_TESTING=true` and a canonical RFC1918 IPv4 address actually assigned to the Mac: `10.x.x.x`, `172.16.x.x`–`172.31.x.x`, or `192.168.x.x`. It rejects public IPs, names/URLs, wildcard addresses as client targets, production credentials and every project ID except `demo-rally4ever`. The app also rejects LAN settings in profile/release builds. The Android emulator's existing `10.0.2.2` loopback alias is unchanged.

Use the **same Flutter SDK executable** for `flutter pub get`, `flutter run` and tests. If you switch SDK checkouts, regenerate `.dart_tool` with that SDK's `flutter pub get`; mixing a package config from one checkout with another checkout's engine can cause missing framework symbols. Do not combine this with a production/staging project configuration.

1. Put the Mac and phone on the same trusted Wi-Fi. Get the Mac's Wi-Fi IPv4 address (usually `en0`):

   ```sh
   ipconfig getifaddr en0
   ```

   If Wi-Fi is on another interface, use the IPv4 address shown in macOS System Settings → Wi-Fi → Details → TCP/IP. The launcher checks that the address belongs to this Mac, so supplying the router's address will fail.

2. In terminal 1, from this app directory, start the explicitly opted-in emulators:

   ```sh
   export LAN_HOST="$(ipconfig getifaddr en0)"
   LAN_TESTING=true LAN_HOST="$LAN_HOST" npm run emulators:lan
   ```

   Stop any existing emulator instance yourself first if these ports are occupied. The launcher does not kill other processes or clear their data. It builds Functions, generates an ignored `.firebase.lan.generated.json`, then starts **only** demo Auth (9099), Firestore (8080) and Functions (5001) with `host: 0.0.0.0`. The privileged emulator UI (4000), hub (4400) and logging service (4500) remain on loopback. The normal config file is never rewritten. The generated config is removed on normal exit; after a force-kill, remove only that stale generated file before restarting the launcher.

3. In terminal 2, seed through the Mac's loopback endpoints:

   ```sh
   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
   npm run seed
   ```

4. In terminal 3, run a **debug web app** on port 57602:

   ```sh
   export LAN_HOST="$(ipconfig getifaddr en0)"
   flutter pub get
   flutter run -d web-server \
     --web-hostname 0.0.0.0 \
     --web-port 57602 \
     --dart-define=USE_FIREBASE_EMULATORS=true \
     --dart-define=LAN_TESTING=true \
     --dart-define=LAN_HOST="$LAN_HOST" \
     --dart-define=FIREBASE_PROJECT_ID=demo-rally4ever
   ```

   Open `http://<Mac-Wi-Fi-IP>:57602` on the phone, for example `http://192.168.1.50:57602`. `0.0.0.0` is a bind address, not the address to open on the phone. The app connects Auth/Firestore/Functions to exactly the supplied `LAN_HOST`; it does not automatically discover a server or fall back to production. If you also set `FIREBASE_EMULATOR_HOST`, it must match `LAN_HOST` exactly.

The app displays a persistent **LAN TESTING — DEVELOPMENT ONLY** warning on every screen, including sign-in. `0.0.0.0` listens on all Mac interfaces: use synthetic/demo accounts only, a trusted router/firewall and no port forwarding. Allow the required local development processes through the Mac firewall if prompted; do not disable the firewall globally. No billing or cloud services are enabled by this mode.

The no-app check-in service's own one-time verification link uses the phone-reachable Auth emulator origin in LAN mode; that link is still a local emulator link, not a real email. Copy the unconsumed emulator link into the original phone tab's field as described above; do not use `localhost`/`127.0.0.1` on the phone to refer to the Mac.

### Camera and location on the phone

**Camera scanning and browser geolocation will not work over plain `http://<private-IP>`**, even on your own Wi-Fi. Browsers require a secure context for those APIs; the localhost exception applies to the device's own localhost, not another computer's private IP. HTTP LAN mode is useful for layout, sign-in, role switching, profiles and event/intent screens. It does not bypass location checks or invent a GPS fix to make attendance succeed. See [MDN camera requirements](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) and [secure-context restricted features](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Secure_Contexts/features_restricted_to_secure_contexts).

For real camera/location testing, use a separately configured, approved **HTTPS staging build** with an HTTPS backend, or a carefully configured, access-controlled HTTPS reverse proxy/tunnel. An HTTPS tunnel for the web port **alone** is insufficient: HTTPS pages can block calls to the HTTP emulator endpoints as mixed content. Do not expose unprotected emulator APIs/UI through a public tunnel or disable browser security. This strict LAN build intentionally does not accept public tunnel hostnames or real staging/production project IDs; secure proxy/staging support needs a separate reviewed configuration. No tunnel, certificate, staging project or paid service has been provisioned here.

### Return to the normal loopback mode

Stop the LAN app and emulator launcher with Ctrl+C. In terminals where you exported settings:

```sh
unset LAN_TESTING LAN_HOST
npm run emulators
# In another terminal, without LAN defines:
flutter run -d chrome --web-port 7357 --dart-define=USE_FIREBASE_EMULATORS=true
```

There is no persistent LAN preference or change to the standard emulator bindings. `npm run test:lan` tests the launcher/configuration guards; the Flutter and Functions tests cover private-address validation, project rejection, release-mode denial and the persistent banner.
