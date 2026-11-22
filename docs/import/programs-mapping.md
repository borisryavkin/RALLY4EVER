# Programs import: schema mapping and decisions

Written before any data was changed (Phase 0). Source spreadsheets live only
in `data-private/` (git-ignored, never committed).

## 1. Existing Firestore schema (reused, not reinvented)

Confirmed against `firestore.rules`, `docs/DATA_MODEL.md`, `docs/WEB_ADMIN.md`
and `functions/src/catalogue.ts` (`validateProgram`/`validateVenue`), and by
reading the **real** `rally4ever-3adaf` project directly (read-only) on
2026-11-22: **61 programs, 14 venues, 48 events** already exist.

- **`venues/{id}`** already exists as its own top-level collection (added
  20 Nov 2026, see `WEB_ADMIN.md`): `id, code, name, address, suburb,
  postcode, state, lat, lng, photoUrl, isDemo, revision, createdAt,
  updatedAt, updatedBy`. Rule: `allow read: if active();` — **any** signed-in
  verified participant can read the **entire** document, so no
  participant/admin field split is possible within this doc; operational
  data cannot live here.
- **`programs/{id}`**: `name, sport (tennis|pickleball), status
  (draft|active|archived), venue {name,address,suburb,postcode,state,
  lat,lng} (embedded, separate from the venues/{id} catalogue), timezone,
  scheduleText (free text, ≤500 chars — there is no structured day/time/
  frequency/startDate field on a program), coachUids, coachNames,
  notes, photoUrl, capacity, registrationStatus`. Rule:
  `allow read: if active() && (status in ['active','archived'] || admin());`
  — **a draft program is already invisible to participants and visible to
  admins under the existing rules, with no rule change needed.** "Active"
  is this schema's "published".
- **`events/{id}`**: actual dated/timed bookable sessions, optionally
  linked to a program via `programId` + `catalogueManaged: true`
  (created through the admin "Generate sessions" action, not by this
  import — see §6).
- No admin-only "operational" collection for coach/contact/notes exists
  yet. I created two new ones (see §4).

### Gap named by your Phase-0 instruction #1

Venues **do** already exist as their own collection — nothing to create
there. The gap is the other direction: `programs` has no structured
day/time/frequency/start-date fields, only `scheduleText`. Reusing the
schema means folding parsed day/time/frequency/start date into a
human-readable `scheduleText`, and keeping the structured, machine-parsed
values in the new admin-only companion doc (§4) so nothing is lost.

### `coachNames` tension (flagged, not silently resolved)

`programs/{id}.coachNames` is part of the existing schema and **is**
participant-readable today (e.g. the real `nsw-tennis-armidale` program
already has `coachNames: ["Damian Roff","Glen"]`, clearly populated by
hand). Your instruction says coach names must never enter
participant-readable data from this import. I followed your explicit
instruction over the pre-existing field's usual behaviour: this import
**never writes `coachNames`** on any document it creates or updates, and
real coach names only go into the admin-only companion doc. I'm not
touching the field on any already-matched program.

## 2. Real existing data found (read-only check, 2026-11-22)

- 61 `programs`, mostly from an **earlier pass over this same master
  spreadsheet** (IDs already follow `<state>-<sport>-<slug(name)>`, e.g.
  `nsw-tennis-armidale`, `vic-pickleball-albury-wodonga`). About 2/3 are
  `status: active, needsVerification: false` with clean, human-edited
  `scheduleText` (e.g. "Every Sunday (Weather Permitting) · 2-3pm ·
  During School Terms") — clear signs of manual admin review through the
  web-admin console. The rest (mostly all of QLD/SA/VIC, plus a handful
  of NSW ones) are still `status: draft, needsVerification: true` with raw
  auto-generated `scheduleText` like "Thursday, weather permitting, during
  school terms · 10:00 AM - 11:00 AM".
- **Decision**: treat any existing program with `needsVerification: false`
  (i.e. already reviewed/published by a human) as **don't touch its
  content** — match it, log the match, but do not overwrite `name`,
  `scheduleText`, `venue`, `status`, or anything else a human already
  cleaned up. Only create/update documents that are new, or that are
  still `draft`/`needsVerification: true` (i.e. untouched since the
  original mechanical import). This is the single most important safety
  rule in this import and is driven directly by what I found in the real
  project, not a guess.
- **Pre-existing near-duplicates already in the live data** (predate this
  import, surfaced here because they're directly relevant):
  `nsw-tennis-bar-beach` (draft) vs `nsw-tennis-bar-beach-newcastle`
  (active) — same venue/suburb; and `nsw-tennis-paddington-trumper-park`
  (draft) vs `nsw-tennis-paddington-trumper-park-tennis-centre` (active) —
  same venue. Both look like the draft was superseded by a cleaned-up
  active entry under a slightly different name/ID. I did not merge these
  (out of scope — pre-dates this import and isn't something a mechanical
  script should merge unsupervised); flagging for your review.
- 5 venues are clearly demo/test fixtures (`isDemo: true`, or an
  obviously-fake name like "Photo upload verification (demo)"). **Excluded
  from all matching** — spreadsheet rows are never matched against demo
  venues, and demo venues are never updated by this import.

## 3. Master spreadsheet: actual sheets and columns

`R4E_PROGRAMS_MASTER_SPREADSHEET.xlsx` — all four sheets named in the task
exist exactly as named (including the leading space in
`" Active Pickleball Programs"`). `Council Grants` is genuinely empty
(1×1). Row counts are **non-empty data rows**, not the sheet's padded
dimensions:

| Sheet | Rows | Status values actually present |
| --- | --- | --- |
| Active Tennis Programs | 33 | Active (30), TBC (2), About to start (1) |
| " Active Pickleball Programs" | 8 | Active (6), TBC (2) |
| Prospective programs | 65 | blank (56), waiting (2), running? (4), Pending (2), grant submitted (1) |
| On Hold Inactive | 37 | On Hold/on hold (12), Inactive/inactive/inactice (19), Cancelled/cancelled (2), free-text variants like "from end T3 2025 ON HOLD" (2), "Occasional ON HOLD early 2025" (1), "Inactive club sold" (1) |

**Status rule used**: a row becomes `active` (published) only if its
`Status` cell, trimmed and lower-cased, is **exactly** `"active"`. Every
other value — including `"About to start"`, blank, and every free-text
on-hold/inactive/cancelled variant above — becomes `status: draft`. This
is a literal, conservative reading of your instruction and never guesses
at intent for an ambiguous status string.

Columns actually present (confirmed from row 1, not assumed):
`Active Tennis Programs` has `State/Suburb, State, Status, SC Name, SC
Activities, Attendance, Community Services Associated, Community Contact,
Subsidised, Start Date, Day, Frequency (During School Term), Time, Tennis
Centre, Address, Posting address, Coach name, Coach Number, Contact Name,
Contact number, Contact Email, Poster Distributed, QR Code, Tea/Coffee,
Closed Program, Notes (…), How the program is going #, Equipment/
merchandise needed, Any issues, cuppa/vouchers, help reaching community,
new poster/videos, WhatsApp group, community impact`. Pickleball/
Prospective/On-Hold sheets are similar with minor renames (`Location` vs
`State/Suburb`, `Occurance` vs `Frequency`, `Facility Name/Org` vs `Tennis
Centre`). **Everything from "Community Contact" onward through the last
column is operational/admin-only**, matching your "never import" list
exactly.

## 4. University matrix: actual structure (not a clean table)

- `Universities` and the finance sheets (`Pilot Finance`, `Semester
  Finance`, `Copy of Semester Finance`, `2026 Semester  Finance`) are
  skipped entirely, per instruction.
- `SchedulingCoaches` is **not** one table: it's a report with a section
  header per university (e.g. "Wollongong"), a repeated sub-header row
  (`Coach | Schedule Dates | Times | Day of the week`), then dated rows,
  repeated per term. Coach names are the first column — admin-only.
- The 7 per-university sheets (`NSW - UNSW`, `NSW - Macquarie University`,
  `NSW - University of Sydney`, `NSW - Western Sydney University`,
  `University of Wollongong`, `QSL - Griffith University`, `VIC - Deakin
  University`) are each a free-form "working notebook", not a table: a
  Contacts block (names/emails/phones — admin-only), a Facility/Location
  block (venue name + address — this is what I used for venue matching), a
  Fundamentals/pricing block (skipped), and — where present — a genuinely
  tabular **Schedule** block (`Date | Day of Week | Time | Location |
  Coach | Turned Up | Registered`). `Turned Up`/`Registered` are
  attendance numbers — admin-only per your instruction.
- **Found and corrected a data bug rather than trusting it**: on
  `NSW - UNSW`'s Schedule block, the `Day of Week` column drifts through
  all seven days in sequence (Tue, Wed, Thu, Fri, Sat, Sun, Mon, Tue, …)
  even though the `Date` column is a genuine weekly series — a classic
  Excel fill-down artifact, not real data. The importer computes the
  weekday from the `Date` cell itself (authoritative) and only uses the
  free-text `Day of Week` column as a cross-check; a mismatch rate over
  20% for a sheet is written to `needs-review.csv` rather than trusted
  silently.
- **Found a likely copy-paste error, not corrected, flagged for you**:
  both `QSL - Griffith University` and `VIC - Deakin University` sheets
  have cell A1 literally reading `"University of Wollongong"` (and
  Griffith's facility is listed as "KDV Sports Pickleball Courts",
  Southport — a real Gold Coast venue, so the sheet's *data* does look
  Griffith-specific; it's only the stray title cell that's wrong). I used
  the **sheet name** (Griffith → QLD, Deakin → VIC) to decide the
  program's state/university, not the stale in-cell title, but you should
  double check these two sheets are actually about the right university.
- Rows below each Schedule block are unstructured scratch notes
  (including, on `NSW - UNSW`, someone's personal mobile number jotted in
  a stray cell). These are **not parsed at all** — attempting to extract
  meaning from free-form notebook scrawl is both low-value and a privacy
  risk if a personal number were accidentally machine-read into any
  stored field. Only the clearly-tabular Schedule block, the
  Facility/Location block, and the single "NOTES:" cell (verbatim, into
  the admin-only doc) are read.
- "Mark as unpublished any program whose dates are marked 'Need to
  confirm'" — I did not find a structured status field with this exact
  value; it appears only as free text in notes (e.g. "Need to confirm
  dates" on `University of Wollongong`, whose Schedule block is in fact
  empty). This falls out naturally from the existing rule "a program
  needs a real day/time to be published": a sheet with no usable Schedule
  rows has nothing to parse, so it's `draft` regardless. No special-case
  string match was needed or added.

## 5. New admin-only storage for operational data

Two new top-level collections, rules added following the exact existing
`catalogueAudits` pattern (`allow read: if admin(); allow write: if
false;` — there is no existing "venue's own coach" relationship anywhere
in this schema to extend, since coaches are assigned per-`event` via
`coachUids`, never per-venue or per-program; I did not invent one):

- **`programOperational/{programId}`**: `coachName, coachContact,
  contactName, contactPhone, contactEmail, communityContact, notes,
  howItsGoing, equipmentNeeded, issues, whatsappGroup, attendance,
  rawTime, rawStartDate, importKey, importSource, importedAt`.
- **`venueOperational/{venueId}`**: mirrors the above where applicable
  (contact details found against a venue rather than a program), plus
  `rawAddress` when an address couldn't be geocoded.

Document ID matches the `programs`/`venues` document it describes, so
admins can look an operational doc up directly by the same ID shown in
the existing web-admin Programs/Venues screens (no new UI built, per
instruction #2 — the existing admin console's draft/published filters
already satisfy "an admin-only way to see unpublished imports").

## 6. Deliberately out of scope this pass

- **No dated `events` are generated.** Programs/venues are created or
  updated; turning a published program into actual bookable, dated
  sessions is the existing "Generate sessions" admin action
  (`WEB_ADMIN.md` §4), which needs a real date range/duration decision
  that's yours to make, not something to infer silently for 60+ programs.
- **No Firestore rules change was needed for `programs`/`venues`
  themselves** — the existing draft/active split already does exactly
  what's needed.
