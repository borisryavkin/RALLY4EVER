# Cloud Functions contract — emulator-only review

All exports live in `functions/src/index.ts`, TypeScript with strict checking, Node 24, region `australia-southeast1`. There is no deployment in this stage. Every entry point refuses to execute outside `FUNCTIONS_EMULATOR=true`, `demo-rally4ever` and the exact local Auth/Firestore hosts. No Functions build here is production-ready to deploy: this guard and the local push double are intentional.

## Calling and authentication

Callable URL prefix: `http://127.0.0.1:5001/demo-rally4ever/australia-southeast1/`. Use Firebase callable protocol/SDK, with an Auth emulator ID token. All seven require verified email. Do not trust a UID or role from request data: actor UID/email/claims come from verified callable context. Protected profile role overrides a stale claim. Participants cannot use coach/admin operations. Merged or unprovisioned actors are denied except for `registerIdentity`.

Payloads reject unexpected keys. Event IDs/codes and form IDs use ASCII letters, numbers and hyphens (max 128); UIDs must be nonempty, max 128, with no slash or whitespace. Email validation accepts ordinary ASCII addresses, trims and lowercases them, and excludes `/` so the address can be the exact identity document ID. Domain/provider-specific alias rewriting (dots, plus tags) is deliberately not performed.

**Schema adjustment requested in this stage:** `emailIdentities/{normalizedEmail}` replaces the stage-3 SHA-256 key contract. All new fixture/provisioning paths use literal normalized email IDs. There is no live schema migration. Discard/reseed disposable old emulator data rather than mixing both key formats. There is no public email lookup endpoint.

## Callable inputs, outputs and errors

Standard errors are Firebase `HttpsError` codes. Clients branch on `error.details.reason` for precise UI states; SDKs may prefix codes with `functions/`. Transport returns uppercase gRPC status names such as `FAILED_PRECONDITION`. Timestamps returned to clients are ISO-8601 strings. Persisted timestamps are Firestore Timestamps.

Common errors across callables:

| Code | `details.reason` | Meaning |
| --- | --- | --- |
| `unauthenticated` | `sign-in-required` | No authenticated caller. |
| `permission-denied` | `email-unverified` | Auth context lacks a verified email. |
| `failed-precondition` | `emulator-only` | This build was invoked outside its local demo environment. |
| `failed-precondition` | `inactive-profile` | Profile missing or merged; register/resolve identity first. |
| `invalid-argument` | `invalid-input`, `invalid-id`, `invalid-email`, `invalid-location`, `unknown-field` | Invalid field/type/value or extra key. |
| `permission-denied` | `event-role-required`, `admin-required` | Caller lacks required protected role/event assignment. |
| `not-found` | `event-not-found`, `checkin-not-found`, `profile-not-found` | Requested record absent. |
| `internal` | `internal-error` | Unexpected storage/Auth error; message omits private details. Retry safely. |

### `registerIdentity`

Input: `{email?: string}`; defaults to caller's verified email. Rechecks the Auth record's current email, verification and disabled state. Transactionally reads/reserves `emailIdentities/{normalizedEmail}` and creates `users/{authUid}` only when needed; roles default to participant. Existing trusted roles are preserved. Repeated/concurrent calls resolve the same identity.

Output: `{uid, created: boolean, requiresSignIn: boolean}`. If an admin merge has mapped an old verified account email to another canonical UID, return that UID with `requiresSignIn: true`; **do not mint a token or grant access as the target account**. Sign in/recover the canonical account separately. Auth providers and credentials are not merged or deleted.

Additional errors: `permission-denied / email-mismatch` (requested/current/verified address mismatch), `failed-precondition / identity-conflict` (corrupt/inactive mapping or conflicting profile). Concurrent Auth sign-ups with the same email are already constrained by Auth; Firestore transaction tests additionally race two candidate UIDs and real repeated register calls.

### `rotateEventSecret`

Input: `{eventId}`. Assigned coach or admin, published event that has not ended. Uses 32 random bytes, stores SHA-256 only, increments generation; previous secret becomes invalid immediately. New secret expires in five minutes or at event end, whichever comes first.

Output: `{eventId, eventCode, url, secret, generation, expiresAt}`. URL is `https://rally4ever.org/c/<eventCode>?k=<secret>`. Returning a real HTTPS deep-link string does not configure or purchase the domain. The future coach UI must request rotation before expiry; no UI is added here.

Additional errors: `failed-precondition / event-unavailable` for unpublished/ended event. Secrets are never client-readable Firestore fields.

### `checkIn`

Input: `{eventCode, secret, lat, lng, method?: 'app'|'camera'}`; method defaults to app. Identity comes exclusively from Auth. Resolves a unique event code and transactionally validates the published event, window, rotating secret, finite coordinates, distance, current form receipts, profile details and absence of `checkins/{eventId}_{uid}`.

Window is inclusive from start minus ten minutes through event end. Radius defaults to 150 metres; venue coordinates/radius are server data. Client coordinates still are not tamper-proof physical-presence evidence. Required details are nonempty firstName/mobile/emergency-contact name/mobile. Injuries can be an empty string. Forms must match current form ID/type/version and have a nonfuture signature timestamp. Reads and create happen in one transaction, so form-version/secret changes and concurrent scans cannot bypass validation.

Output: `{checkinId, eventId, status: 'pending', distanceM}`. Creates original scan, nullable confirmation fields, `corrections: []`, eventEndsAt and feedbackReminderPending=false. Walk-in flag is true when no active intent exists. RSVP is not changed by a scan.

Additional errors:

| Code | Reason | Details |
| --- | --- | --- |
| `failed-precondition` | `too-early` | `opensAt`; message e.g. “Check-in opens at 6:20 pm” in event timezone. |
| `failed-precondition` | `too-late` | `closedAt`. |
| `failed-precondition` | `too-far` | Rounded `distanceM`, `maxDistanceM`. |
| `permission-denied` | `invalid-secret` | Wrong, rotated, missing or expired QR credentials. |
| `already-exists` | `already-checked-in` | `checkinId`, existing status; no second scan overwrites the first. |
| `failed-precondition` | `unsigned-forms` | `missingForms` IDs. |
| `failed-precondition` | `missing-details` | `missingDetails` field names. |
| `failed-precondition` | `event-unavailable`, `invalid-event`, `form-unavailable` | Unpublished event, invalid/duplicate configuration, missing current form. |
| `invalid-argument` | `invalid-method` | Manual attendance must use the authorized walk-in path. |

### `coachDecision`

Input: `{eventId, uid, decision: 'confirm'|'reject'}`. Assigned coach or admin. Changes pending attendance to confirmed/rejected, recording confirmedBy/confirmedAt and updating feedbackReminderPending. No original scan fields change.

Output: `{checkinId, status: 'confirmed'|'rejected', unchanged: boolean}`. Retrying the same decision is idempotent; changing an existing decision requires a reasoned correction.

Additional errors: `invalid-argument / invalid-decision`; `failed-precondition / decision-already-made`.

### `correctAttendance`

Input: `{eventId, uid, status: 'pending'|'confirmed'|'rejected', reason}`. Assigned coach or admin; nonblank reason ≤1,000 characters. Does not invent a missing scan. Transaction appends `{at, by, reason, previousStatus, newStatus}` and updates only decision fields/feedback eligibility. Original scannedAt, method, lat/lng/distance and walkIn are retained, as is all prior correction history.

Output: `{checkinId, status, correctionCount}`.

Additional errors: `invalid-argument / invalid-status`; invalid/blank reason is `invalid-argument / invalid-input`; `resource-exhausted / correction-limit` at 100 prior entries.

### `addWalkIn`

Input: `{eventId, email, firstName?, lastName?, mobile?, emergencyContact?: {name,mobile}, injuries?}`. Assigned coach or admin. Validates event/window before account lookup and reauthorizes in the final transaction. Checks normalized-email mapping first. If missing, finds an existing Auth account or creates an unverified email-only account, then uses the same transactional identity reservation. Never sets verification or signs forms for that person.

Optional profile details fill empty fields only; a second coach cannot silently overwrite existing details. Creates coach-added RSVP if absent. With missing forms, returns an actionable waiting result and writes **no attendance**. Once signed, retry creates pending manual attendance; manual scan location/distance fields are **null**, never fabricated venue coordinates.

Output: `{uid, created: boolean, status: 'awaiting-forms'|'pending', missingForms: string[], checkinId: string|null}`. The eventual verified account uses the pre-created Auth UID. Email-link sign-in UI is a later stage.

Additional errors: `already-exists / already-checked-in` (`checkinId`, uid), event-window/form/identity errors as above. Auth account creation and Firestore are separate systems: an interrupted authorized request can leave an unverified Auth account; retry reuses it rather than creating another. No account is deleted as compensation.

### `mergeProfiles`

Input: `{sourceUid, targetUid, reason, dryRun?: boolean, dryRunId?: string}`. Admin only, distinct active participant profiles; privileged profiles are refused. `dryRun` defaults to true.

Dry-run output: `{dryRun:true, auditId, status:'dry-run', conflicts: string[], summary:{moves:[{from,to}], aliases:string[], writes:number}}`. Writes only a private audit plan; source profile and references are unchanged. Apply requires `dryRun:false` plus the plan ID, same admin/inputs/reason, age ≤15 minutes and a fingerprint of unchanged source/target records.

Apply output: `{dryRun:false, auditId, status:'applied', unchanged:false, summary}`. A repeated successful apply returns `{dryRun:false, auditId, status:'applied', unchanged:true}`.

Transaction sets source `mergedInto`, rewrites email aliases to the canonical target, moves source RSVPs/checkins/consents/feedback/recipient notifications to deterministic target IDs and removes the superseded source references. **Complete originals are retained in the private applied merge audit**, including original scans. Moved records carry `mergedFromUid`; target profile/credentials are preserved. Any overlapping target record blocks apply, rather than silently choosing which attendance/feedback/receipt to discard. Old devices stay on the blocked source account and are never transferred. Coach-alert copies of the old attendee UID remain historical; no second scan alert is sent just because a record was moved. No real data was merged in this stage; apply tests operate on disposable emulator fixtures.

Additional errors: `invalid-argument / same-profile`; `failed-precondition / privileged-profile`, `already-merged`, `dry-run-required`, `dry-run-expired`, `stale-dry-run`, `merge-conflicts` (conflict paths), `invalid-reference`; `resource-exhausted / merge-too-large` (400 writes, 200 source records per collection/aliases, 500KB audit snapshot guard). Exceeding bounds requires a separately reviewed offline migration, not partial application.

## Background functions and delivery

### `notifyCoachesOnCheckIn`

Firestore `onDocumentCreated` on `checkins/{checkinId}` with retries enabled. Reads current pending scan/event/active assigned coaches. Confirmed/rejected/missing/merged-copy scans are ignored. Transaction creates one notification per attendee/event/coach, ID `checkin-<attendeeUid>_<eventId>_<coachUid>`; retries see the same ID. Notification points to `/coach/events/<eventId>/checkins`. The real Firestore emulator trigger is integration-tested.

### `sendFeedbackReminders`

`onSchedule('every 5 minutes')`. Reads at most 100 confirmed records per run with feedbackReminderPending=true and eventEndsAt ≤ now minus 40 minutes, rechecks event end/current attendance/profile, and transactionally creates `notifications/feedback_<eventId>_<uid>`. Marks each processed eligibility flag false so old sent attendees cannot starve the next page. If event was extended, updates cached end and waits. Confirm/reasoned correction re-enables eligibility; existing notification ID still prevents another reminder. Event time editing must keep denormalized eventEndsAt in sync when shortening events; a future event-management endpoint must own that update.

Notification route is `/feedback/<eventId>`. Delivers/retries at most 100 outstanding notifications per run. Delivery uses transaction leases (60 seconds), up to five attempts; states pending → sending → sent, failed (retryable), dead (five failures), or suppressed (inactive recipient/rejected feedback attendance). Rechecks confirmed attendance before feedback delivery. Deterministic notification documents dedupe inbox entries; a future real external push transport will have at-least-once ambiguity if delivery succeeds just before a worker crash. It must not be advertised as exactly-once FCM delivery.

**Local push only:** sender writes `emulatorPushes/{notificationId}` with recipient/event/type/route/tokenCount/recordedAt. No real FCM messages or credentials are used. This private local collection has no client permissions. Actual FCM transport/token cleanup/permission UX will be completed during the notification stage, with APNs/web setup steps documented separately.

## Tests and local tooling

```sh
npm ci
npm --prefix functions ci
npm run test:functions
npm run test:all:emulator
```

Rules/Auth tests run with their own Auth/Firestore instances first. Functions integration tests then start Auth/Firestore/Functions and use real emulator ID tokens and HTTP callable endpoints. Controlled-clock tests use the same service logic with actual emulator Firestore transactions. Local fixtures are reset between tests; no production fallback or deployment command is provided.

The current Firebase CLI 15.36 adapter cannot deliver v2 `onSchedule` through Pub/Sub: it reports `Unsupported trigger signature: http`. The scheduler integration test calls the actual exported SDK handler's `.run(...)` with local emulator data, verifies its five-minute definition and runs it twice to verify dedupe. It does not claim wall-clock scheduler delivery was emulated. The ordinary Firestore trigger is tested through real emulator dispatch. No paid Scheduler service was enabled to work around this local tooling limitation.

Merge CLI (dry-run default, emulator-only):

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  node scripts/merge-profiles.mjs --source participant-3 --target participant-1 --reason 'Verified duplicate'
```

Uses the local seed admin/password. To apply a reviewed local plan, pass the same source/target/reason plus `--apply --dry-run-id <auditId>`. It refuses missing emulator environment. Do not adapt this tool to real data without explicit authorization and a reviewed backup/rollback plan.

References: [callable protocol and errors](https://firebase.google.com/docs/functions/callable), [local Functions emulator](https://firebase.google.com/docs/functions/local-emulator), [Firestore trigger delivery semantics](https://firebase.google.com/docs/functions/firestore-events?gen=1st). Triggers can be retried/out of order, so handlers re-read current state and reserve deterministic notification IDs.

## Rate limits

Limits are enforced server-side by transactional fixed-window counters in private `rateLimits` documents; retries and failed validation attempts count too. No participant can reset counters through Firestore rules.

| Entry point | Scope | Limit |
| --- | --- | --- |
| `checkIn` | Auth UID | 10 attempts per 60 seconds |
| `registerIdentity` | Auth UID | 20 attempts per hour |
| `beginNoAppCheckIn` | Remote IP | 10 attempts per 60 seconds |
| Returning-member sign-in link | Normalized email | 3 sends per hour |
| `completeNoAppCheckIn` | Remote IP | 5 attempts per 60 seconds |
| `getNoAppForms` | Remote IP | 20 reads per 60 seconds |

An exhausted bucket returns `resource-exhausted`, `details.reason = rate-limit`, plus `retryAfterSeconds`. These are application limits; Auth's own sign-in limits are separate. Counters use server time and reset on the first attempt after the window. Internal trusted attendance calls in the no-app service are covered by its public IP/email limits. This emulator-only build is not an internet anti-bot deployment.

## Known risks

- **Email-only no-app identification does not prove ownership.** A person could enter somebody else's address, particularly a new address or a profile with no attendance history. New-email/no-history requests create only a provisional pending walk-in; they never get an app login token or confirmed attendance. Returning profiles with any prior check-in require a one-time Firebase email sign-in link by default. The optional event policy `requireReturningEmailVerification` can be set to false only by trusted admin configuration; clients cannot switch it off. Public responses do not expose profile details, but the verification-required response can reveal that an email has history; IP/email limits reduce repeated probes.
- **Location is self-reported by the device.** Computing geofence distance server-side does not make GPS spoof-proof. Time-window, QR rotation and geofence checks reject invalid requests but cannot establish physical presence on their own.
- **Mandatory human confirmation is the mitigation for both risks.** Every app/camera/no-app scan starts pending. Only an assigned coach with an admin-issued claim, or an admin, can confirm it. Coach review data shows the original scan time, server-computed distance and `identityVerification` (`account`, `email-link`, or `email-only`). Email-only arrivals are clearly flagged. The coach must confirm the person at the court; a scan is never automatically treated as attendance. Corrections preserve the original scan and record a reason.

## No-app verification callables

- `getNoAppForms({eventCode,secret,lat,lng})` is public but rate-limited. Validates the live event QR/window/distance and returns `{eventId,name,forms}` containing current form content/version, with no personal data.
- `beginNoAppCheckIn({email,eventCode,secret,lat,lng,firstName,mobile,emergencyContact,injuries?,signedVersions})` is public but rate-limited. `signedVersions` maps current required form IDs to versions explicitly accepted by the visitor. A returning profile with history receives `{status:'verification-required',requestId}` without an attendance write. Otherwise it returns `{status:'pending',checkinId,eventId,verification:'email-only'}`. Existing profile details are only filled if empty; current signed receipts are preserved.
- `completeNoAppCheckIn({requestId,oobCode,secret})` exchanges the one-time emailed code with **the local Auth emulator**, verifies its email/UID, consumes the private request and reruns server check-in validation. Returns the same pending result with `verification:'email-link'`. No ID/refresh token is returned. Replays/expiry use `failed-precondition / verification-expired`; invalid/used/wrong-email codes use `permission-denied / verification-invalid`; a request bound to another QR uses `permission-denied / invalid-secret`. New links are needed if the QR expired before verification.

`noAppRequests/{requestId}` is server-only: email, non-secret request data, secretHash, createdAt, expiresAt, consumed and verifiedAt. Requests expire after 15 minutes; QR secrets still expire after five minutes. Emulator email links are printed to the terminal/OOB endpoint; **no real emails are sent**. The local screen supports pasting the link into the original check-in tab. Public Hosting/domain links remain a later deployment stage.

`getCountedIn({eventId})` requires an active verified account and returns `{count,people:[{label,initials,isYou}]}`. Only opted-in first names and the viewer are shown; no email, UID, phone or emergency details are exposed. It is a read projection, not a participant permission to read other RSVP/profile documents.

## Google Workspace and coach administration

Google is an authentication provider, not a role source. Neither a verified `@rally4ever.org` address, Google's domain hint, nor an owner-editable UI choice grants coach access. A coach needs an admin-issued `role:'coach'` or `roles:['participant','coach']` Auth claim **and** an active protected profile gate. A protected participant role or `coachEnabled:false` denies even a cached old coach claim. Participants always retain their own member tools and the same UID/profile when coach access changes. Existing pre-created accounts and Google sign-in are reconciled by Auth's email identity and `registerIdentity`; emulator tests verify no duplicate profile for the same email.

New trusted callables (all authenticated, verified, emulator-only):

| Callable | Input | Output / authorization |
| --- | --- | --- |
| `listUsers` | `{query?: emailPrefix,cursor?: emailLower}` | Admin only. Up to 50 `{uid,email,firstName,role,coachEnabled,mergedInto}` records, cursor and up to 100 event summaries for assignment. |
| `setUserRole` | `{uid,role:'coach',enabled:boolean,reason}` | Admin only. `{uid,roles,coachEnabled,auditId,refreshRequired:true}`. Retains participant access and preserves an existing admin role. |
| `assignEventCoaches` | `{eventId,coachUids:string[],reason}` | Admin only. Validates up to ten distinct verified, claim-authorized, active coaches; returns eventId/coachUids/auditId. |
| `coachOverview` | `{}` | Claim-authorized coach/admin only. Assigned event summaries and pending arrivals with firstName, scan time, distance and verification status. |

Role updates fail closed across Auth and Firestore: protected coach access is disabled first, then claims change, then the protected mirror is enabled only after success. A per-UID operation lock serializes concurrent changes. Revocation blocks reads/callables immediately, without signing the person out of participant tools. Grants require a token refresh; the app provides “Refresh access”. Old event assignments do not override a revoked role, and the admin can remove them. `roleAudits` records actor/target or event, reason, action/status and timestamps; `roleChanges` holds private operation locks. Clients cannot write either collection. Failed cross-system updates leave the gate disabled and are retryable by the admin.

Additional errors: `permission-denied / admin-required` or `coach-claim-required`; `invalid-argument / invalid-role` or `invalid-coaches`; `failed-precondition / email-unverified` or `coach-claim-required`; `aborted / role-change-in-progress` for an in-flight update. No production Auth providers, account credentials or paid services were changed.

## Staff administration increment — 19 November 2026

See [ADMIN_TOOLS.md](ADMIN_TOOLS.md) for the new `listStaffSessions`, `getEventConsole`, `cancelSession` contracts and expanded `setUserRole` inputs. `saveSession` accepts per-session `venue`, `timezone` and `coachUids`; creation requires a published `programId`, while editing an existing legacy event may omit programId and keeps the same ID. Details cannot change after a scan or session start. Cancellation is a separate admin-only, reasoned operation that retains all RSVP/check-in records, including original scan fields. No schema migration is required. Staff list/console requests are read-only; the console separately calls the existing rotateEventSecret to generate the five-minute QR.

## Hosted administration callables (20 November 2026)

The following are deployed only to `rally4ever-3adaf`, region `australia-southeast1`, existing codebase `attendance`. Each requires verified Firebase Auth, an admin custom claim and an active protected admin profile. Public HTTP transport permits browser preflight/Firebase tokens; handler authorization is mandatory. Full UI, deployment and proof: [WEB_ADMIN.md](WEB_ADMIN.md).

| Callable | Input | Result | Main error reasons |
|---|---|---|---|
| `adminCatalogue` | `{}` | ISO-serialized `events`, `programs`, derived/stored `venues`, current form IDs/versions | `admin-claim-required`, `admin-required`, `catalogue-limit` |
| `adminSaveSession` | optional `eventId`, current `revision`, whitelisted `changes` | `{eventId}` | `stale-session`, `duplicate-code`, `invalid-coach`, `invalid-forms`, `incomplete-session`, `attendance-started`, `capacity-below-reservations`, `invalid-time`, `invalid-timezone` |
| `adminSaveVenue` | optional `venueId`, current `revision`, `venue` | `{venueId, updatedRecords}` | `stale-venue`, `duplicate-venue-code`, `invalid-photo`, `venue-photo-path`, `venue-too-large` |
| `adminRemoveDemo` | preview `{}`; apply `{apply:true, expectedPaths:[...]}` from exact preview | preview count/per-collection counts/paths; apply removed count/paths | `demo-changed`, `demo-in-use`, `demo-too-large` |

Permission failures are HTTP 403 `PERMISSION_DENIED`; missing sign-in is HTTP 401 `UNAUTHENTICATED`; validation is HTTP 400 `INVALID_ARGUMENT`; stale revisions/previews are HTTP 409 `ABORTED`; publication/original-context/reference constraints are `FAILED_PRECONDITION`. All writes use trusted server timestamps, increment revisions, and retain audit snapshots. Venue image finalization validates the owned path/type/size and removes download tokens before storing the reference. `saveProgram`, `listUsers`, `setUserRole`, `getEventConsole`, `coachDecision` and `assignEventCoaches` are reused by the web client; current protected admin claim checks also apply to their admin operations.
