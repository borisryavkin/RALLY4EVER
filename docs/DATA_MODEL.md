# Firestore schema and access contract

Stage 3 review, 17 November 2026. Timestamp means Firestore Timestamp (UTC instant); event timezone is an IANA name. Nullable fields are stored explicitly as null. This is the application contract; server-only writes still need validation in the next Functions stage. Rules do not validate Admin SDK writes.

## Collections and fields

| Path / ID | Fields | Client access |
| --- | --- | --- |
| `users/{uid}` | `uid`, `email` (verified address), `emailLower` (trim/lowercase), `role` (`participant`, `coach`, `admin`), `mergedInto` (null or canonical UID), `createdAt`, `updatedAt`; `firstName`, `lastName`, `postcode`, `mobile`, `injuries` strings; `emergencyContact: {name, mobile}`; `preferences: {useInReports, wellbeingCheckIns, showInWhosGoing, marketingEmails}` booleans; `about` optional string fields below | Verified active owner reads and updates permitted personal fields; admin manages. Identity/role/merge/createdAt immutable to owner. No participant creation/deletion. Coaches cannot read arbitrary profiles. |
| `users/{uid}/devices/{deviceId}` | `token` (nonempty string), `platform` (`android`, `ios`, `web`), `updatedAt` | Owner manages; admin access. No cross-user token reads. |
| `emailIdentities/{sha256(emailLower)}` | `emailLower`, `uid`, `createdAt` | Admin only. Trusted identity provisioning will transactionally reserve/update this mapping; not public email search. |
| `events/{eventId}` | `eventId`, unique `code`, `name`, `sport`, `status` (`draft`, `published`, `cancelled`), `startsAt`, `endsAt`, `timezone`, `coachUids: string[]`, `venue: {name, address, lat, lng}`, `geofenceRadiusM` (default 150), `requiredFormIds: string[]` | Active authenticated users read published events; assigned coaches also read their drafts; admin manages. No secrets here. |
| `eventSecrets/{eventId}` | Proposed for next stage: `currentSecretHash`, `rotatedAt`, `expiresAt`, `generation` | All client access denied, including admin. Trusted QR issuance/rotation callable only. Secret format/rotation cadence finalized in Functions stage. |
| `rsvps/{eventId}_{uid}` | `eventId`, `uid`, `createdAt`, `cancelledAt` (null or timestamp), `source` (`app`, `coach-added`) | Owner reads, creates own app intent and cancels/rejoins; assigned coach reads event intent; admin manages. `coach-added` creation is trusted/server-only for coaches. No attendance implied. Preserve original createdAt/source. |
| `checkins/{eventId}_{uid}` | `eventId`, `uid`, `scannedAt`, `method` (`app`, `camera`, `manual`), `lat`, `lng`, `distanceM`, `status` (`pending`, `confirmed`, `rejected`), `confirmedBy` (null or UID), `confirmedAt` (null or timestamp), `walkIn: bool`, `corrections: map[]`, `eventEndsAt` (timestamp for feedback selection) | Owner/assigned coach/admin reads. **All direct client writes denied**, including admin: use trusted callables. The next stage must enforce coach assignment and preserve scan history. |
| `forms/{formId}` | `formType` (`conduct`, `waiver`), `version` (positive integer), `title`, `content`, `updatedAt` | Active authenticated read, admin management. Seed text is explicitly a demo, not approved form wording. |
| `consents/{uid}_{formId}` | `uid`, `formId`, `formType`, `version`, `signedAt` | Owner signs only the current matching version with request timestamp. Same-version rewrite/older version denied; admin manages. Owner/admin reads. Version changes replace current receipt; full historical signatures can be added to a server-owned audit collection if required. |
| `feedback/{eventId}_{uid}` | `eventId`, `uid`, `rating` (integer 1–5), `tags: string[]`, `comment` (≤2,000 characters), `createdAt` | Owner creates once, after event end, only with confirmed check-in. Owner, assigned event coach and admin read; admin update/delete. Tags: `coaching`, `people`, `atmosphere`, `accessibility`, `timing`, `other` (≤6 entries). |
| `notifications/{type_eventId_uid}` | Proposed delivery fields: `type`, `eventId`, `uid`, `createdAt`, `readAt`, `deliveryStatus`, `attempts`, `sentAt`, `lastError`, `route` | Owner reads and may change only `readAt` to request time; admin manages; Functions will create/send/retry. User UID is the recipient (coach for scan alerts, attendee for feedback). Exact retry contract due in notification stage. |
| `mergeAudits/{mergeId}` | Proposed: `sourceUid`, `targetUid`, `actorUid`, `reason`, `createdAt`, `status`, `summary`, `conflicts` | Admin only. Merge dry-run/apply implementation deferred to Functions stage. |

`about` allowed fields: `ageRange`, `gender`, `accessNeed`, `currentActivity`, `referral`, `referralOther`, `loneliness`, `satisfaction`, `culturalBackground`. Missing answers stay missing; seed does not invent demographic answers. Existing in-memory UI defaults will be addressed during participant integration.

Proposed correction entry: `at`, `by`, `reason`, `previousStatus`, `newStatus`; retain `scannedAt`, method, location and original scan. Confirmation/rejection are server-authorized transitions; no client can forge either confirmations or corrections. Final correction policy belongs to Functions tests.

## Identity and roles

Normalize emails identically in Dart and server scripts with trim/lowercase; hash the normalized address to obtain a safe mapping document ID. Firebase Auth UID is canonical, never a coach-local profile ID. A verified Auth user must also have an active trusted profile. `mergedInto != null` blocks app access for the old UID. The protected profile `role` takes precedence over a custom claim; missing profile role falls back to the claim, then participant. This permits immediate field-based demotion even when an old token has elevated claims. Unknown roles have no privileged access. Clients cannot assign role fields or Auth claims.

This stage establishes the boundary, seed and real Auth emulator login tests. It does **not** yet implement account provisioning, concurrent normalized-email reservation, coach lookup/create, merge dry-run or real attendance callables. Do not claim the legacy duplicate defect fixed. Two-coach race/merge tests against emulator data are required in the Functions stage.

Admin access covers listed business collections, with explicit exceptions for secrets and attendance writes. Unknown paths remain denied to everyone. This intentionally routes admin attendance changes through audited server operations too.

## Queries and indexes

Use `status == published` for participant event queries, `coachUids array-contains uid` for coach events, `uid == currentUid` for personal RSVPs/attendance/notifications, and `eventId == assignedEventId` for coach rosters. Rules are not filters: unscoped collection reads by participants/coaches are denied. Attendance lookup uses a scoped query so an absent attendance record returns an empty result rather than attempting to authorize nonexistent document fields.

Composite indexes are listed in `firestore.indexes.json` for event discovery, coach events, personal intent/attendance, coach attendance queues, feedback selection, inbox and event feedback. Equality-only attendance lookup uses default index merging. Local rule tests do not prove that production composite indexes have been deployed; there is no deployment in this stage.

## Verification boundaries

Rule tests cover read/write denials and permitted paths with mocked claims; Auth integration tests log in to the real local Auth emulator and read through Firestore rules. Dart tests cover role precedence, normalization, separate intent/attendance states, event times and emulator fail-closed guards. Flutter SDK services are not yet wired to UI, and Android/iOS/web runtime integration is not claimed. No Storage collection/service is needed for this stage.

References used: [Firebase rules unit testing](https://firebase.google.com/docs/rules/unit-tests), [Auth emulator integration](https://firebase.google.com/docs/emulator-suite/connect_auth). These distinguish mocked rule contexts from actual emulator authentication; Admin SDK access bypasses rules.
