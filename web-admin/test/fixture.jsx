import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { adminError } from "../src/admin_helpers.mjs";
import {
  Programs,
  VenueEditor,
  Attendance,
  Venues,
  SessionEditor,
} from "../src/main.jsx";
const now = new Date();
now.setHours(11, 30, 0, 0);
const venue = {
  id: "ultimo",
  code: "ultimo-community-centre-nsw",
  name: "Ultimo Community Centre",
  address: "40 William Henry Street",
  suburb: "Ultimo",
  postcode: "2007",
  state: "NSW",
  lat: -33.88,
  lng: 151.196,
};
const programs = Array.from({ length: 63 }, (_, i) => ({
  id: "program-" + i,
  name:
    i === 0
      ? "Pickleball at Ultimo Community Centre"
      : i === 1
        ? "Community Tennis at Manly"
        : "Community " + (i % 2 ? "Tennis" : "Pickleball") + " " + (i + 1),
  sport: i % 2 ? "tennis" : "pickleball",
  status: i % 5 ? "active" : "draft",
  venue: { ...venue },
  timezone: "Australia/Sydney",
  scheduleText: "Thursdays 11:30–12:30",
  capacity: null,
  coachUids: ["coach-1"],
  coachNames: ["Dan"],
  photoUrl: "",
  notes: "Equipment provided",
  registrationStatus: "open",
  revision: 1,
}));
const events = Array.from({ length: 364 }, (_, i) => {
  const date = new Date(now);
  date.setDate(date.getDate() - 35 + i);
  return {
    id: "gen-session-" + i,
    programId: "program-" + (i % 63),
    catalogueManaged: true,
    name: programs[i % 63].name,
    sport: programs[i % 63].sport,
    venue: { ...venue },
    startsAt: date.toISOString(),
    endsAt: new Date(+date + 3600000).toISOString(),
    timezone: "Australia/Sydney",
    status: "published",
    bookedCount: i % 7,
    revision: 1,
    capacity: 20,
    coachUids: ["coach-1"],
  };
});
const users = [
  {
    uid: "coach-1",
    firstName: "Dan",
    email: "dan@example.test",
    role: "coach",
  },
  {
    uid: "member-1",
    firstName: "Priya",
    lastName: "Lal",
    emailLower: "priya@example.test",
    role: "participant",
  },
];
const params = new URLSearchParams(location.search),
  screen = params.get("screen") ?? "Attendance";
function Fixture() {
  const [data, setData] = useState({
      programs,
      events,
      venues: [venue],
      forms: [],
    }),
    [notice, setNotice] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [show, setShow] = useState(true);
  const api = React.useCallback(async (name, d = {}) => {
    window.__calls ??= [];
    window.__calls.push({ name, data: d });
    await new Promise((r) => setTimeout(r, 180));
    if (name === "saveProgram") {
      if (params.get("fail"))
        throw {
          details: { reason: "invalid-capacity" },
          message:
            "Capacity must be 1–5000, or unlimited [400] (invalid-capacity)",
        };
      setData((old) => ({
        ...old,
        programs: [
          ...old.programs.filter((p) => p.id !== d.programId),
          {
            ...d.program,
            operations: d.operations,
            id: d.programId ?? "created-program",
            revision: 2,
          },
        ],
      }));
      return { programId: d.programId ?? "created-program" };
    }
    if (name === "adminSaveSession") return {};
    if (name === "adminAttendanceCounts")
      return {
        counts: Object.fromEntries(
          d.eventIds.map((id, i) => [
            id,
            { registered: i % 7, checkedIn: i % 4 },
          ]),
        ),
      };
    if (name === "adminFindPeople")
      return {
        people: users
          .filter((x) =>
            JSON.stringify(x).toLowerCase().includes(d.search.toLowerCase()),
          )
          .map((x) => ({ ...x, email: x.email ?? x.emailLower ?? "" })),
        cursor: null,
      };
    if (name === "adminPersonAttendance")
      return {
        person: { ...users[1], email: users[1].emailLower },
        rows: events
          .slice(d.cursor ? 33 : 30, d.cursor ? 36 : 33)
          .map((e, i) => ({
            eventId: e.id,
            program: e.name,
            venue: e.venue.name,
            startsAt: e.startsAt,
            timezone: e.timezone,
            status: i ? "confirmed" : "pending",
            scannedAt: e.startsAt,
            distanceM: 42 + i,
            decision: i ? "Confirmed by Dan" : "Awaiting coach",
            countedIn: true,
          })),
        cursor: params.get("historyPages") && !d.cursor ? "history-next" : null,
      };
    if (name === "getEventConsole")
      return {
        event: events.find((e) => e.id === d.eventId),
        roster: [
          {
            uid: "member-1",
            firstName: "Priya",
            email: "priya@example.test",
            countedIn: true,
            checkinStatus: "confirmed",
            scannedAt: now.toISOString(),
            distanceM: 43,
            walkIn: false,
          },
        ],
      };
    if (name === "adminProgramDeletion") {
      if (d.operation === "purge") {
        setData((old) => ({
          ...old,
          programs: old.programs.filter((p) => p.id !== d.programId),
        }));
        return { permanent: true };
      }
      if (["preview", "preview-purge"].includes(d.operation))
        return {
          allowed: !params.get("blocked"),
          blocked: !!params.get("blocked"),
          registrations: params.get("blocked") ? 1 : 0,
          checkins: 0,
          attendance: 0,
          feedback: 0,
          futureGenerated: 8,
          retainedSessions: 2,
          sessionCount: 10,
        };
      setData((old) => ({
        ...old,
        programs: old.programs.map((p) =>
          p.id === d.programId
            ? {
                ...p,
                status: d.operation === "restore" ? "draft" : "deleted",
                deletedAt:
                  d.operation === "restore" ? null : new Date().toISOString(),
              }
            : p,
        ),
      }));
      return {};
    }
    if (name === "adminVenueDeletion") {
      if (d.operation === "purge") {
        setData((old) => ({
          ...old,
          venues: old.venues.filter((v) => v.id !== d.venueId),
        }));
        return { permanent: true };
      }
      if (["preview", "preview-purge"].includes(d.operation))
        return {
          allowed: !params.get("venueBlocked"),
          programs: params.get("venueBlocked") ? 1 : 0,
          sessions: 0,
          revision: 0,
        };
      setData((old) => ({
        ...old,
        venues: old.venues.map((v) =>
          v.id === d.venueId
            ? {
                ...v,
                deletedAt:
                  d.operation === "restore" ? null : new Date().toISOString(),
                revision: 1,
              }
            : v,
        ),
      }));
      return {};
    }
    if (name === "adminFindCoordinates")
      return {
        results: [
          {
            lat: -33.88,
            lng: 151.196,
            label: "Ultimo Community Centre, Sydney, NSW",
            attribution: "© OpenStreetMap contributors",
          },
        ],
      };
    if (name === "adminSaveVenue") {
      setNotice("Venue saved");
      setShow(false);
      return { venueId: d.venueId };
    }
    throw Error("Unmocked fixture function: " + name);
  }, []);
  async function action(fn, message = "Saved", onError) {
    if (busy) return false;
    setBusy(true);
    setError("");
    try {
      await fn();
      setNotice(message);
      return true;
    } catch (e) {
      setError(adminError(e));
      onError?.(e);
      return false;
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="shell">
      <aside>
        <a className="brand">
          <img src="/logo.svg" alt="Rally4Ever" />
          <span>ADMIN</span>
        </a>
        <nav>
          {["Sessions", "Programs", "Venues", "Users", "Attendance"].map(
            (p) => (
              <button key={p} aria-current={screen === p ? "page" : undefined}>
                {p}
              </button>
            ),
          )}
        </nav>
        <div className="sidebar-foot">
          Local test fixture · no Firebase writes
        </div>
      </aside>
      <main>
        <header>
          <div>
            <div className="eyebrow">RALLY4EVER / ADMINISTRATION</div>
            <h1>{screen}</h1>
          </div>
          <button onClick={() => setNotice("Refreshed")}>Refresh</button>
        </header>
        {error && (
          <div className="notice error" role="alert">
            {error}
          </div>
        )}
        {notice && (
          <div className="notice" role="status">
            {notice}
          </div>
        )}
        {screen === "Attendance" ? (
          <Attendance
            data={data}
            users={users}
            api={api}
            action={action}
            busy={busy}
          />
        ) : screen === "SessionDetails" ? (
          <SessionEditor
            row={{ ...events[20], id: undefined }}
            data={data}
            users={users}
            busy={busy}
            onClose={() => {}}
            onSave={(changes, operations) =>
              action(
                () => api("adminSaveSession", { changes, operations }),
                "Session saved",
              )
            }
          />
        ) : screen === "VenueList" ? (
          <Venues data={data} action={action} busy={busy} api={api} />
        ) : screen === "Programs" ? (
          <Programs
            data={data}
            users={users}
            api={api}
            action={action}
            busy={busy}
          />
        ) : (
          show && (
            <VenueEditor
              row={{
                ...venue,
                id: undefined,
                code: "",
                name: "",
                address: "",
                suburb: "",
                postcode: "",
                lat: null,
                lng: null,
              }}
              venues={data.venues}
              api={api}
              action={action}
              busy={busy}
              onClose={() => setShow(false)}
            />
          )
        )}
      </main>
    </div>
  );
}
createRoot(document.getElementById("fixture")).render(<Fixture />);
