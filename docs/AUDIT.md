# Rally4Ever audit and proposed implementation plan

Audit date: 17 November 2026. Scope: this app directory, supplied target brief, and two supplied design screenshots. No production services or data were accessed. No application code was changed. Implementation is pending approval.

## 1. Repository and evidence boundary

This directory is a Flutter prototype, not an independently tracked Git repository. `git rev-parse --show-toplevel` resolves to `/Users/borisryavkin/technical/flutter`, the parent Flutter SDK checkout, on branch `stable`. `git ls-files -- .` returns no tracked app files. The parent has extensive unrelated modifications. Do not create the requested feature branch or commit this app in that SDK repository. Resolve whether to initialize an app-local repository or use the intended existing repository, then create `feature/qr-attendance` and make narrowly scoped commits. No Git state was changed during this audit.

No applicable `AGENTS.md` was found in the app/containing Rally4Ever folder or checked ancestor locations. No `docs/design` exists. The screenshots provide visual guidance but do not include the full S01–S34 canvas or readable data-model/admin details. The old iOS Admin app is not present in this app directory; its behavior and backend cannot be inferred as audited facts.

## 2. App structure, screens, navigation and state

Almost all implementation is in `lib/main.dart` (2,716 lines). `lib/session_feedback_notifications.dart` (97 lines) contains local reminders. There is one test in `test/widget_test.dart`.

Navigation is a `String route` switch inside `MaterialApp.home`, with `AnimatedSwitcher`, callbacks and `setState` (`main.dart:150–329`). There is a navigator key for the initial location dialog, but no named route table, URL router, authentication gate, deep-link parsing, or browser `/admin` route. Home maintains an integer tab. Data is held in mutable `MemberData` and widget-local state; there is no repository layer, state-management package, database or durable local profile store.

| Screen/route | Implementation and current behavior |
| --- | --- |
| `welcome` | `Welcome`, three intro pages and initial location permission dialog. |
| `account` | `Account`, email entry; Google/Apple buttons bypass to onboarding with empty email. No authentication or email validation. “Sign in” is text. |
| `aboutYou` | Five pages: basics, research/demographics, access/current activity/referral, wellbeing, consent preferences. Mutates in-memory member. Skip bypasses even basics; progress text says “of 4” despite five pages. |
| `home`, Play tab | Program discovery, Tennis/Pickleball filters, manually selected search area, distance sorting within 80 km. JSON asset-backed. |
| `locationPicker` | Search/select area and free-text selection. Unknown areas fall back to Sydney in Play. |
| Home Map tab | `flutter_map`/OpenStreetMap with program markers and previews. All session navigation shares the same callback. |
| `session` | Fixed Weeknight Rally, Waverley Park, Coach Dan, Wednesday 1 Oct, 6:30–8pm; does not receive the selected program or event ID. |
| `checkin` | Static “I'm here” screen; both tap and “scan” text advance to waiver without validation. |
| `qrCheckin` | Real camera scanner, but accepts any non-null barcode string and advances to waiver; no event/secret checks. |
| `waiver` | Static waiver, ephemeral checkbox, always shown on that route. |
| `post` | Immediate post-waiver wellbeing questions/comment; Send only navigates home. |
| Home Me tab | Profile name/postcode from memory, fixed attendance statistics/member date, edit opens onboarding. Other settings are placeholders. |
| Home Help tab | Support call links, static topic cards, inactive team-message button. |
| `coachToday` | Available solely by entering `coach@rally4ever.org`. Fixed event, decorative QR-like grid and sample counts. |
| `roster` | Four fixed sample people/statuses. End session button has no handler. |

Reusable UI includes `Logo`, `Button`, `CardBox`, `Avatar`, `Tag`, `SessionCard`, `Info`, `Question`, `ChoiceChips`, `SetRow`, `Support`, `Mini` and onboarding/court artwork. Preserve program discovery, map, location selection, onboarding, help links and existing assets while replacing prototype data/navigation behavior. Tell the user before retiring an existing feature.

### Packages and design

`pubspec.yaml`: app `1.0.1+2`, Dart constraint `^3.13.4`.

| Runtime dependency | Version constraint | Use |
| --- | --- | --- |
| Flutter SDK | SDK | Material UI and state |
| cupertino_icons | ^1.0.8 | Icons |
| geolocator | ^14.0.2 | Location permissions/current position |
| flutter_map | ^8.2.2 | Map UI, remote OSM tiles |
| latlong2 | ^0.9.1 | Coordinates |
| flutter_local_notifications | ^19.5.0 | On-device reminder |
| mobile_scanner | ^7.1.3 | Camera barcode scanning |
| timezone | ^0.10.1 | Reminder scheduling |
| url_launcher | ^6.3.2 | Support call links |

Development dependencies: `flutter_test` SDK, `flutter_launcher_icons ^0.14.3`, `flutter_lints ^6.0.0`. No Firebase, Functions, messaging, auth, QR-generation, CSV or URL-routing packages.

Theme is close to the design: navy is already `#001751`; coral is `#ff4b4d` rather than `#ff4b4c`; background is `#f5f1ee` rather than cream `#f2eeeb`. Several secondary colors are hardcoded. Inter/Figtree are not configured or bundled. Consolidate target tokens and fonts while reusing widgets; use supplied screenshots for waiting/confirmed, coach and feedback states.

## 3. Firebase and platform audit

| Area | Evidence in this directory |
| --- | --- |
| Auth | Absent: no Firebase initialization, SDK or providers. Entering an email confers the prototype coach UI. No actual account exists through this flow. |
| Firestore collections/fields | None in code/config. `MemberData` is not a Firestore document. No users/profiles, events, RSVP, check-in, consent, feedback or notification collection is implemented. Deployed schema/rules are unknown. |
| Storage | No Firebase Storage usage/config/rules. Images and programs are local assets; map tiles are remote OSM. |
| Functions | No Functions source, TypeScript project, callable, trigger or scheduler. |
| Rules/indexes | No `firestore.rules`, rules tests, Storage rules or composite indexes file. Deployed security cannot be assessed. |
| FCM | No messaging SDK, token registration, background handler, web worker or push-open handling. Local notifications are not FCM. |
| Hosting/emulators | No `firebase.json`, `.firebaserc`, Hosting check-in page, emulator connection/config, fixtures or seed script. CLI commands are present locally, but emulator readiness was not established. |
| Native Firebase config | No Firebase references found in inspected platform sources; no Android Google Services plugin configuration. |

`MemberData` fields: firstName, postcode, email, ageRange, gender, accessNeed, currentActivity, referral, referralOther, loneliness, satisfaction, culturalBackground, useInReports, wellbeingCheckIns, showInWhosGoing, marketingEmails. There is no uid, normalized-email identity, role, mobile, emergency contact, injury detail, form version or merge marker. Several demographic answers default to concrete values without user input.

`RallyProgram` fields: name, sport, venue, suburb, postcode, schedule, time, latitude, longitude. The loader merges active records from two JSON assets by `sport|name`, with fallback suburb coordinates. There are no event-instance IDs, start/end timestamps, timezone, coach UID assignments or event secrets. Approximate discovery coordinates must not silently become authoritative geofence centers.

Platform scaffolding exists for Android, iOS, web, macOS, Linux and Windows. The app is not intrinsically iOS-only, but browser readiness is unverified. Notifications directly import `dart:io` and access `Platform.isAndroid/isIOS`; this needs a web-safe platform abstraction before browser execution. Android has location, camera and local-notification permissions/receivers. iOS has location descriptions but no camera usage description in the inspected `Info.plist`; QR camera permission needs correction. No APNs entitlement or associated-domain setup was found. Android has no HTTPS app-link intent filter. Web is standard Flutter scaffolding. The old Admin app is outside this audit.

Two program assets are absolute symlinks into `/Users/borisryavkin/technical/flutter/rally4ever copy/rally4ever/assets/`. They work on this machine but make clean checkouts nonportable. Plan to bring reviewed source data into this app, without deleting the originals. Build artifacts/credentials must not be included in an initial source commit.

## 4. Current flows and reported bugs

### Intent, attendance and feedback

“Count me in” (`main.dart:1939`) schedules a local reminder, then navigates to `checkin`; it writes no intent record. “I'm here” advances to waiver. QR detection (`main.dart:2054`) accepts any barcode raw value, briefly shows “You're checked in”, then advances. There is no server validation, geofence, window, deduplication, attendance record, pending state or coach confirmation. Waiver acceptance immediately opens feedback; feedback values are not persisted.

The local reminder targets the next Wednesday 8pm end plus **30 minutes**, uses fixed notification ID `1001` and payload `session-feedback`. It is scheduled on intent rather than confirmed attendance. There is no notification response callback to open an event form, no server dedupe, and no actual event timezone model.

### Profiles/coaches/forms

Email is trimmed but kept as entered in member state; lowercasing is used only for the hardcoded coach comparison. No identity lookup or registration persists across restarts. Coaches cannot add participants or search profiles in this code. Roster and coach counts are static. Waiver agreement is widget-local, without conduct form, signature timestamp or version; onboarding consent toggles represent preferences, not signed forms.

| Report | What can be confirmed | Required fix/verification |
| --- | --- | --- |
| (a) Coach-registered participant cannot see event | This app cannot display persisted coach-added events: no event assignments, UID/email lookup, RSVP store or participant membership query exists. All cards route to the same event. The specific old-admin registration defect cannot be reproduced from this directory. | Add canonical UID resolution, transactional coach-added RSVP creation and participant UID-based queries. Test mixed-case email, existing account, pre-account registration and later verified sign-in; inspect old-admin schema/export before any migration. |
| (b) Duplicate profiles across coaches | No persistent profile creation path exists here, so the reported cross-coach duplication is unconfirmed. There is no uniqueness/merge protection to reuse. | Server-owned normalized email identity mapping and race-safe lookup before creation; independent coach concurrency tests; admin merge with `mergedInto`, audit history and reference reconciliation. Obtain old-admin source/schema or a sanitized export to assess legacy duplicates. |

## 5. Target gap table

Paths below are proposed where absent; existing UI should be extracted gradually from `main.dart`.

| Target feature | Status | Files to change/add |
| --- | --- | --- |
| One authenticated login; participant/coach/admin role enforcement | Missing | `pubspec.yaml`, `lib/main.dart`, `lib/auth/`, `lib/data/`, `firestore.rules`, rules tests |
| Canonical lowercased email → UID; coach linking; merge path | Missing | `functions/src/identity.ts`, `functions/src/admin.ts`, `scripts/merge-users.ts`, `lib/admin/`, `lib/data/` |
| Event instances with times, venues, assigned coaches | Partial: discovery programs only | `lib/main.dart`, `lib/models/`, `lib/data/`, `scripts/seed.ts`, program assets |
| Separate deterministic-ID RSVPs and attendance | Missing | `lib/models/`, `lib/data/`, `functions/src/check-in.ts`, `firestore.rules`, `firestore.indexes.json` |
| Counted in → checked in → confirmed UI; who's coming privacy | Partial: static session UI | `lib/participant/`, `lib/main.dart`, participant widget/integration tests |
| Event QR, HTTPS link and rotating secret | Partial: scanner only, decorative coach QR | `lib/coach/`, `lib/participant/`, `functions/src/qr.ts`, native app-link configuration, `web/` |
| Callable checkIn; server time/distance/secret/forms/dedupe | Missing | `functions/src/check-in.ts`, unit/emulator tests, `lib/data/` |
| Once-only prefilled attendance details | Partial: basic in-memory profile | `lib/models/`, `lib/participant/`, profile validation/rules |
| Coach My events, live console and roster filters | Partial: static single event/roster | `lib/coach/`, event queries/indexes, `lib/main.dart` |
| Confirm/reject/all on time; reasoned corrections | Missing | `functions/src/attendance.ts`, `lib/coach/`, rules, tests |
| Walk-in search/create; in-app alerts | Missing | `functions/src/identity.ts`, `functions/src/attendance.ts`, `lib/coach/` |
| Camera/no-app lightweight web check-in | Missing | `hosting/`, `firebase.json`, `functions/src/`, Hosting/auth emulator tests |
| Coach FCM, in-app notification inbox, push navigation | Missing | `functions/src/notifications.ts`, `lib/notifications/`, platform/web messaging config |
| Versioned conduct/waiver signatures and re-prompt | Partial: unpersisted waiver | `lib/forms/`, `functions/src/forms.ts`, `firestore.rules`, admin UI |
| Five-minute feedback job; +40 min; confirmed only; dedupe | Partial: different local reminder | `functions/src/feedback.ts`, `lib/session_feedback_notifications.dart`, job tests |
| Event feedback rating/tags/comment | Partial: unsaved wellbeing questions | `lib/feedback/`, feedback schema/rules/tests |
| Browser admin: aggregates, counts, CSV, merge, form versions | Missing | `lib/admin/`, router/auth gate, `functions/src/admin.ts`, browser tests |
| Rules tests, indexes, emulator config and demo seed | Missing | `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `functions/`, `tests/rules/`, `scripts/seed.ts` |
| Design tokens/fonts and responsive layouts | Partial | `lib/theme/`, existing widgets, `pubspec.yaml`, font assets |
| Running changelog and manual setup guide | Missing | `docs/CHANGELOG.md`, `docs/SETUP.md` |

## 6. Proposed data/security decisions

- Use `users/{uid}` as canonical profiles, with protected role and `mergedInto` fields. A private server-owned email mapping resolves trimmed/lowercased verified addresses to canonical UIDs. Roles cannot be self-assigned. Handle coach pre-registration as a pending identity/invitation bound by trusted code; email entry alone cannot prove ownership.
- Add dated `events/{eventId}` with startsAt, endsAt, timezone, venue coordinates, default geofence radius 150m, coachUids and public event code. Keep rotating secrets in server-only documents; event-readable documents must not disclose them. Coach QR issuance requires event assignment.
- Keep `rsvps/{eventId}_{uid}` (intent, createdAt, cancelledAt, source) separate from `checkins/{eventId}_{uid}` (scannedAt, method, coordinates/distance, pending/confirmed/rejected, confirmedBy, walkIn, corrections). Include eventId/uid query fields. Server transactions preserve the original scan and enforce one canonical attendance record.
- A function checks the event window (start minus ten minutes through end), QR secret, distance, identity, required details and current consents. Mobile location is submitted by the client; server-side distance checks do not establish tamper-proof physical presence. Confirmation/rejection/correction use assigned-coach authorization; preserve an audit trail with required correction reason and timestamps.
- Participants can access their own allowed profile fields, RSVPs and feedback; restrict sensitive roster/profile data to authorized use. Direct client writes to check-ins are denied. Coach attendance mutations should use authorized server endpoints so validation and audit records cannot be bypassed. Admin management remains audited; function-only check-in writes apply even to admin clients, with admin operations through trusted server code.
- Use `consents/{uid}_{formId}`, current version definitions, `feedback/{eventId}_{uid}`, and deterministic `notifications/{type_eventId_uid}`. Keep per-device push tokens private. Feedback eligibility uses confirmed attendance and an event-linked notification route. Design notification retries so transient send failures do not permanently suppress delivery; mock FCM in local tests because delivery itself is not emulated.
- No-app flow must verify email ownership before revealing an existing profile or submitting attendance as that UID (for example email-link auth). Do not expose a public email-to-profile lookup or trust a caller-supplied UID. Anonymous email entry alone would enable impersonation. Reuse the same authenticated checkIn callable after verification, retaining QR context across sign-in.
- Merge tooling defaults to dry-run and reports affected references, collisions, consent/feedback handling and proposed canonical identity. Do not migrate/delete production data or alter production auth providers without explicit approval.

## 7. Baseline validation

Executed locally with existing dependency resolution, without connecting Firebase:

- `flutter analyze --no-pub`: exits 1 with nine informational findings: missing braces at main.dart lines 189, 192, 1616, 1642, 2710; deprecated Radio properties at 829 and 831; unnecessary underscores at 1467; missing widget key at 2379. No analyzer errors reported.
- `flutter test --no-pub`: passes, one welcome-screen test. No auth, event, QR, state transition, rule or backend tests exist.
- Emulator tests: not runnable yet; no Firebase config, test suite or backend exists. No claim of production correctness or browser compatibility is made. Firebase CLI, Node and a Java command are on PATH; versions/runtime compatibility need checking during setup.

Additional confirmed source issues: arbitrary barcode acceptance, no authentication despite sign-in UI, missing iOS camera description, fixed session navigation, nonportable assets, no feedback persistence and mismatched reminder eligibility/timing. Browser notification platform access is a source-level compatibility risk that needs a web run to verify.

## 8. Numbered implementation/commit plan — approval required before starting

0. Resolve app Git ownership; create `feature/qr-attendance` in the intended app repository. Commit the audit independently. Record starting state, exclude generated files/credentials, and make program assets portable. Add the changelog/setup log and an emulator-only configuration using a demo project ID with no production fallback.
1. **Data model and rules:** canonical identities, event instances, RSVP/check-in separation, private secrets, notification/consent/feedback schemas, typed repositories, role/ownership rules and composite indexes. Add emulator rule tests and a repeatable seed (1 admin, 2 coaches, 10 participants, 3 events). Commit schema/rules and fixtures separately where practical.
2. **Cloud Functions:** TypeScript project; identity linking, QR rotation/issuance, transactional checkIn validation, assigned-coach confirm/reject/correct and walk-in operations. Unit/emulator tests cover authorization, races, window boundaries, distance, expired secrets, forms and duplicate scans. Add dry-run merge tooling and callable contracts before UI work.
3. **Participant flow:** authenticated shared login and role routing, persistent profile, event-aware discovery/detail, RSVP/cancellation, scanner/deep links, once-only attendance details, waiting/confirmed/rejected states and private who's-coming projection. Retain discovery/map/help/onboarding features. Add flow tests including coach-added RSVP visibility.
4. **Coach console:** My events, event-specific real QR, live counts, confirmations, confirm-all-on-time, roster filters, corrections with reason and profile-first walk-in search. Verify two coaches resolve the same normalized-email identity and cannot operate on each other's events.
5. **No-app web check-in:** lightweight Hosting page on `/c/<eventCode>`, retained rotating-secret context, verified identity, existing-profile prefill, same callable validation and download links. Configure/test Hosting rewrites and app-link association files locally.
6. **Notifications:** coach inbox and FCM hooks/token lifecycle; scheduled feedback selection every five minutes at end plus 40 minutes, confirmed attendees only, deterministic dedupe/retry and event-specific navigation. Replace the old intent-triggered local reminder behavior explicitly in the changelog; retain useful notification UX. Test scheduled selection with a controlled clock and mocked sends.
7. **Forms:** finish conduct/waiver UI, current-version-only prompts, signature records and profile form status; server enforcement already exists from stage 2. Test version bumps and re-prompt once per version. Complete event feedback rating 1–5, tags/comment and eligibility tests.
8. **Admin web:** responsive role-gated `/admin`, event/coach aggregates, separate intent/attendance counts, CSV export, reviewed dry-run merge tool and form-version controls. Test participant/coach denial and browser operation, including web-safe notification initialization.
9. **Final verification and handoff:** run full local checks, document retained/replaced prototype behavior, remaining manual steps and emulator commands. No deploy, paid service activation or real-data migration is implied by implementation approval.

After each implementation stage: run `flutter analyze`, `flutter test`, applicable Functions unit tests and emulator suites; fix failures before proceeding. Baseline lint findings should be cleaned up early. Use a demo project and emulator host settings consistently across clients, functions and seed scripts; fail closed when emulator configuration is absent in development. Keep commits small by separating backend contracts, UI features and validation changes.

## 9. Cost guard and manual steps

No paid services were enabled, no budget was changed, and no production deployment was attempted. Development remains local/emulated. Before any billed action, present its purpose, current estimated AUD cost and free alternative and obtain approval. Respect AUD $100 total budget. An AUD $20 billing budget alert is a deployment prerequisite; it has **not** been created and must not be described as a spending cap.

Track these in `docs/SETUP.md` during implementation:

1. Firebase project/app registrations and approved authentication providers; legacy Admin app source/schema or sanitized export for compatibility review. Do not change deployed providers without approval.
2. Before deploying Functions/scheduled jobs, verify current Blaze/billing requirements and costs, obtain approval, then arrange the AUD $20 alert with authorized billing access. Local callable/job tests are the free development alternative. Keep minimal instances and bounded scheduled queries in the deployment proposal.
3. APNs key/capabilities, iOS camera permission, Android notification setup, FCM web push configuration/service worker and token lifecycle. Physical device push testing is manual; no real FCM delivery in emulators.
4. Authorized control of `rally4ever.org`, Hosting DNS/HTTPS and Apple/Android link associations. Use local Hosting/emulator URLs during development; domain purchases or paid changes require approval.
5. Approved published conduct/waiver content and versions, verified venue coordinates and event timezone/schedules, actual coach account assignments and store download URLs.
6. Store signing/release access and any developer-account fees need a separate cost approval before expenditure. Browser admin should work without an iOS release.
7. Review a dry-run migration/merge report and backup/rollback strategy before authorizing any real-data mutation. Emulator fixtures can exercise the path first.

**Stop point:** approve or revise this plan before implementation. The Git repository boundary also needs resolution before feature-branch commits.

## 10. Implementation status after approval — 17 November 2026

The findings above describe the original prototype and remain historical evidence. The app now has its own Git repository (`main` baseline `071698b`, active `feature/qr-attendance`), and the nine analyzer findings were corrected separately in `3a9b5b0`. The parent SDK repo was not changed.

Stage 3 adds a local-only Firebase foundation, role/ownership rules, schema, indexes, Auth/read service contracts, seed and emulator tests; see `DATA_MODEL.md`, `PLAN.md`, `CHANGELOG.md`, `SETUP.md` and root `firestore.rules`. No UI paths have been connected or replaced yet. Production Firebase configuration, Functions, concurrent identity provisioning, merge implementation, check-in validation and live notifications remain unimplemented. No claim is made that the old backend duplicate defect is fixed. Review is required at this stage before continuing.

## 11. Functions-stage status — 17 November 2026

The emulator-only TypeScript backend now implements the seven requested callables plus the pending-check-in trigger and feedback scheduler. See `FUNCTIONS.md` for inputs, outputs, error codes, merge semantics and test coverage. Literal normalized-email identity keys supersede the stage-3 hash convention at the user's request; only local fixture paths changed. Concurrent registration and two-coach walk-in tests verify one profile/UID in the emulator, but the legacy backend duplicate report remains unconfirmed.

No UI has been connected, no production services deployed and no paid services enabled. FCM is still a local delivery double; scheduled handler logic is tested against emulator data, with the local CLI v2 scheduler-dispatch limitation documented. Review is required before participant integration.

## 12. Participant and Workspace stage — 17 November 2026

The participant app is now connected to the local backend, with verified Auth/signup/Google, real event identity, separate RSVP/check-in UI, once-only details/current forms, live confirmation, feedback, profile and help. The old fake navigation paths were retired as approved, with real discovery/location/map/support components retained. Program symlinks were materialized without changing their contents.

Latest authorization requirement supersedes the earlier field-only coach role: coach access now requires an admin-issued claim and a protected active profile gate. Admin user/email listing, grant/revoke and assignment callables/UI are implemented, with one-profile participant/coach switching. Email-only no-app verification, rate limits and known-risk mitigations are documented in FUNCTIONS.md. See PARTICIPANT.md and SCREENSHOTS.md for scope and evidence; native OAuth/hardware and production/FCM/Hosting deployment remain manual/later work.

## Tester release preparation update (17 November 2026)

Current platform IDs, version/build, store state and signing/backend audit are recorded in [RELEASE.md](RELEASE.md). Version is now `1.0.1+5`, with native emulator/staging flavor preparation. Legacy backend remains unavailable for inspection; see [MIGRATION.md](MIGRATION.md). Neither staging readiness nor old-data migration is claimed. No upload/deployment/payment was performed by this preparation task; concurrent backend changes/deployment notes are recorded as unverified context in RELEASE.md.

## Staff tools update — 19 November 2026

The Play-page staff shortcut was the only entry point; full coach QR/roster UI and all-three-role editing were missing. They are now implemented with Me-tab entries, a dedicated Sessions manager (including in-place legacy edits), per-session venue/coach overrides and audited cancellation. [ADMIN_TOOLS.md](ADMIN_TOOLS.md) records exact taps, capability table, authorization and remaining bulk-operation/analytics limits. Owner account bootstrap and real Google ID-token/HTTP checks are recorded in CHANGELOG.md; internal-only release evidence is in UPLOADS.md. This increment does not migrate or delete participant data.
