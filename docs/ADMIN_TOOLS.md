# Admin and coach tools — 19 November 2026

## Entry points and audit

Before this change, the Play page had a small **Admin view** / **Coach view** shortcut below the sport filters (`page='role'` in `lib/participant/app.dart`). Admin had **Manage programs & calendar** (`adminCatalogue`) and **Manage users & event coaches** (`adminAccess`). Program creation/edit/archive and dated session creation existed. Coach view showed pending summaries and participant session cards: it did not open an event QR/roster console. Users could only toggle coach access, not select all three roles. Session editors inherited the program venue/coaches and could not override them.

The app uses an in-app page switch, not a separate application or URL-addressable `/admin` router. The same role gates work in Flutter native and Web.

### Exact taps in the new build

Sign in with the existing account; after a role grant, sign out/in or resume the app to refresh claims.

- **Me → Admin → Programs**: search/filter All, draft, published, archived; Create program; Edit / archive; Publish / Unpublish with a reason. Database status `active` means published. Publishing confirms the admin has reviewed imported program details. Unpublishing does not cancel existing dated sessions.
- **Me → Admin → Sessions**: select a published program → Create session from program → timezone, venue/address/coordinates/state, assigned coaches, start/end, capacity, reservation status and notes → enter reason → Save session. Existing sessions → Edit / cancel / assign coaches. Direct Cancel session also works after a program has been unpublished and retains RSVP/attendance records.
- **Me → Admin → Users & coach assignment**: search by email prefix → Search → enter access-change reason → Account role dropdown (participant/coach/admin). Coach access switch remains for a secondary coach grant, including an admin's coach role. Your own role controls are disabled to prevent lockout; another admin must change them.
- On that same Users screen: **Assign event coaches** → choose session → select coach checkboxes → Save assignments (reason required).
- **Me → Coach tools → Open session console**: admins see all sessions, coaches only assigned sessions. See separate counted-in, checked-in and confirmed totals; QR rotates automatically with server-issued five-minute expiry, or tap Rotate QR now. Filter All / Counted in / Checked in / Walk-ins; pending arrivals show scan time/distance and Confirm arrival / Reject arrival.
- Back → Me or **Switch to participant view** retains the same signed-in UID/profile. Existing Play-page staff shortcuts remain available. Participants see neither Me entry and receive server permission errors for staff operations.

## Capabilities and limits

| Capability | Before | Now |
|---|---|---|
| Create/edit/publish/unpublish programs | Editor existed, no quick publishing/filter | Editor plus search/status filters and reasoned quick publish/unpublish |
| Create/edit/cancel sessions | Partial, inherited venue/coaches | Session manager, per-session venue/timezone/capacity/coaches, cancellation independent of parent status |
| Assign session coaches | Existing separate user panel | Preserved and added to session editor |
| Promote/demote all three roles | Coach toggle only | Audited trusted `setUserRole`; claims plus protected profile gate; stale staff tokens fail after revocation |
| Who counted in / checked in | Participant views/pending summary | Staff roster shows intent and attendance separately, filters and confirmations |
| Event-specific rotating QR | Backend only | Real QR image, expiry, rotation, admin-any / assigned-coach restriction |

Editing session details remains limited to future sessions without scans, to preserve original attendance context. Cancellation changes status and closes reservations without deleting historical records. Legacy sessions without `programId` can also be edited in place through Edit / assign coaches (legacy session), with the same future/no-scans restriction; no migration or new profile/session ID is needed. Limits: 500 programs, 300 staff sessions, 500 RSVPs plus 500 scans per console request; large datasets need pagination. Bulk confirmation, walk-in creation/correction screens, merge/form-version UI and feedback analytics are still separate follow-up work; their existing backend operations are preserved.

## Backend and authorization

New callables (region `australia-southeast1`, maxInstances 1):

- `listStaffSessions({})` → `{events, limited}`. Admin all; coach assigned only; participant `permission-denied/staff-required`.
- `getEventConsole({eventId})` → `{event, roster, limited}`. Admin any; assigned coach only. Roster includes public name/email, RSVP boolean, attendance status, original scan time/distance, walk-in and correction count. No private phone/emergency details or QR secrets.
- `cancelSession({eventId, revision?, reason})` → `{eventId,status:'cancelled'}`. Admin only; checks revision and rejects ended sessions, closes reservations and writes `catalogueAudits`.
- `setUserRole({uid, role, reason})` supports participant/coach/admin; legacy `{role:'coach',enabled,reason}` remains supported. Verifies target Auth account before granting staff, protects own/last admin access, serializes per-target changes with `roleChanges`, records `roleAudits`, preserves unrelated claims and participant access. Cross-service failures leave staff access closed; failed role audits require operator review/retry.
- `saveSession` now accepts optional `venue`, `coachUids`, `timezone` overrides; program defaults stay unchanged.

Firestore rules are unchanged: role/identity fields stay protected; participants cannot read staff-only records, and event-secret client access is denied even for admins. Only trusted callables issue QR values. No data/profile/Auth user is deleted by this change. Sign-in now waits for all required profile streams before choosing home versus onboarding, preventing an existing account from being routed using an empty profile.

## Validation and release evidence

See the task's latest entry in [CHANGELOG.md](CHANGELOG.md) and [UPLOADS.md](UPLOADS.md) for completed test counts, real HTTP results and the uploaded build. Run the read-only local access probe with `node scripts/check-staff-staging.mjs`, then open `http://localhost:57821`; choose existing Google accounts only. Tokens remain in browser memory; local `/tmp/r4e-staging-access-proof-*.json` reports contain claims/status/counts, never tokens or keys. No browser-hosted admin deployment or new Firebase Web app registration is included.

### Real-project check results

On 19 November: bootstrap preserved owner UID `C0m1PlHfF3eXVsKoJX78U3HPmyt1`; actual Google/Firebase ID token returned `role=admin`, `roles=[participant,admin]`. HTTP results: admin `listPrograms` 200 (61), `listUsers` 200 (4), `listStaffSessions` 200 (12); an existing participant received 403 / `PERMISSION_DENIED` for all three. The real Flutter app loaded those admin screens and issued a real Epping-session QR. Before/after counts remained 4 profiles, 61 programs, 12 events and 5 Auth accounts. No real participant was promoted/demoted for the test. Emulator tests separately verify role grants, revoked-coach stale-token rejection, Workspace-email-only rejection, admin-any/coach-assigned QR access, edits and cancellation preserving scan records.
