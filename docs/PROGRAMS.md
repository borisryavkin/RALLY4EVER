# Programs, calendar sessions and availability

This implementation is local/emulator-tested. It has not deployed rules, Functions, indexes or directory data to `rally4ever-3adaf`, and it has not uploaded another tester build. The previously uploaded build 5 cannot show these new screens until a subsequent reviewed build is distributed.

## Model

A **program** is a regular community activity and its venue/schedule. A **session** is one dated occurrence in the existing `events` collection. RSVPs and check-ins remain separate and keep their existing deterministic event/UID document IDs. No members, attendance records, features or source directory files are deleted.

| Collection | Fields |
|---|---|
| `programs/{programId}` | `name`, `sport` (`tennis`/`pickleball`), `status` (`draft`/`active`/`archived`), `venue` (`name`, `address`, `suburb`, `postcode`, `state`, nullable paired `lat`/`lng`), IANA `timezone`, `scheduleText`, `coachUids`, public `coachNames`, `notes`, HTTPS `photoUrl`, default nullable `capacity`, default `registrationStatus` (`open`/`full`/`closed`), `revision`, `createdAt`, `updatedAt`, `updatedBy`. Imports additionally retain `needsVerification`, `sourceEntries`, `sourceConflicts`; active admin saves record `reviewedBy`/`reviewedAt`. |
| `events/{eventId}` | Existing session fields plus `programId`, `catalogueManaged`, `sport`, `notes`, `photoUrl`, `coachNames`, nullable `capacity`, `registrationStatus`, `bookedCount`, `revision`, timestamps. Existing QR code, geofence, required forms, coaches and scan records remain linked to the same event. |
| `rsvps/{eventId}_{uid}` | Existing intent fields: `eventId`, `uid`, `createdAt`, `cancelledAt`, `source`. A cancellation retains the original document. |
| `catalogueAudits/{id}` | `kind`, program/session IDs, `actorUid`, required `reason`, before/after values and timestamp. Import audits identify the emulator importer. |

Capacity is **per dated session**, not a live headcount. “Count me in” reserves intent; it does not create check-in or confirmation. Program cards direct people to actual session availability; a program’s default capacity is not presented as a real remaining count. Unlimited capacity is `null`, not zero. Full/closed flags override remaining numbers. Started session details cannot be rewritten by the new editor, preserving attendance context.

Archiving hides a program from active discovery and closes new reservations, but preserves its history and existing reservations. It does not silently cancel all previously scheduled sessions or attendance. An admin can explicitly cancel/edit a future dated session that has no check-ins; cancellation is visible and further reservations are refused. Existing participants can cancel their own reservation. Program defaults are copied into each session; later edits do not silently rewrite historical sessions. Reopen or edit future sessions explicitly as needed.

## Trusted APIs

All four callables reuse verified Auth and protected admin/participant checks. Domain and role/email shortcuts do not grant privileges.

- `listPrograms({})` — admin-only draft/active/archive list, up to 500 programs; returns `{programs}`.
- `saveProgram({programId?, program, revision?, reason})` — admin-only validated create/edit/archive, returns `{programId}`. Editing requires the current revision. Coaches are selected from existing accounts; names do not create accounts or assign privilege.
- `saveSession({programId, eventId?, startsAt, endsAt, status?, revision?, capacity?, registrationStatus?, notes?, photoUrl?, reason})` — admin-only dated occurrence, returns `{eventId}`. ISO timestamps must include an offset or `Z`; the UI date/time picker converts the program’s timezone to UTC. A verified venue coordinate pair and currently active assigned coaches are required. Session capacity can override the default but cannot be reduced below reservations. Start must be future, end later and no more than 24 hours after start.
- `setRsvp({eventId, cancel?})` — authenticated participant intent, returns `{eventId, countedIn, bookedCount, spotsAvailable}`. Rate limit: 30/user/minute. Event and current RSVP query are read in one transaction; the shared event update serializes concurrent last-place requests. Duplicate requests are idempotent and retain the original creation/source fields. This also supports legacy events.
- `syncSessionAvailability` — retryable Firestore RSVP-write trigger. Recomputes the event count from uncancelled intent and only writes when it differs. Handles coach-added RSVPs, merges and cancellation. Existing manual coach walk-in behavior is retained; it may exceed reservation capacity and is not proof of participant confirmation.

Errors include `admin-required`, `invalid-catalogue`, `invalid-capacity`, `invalid-photo`, `invalid-location`, `invalid-timezone`, `invalid-time`, `invalid-coach`, `missing-location`, `missing-coach`, `stale-program`, `stale-session`, `past-session`, `session-started`, `capacity-below-reservations`, `registration-closed`, `session-full`, and `rate-limit`. Callables return standard Firebase error codes with a machine-readable `details.reason`.

Rules allow verified active members to read active/archived programs and published/cancelled events; only admin can read drafts/audits. Program/audit client writes are denied, including admin client writes, so validation/audits stay on the server. Managed-session participant RSVP writes must use the callable. Legacy-session direct RSVP rules are retained for the existing build 5; this keeps its existing sessions functional during rollout. Check-ins remain callable-only.

## User and admin flows

- Home shows nearby programs (within 50 km of the selected area) and upcoming sessions, with separate intent/attendance states. Explore programs supports all Australian states/territories, postcode/name search, sport and archive filtering.
- Map shows active programs with verified coordinates and legacy session markers, without duplicate markers for linked sessions. A program without coordinates remains searchable in the list and explicitly says its map location awaits verification. No coordinates are invented.
- Program detail includes photo/placeholder, venue, regular schedule/timezone, coaches, notes and a dated session calendar. Session detail shows actual remaining/full/closed/cancelled state and disables reservations when unavailable. Server enforcement remains authoritative.
- Admin view → Manage programs & calendar lists all statuses. Create/edit program, select existing coaches by email, enter an HTTPS photo URL, set default capacity/status, and supply a reason. Imported drafts show review/conflict warnings. Add/edit/cancel future calendar sessions and override session notes/capacity/booking status; all changes are audited.
- The original bundled directory remains available through **Browse saved directory**, with an explicit saved-data notice. It does not fabricate dated sessions, availability or check-ins.

Photos use existing HTTPS URLs with an error placeholder. No new Firebase Storage bucket, paid geocoding provider, upload service or image generation was enabled.

Who’s coming continues to use the existing per-session counted-in list. Public roster entries remain limited by the existing privacy rules; attendance still requires coach confirmation.

The map uses a returning member’s saved postcode when it matches a program, and nearby discovery includes programs within 50 km of the selected area.

## Directory import and emulator fixtures

The two existing assets contain 83 source rows (47 national + 36 NSW), combining to **61 program drafts**, **36 with coordinates**, and **2 venue conflicts**. The bundled files cover NSW/VIC/QLD/SA; no real listings are invented for other states. The model/filter supports all eight states/territories. Source data may be stale: drafts require an admin to review real venue, schedule, capacity and coach assignments before publication. School-term/weather text does not create guessed dated occurrences.

Preview is the default and makes **no Firebase requests**:

```sh
npm run programs:preview
node scripts/import-programs.mjs --report=/tmp/program-preview.json
```

Optional create-only import into disposable default local emulators:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
node scripts/import-programs.mjs --apply-emulator
```

The importer refuses absent/nonlocal emulator endpoints, other project IDs and service-account credentials. It never overwrites existing program edits, never creates member/coach accounts and has no real-project apply option. The source files are retained; normalized program IDs combine state/sport/name. Conflicting source venues are reported for review.

The standard `npm run seed` adds two explicitly synthetic active demo programs using existing coach UIDs and retains the original 13 accounts / 3 events. Publish sample calendar sessions via admin or the catalogue emulator tests. No seed was run against the real project in this task.

## Validation and release steps

```sh
flutter analyze
flutter test
npm run test:functions
npm run test:lan
npm run test:catalogue
```

`test:catalogue` builds TypeScript, tests the pure importer, then launches **isolated** Auth/Firestore on 23999/23880 with hub/logging on 24400/24401 and UI disabled. It leaves the running development instance on 9099/8080 untouched. It runs the new catalogue service/rules tests plus the existing Firestore rules regression suite through a temporary port-adjusted copy; only those isolated test databases are cleared. Guard/config files are removed on normal exit. No real-project credentials or Auth login are used.

Before this appears on phones: review and integrate the concurrent backend/runtime edits already present in the workspace; approve a staging deployment of the four new callables, trigger, rules and indexes; review/import/publish real program data; then build/upload **build 6 or higher**, rechecking both stores first. Keep new catalogued sessions unpublished until testers have the updated client; build 5 does not understand the new reservation API. A real-project importer must be separately reviewed with a dry run before any writes. Do not run the separate staging seed script just to populate this catalogue.

No deployment, real-data import, billing change, budget-alert creation or new store upload is performed by these commands. The existing AUD $100 total / AUD $20 alert requirements remain. Cost depends on reservations and attendee counts: transactions and reconciliation currently read active RSVP documents, so evaluate larger events before increasing the 5000 capacity validation ceiling. Development on emulators remains the free alternative.
