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
