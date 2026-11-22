import React, { useState, useEffect, useMemo, useRef } from "react";
import { call } from "./firebase";
import { Field, Select, Button, Status } from "./controls";
import {
  attendanceSessions,
  dateRange,
  adminError,
  downloadFile,
} from "./admin_helpers.mjs";
import { csv, localTime, displaySessionTime } from "./helpers.mjs";

const sortHistory = (rows) =>
  [...new Map(rows.map((r) => [r.eventId, r])).values()].sort(
    (a, b) => Date.parse(b.startsAt ?? 0) - Date.parse(a.startsAt ?? 0),
  );
export function SessionPicker({ data, api, onSelect, selected }) {
  const [f, setF] = useState(() => ({
      search: "",
      program: "",
      sport: "",
      ...dateRange(),
    })),
    [offset, setOffset] = useState(0),
    [counts, setCounts] = useState({}),
    [error, setError] = useState("");
  const rows = useMemo(
    () => attendanceSessions(data.events, data.programs, f),
    [data.events, data.programs, f],
  );
  const visible = rows.slice(offset, offset + 24),
    ids = visible.map((e) => e.id).join("|");
  const update = (k, v) => {
    setF((old) => ({ ...old, [k]: v }));
    setOffset(0);
  };
  const quick = (mode) => {
    setF((old) => ({ ...old, ...dateRange(mode) }));
    setOffset(0);
  };
  useEffect(() => {
    let live = true;
    setError("");
    if (!ids) {
      setCounts({});
      return;
    }
    api("adminAttendanceCounts", { eventIds: ids.split("|") })
      .then((r) => {
        if (live) setCounts(r.counts);
      })
      .catch((e) => {
        if (live) setError(adminError(e));
      });
    return () => {
      live = false;
    };
  }, [ids, api]);
  const groups = new Map();
  for (const e of visible) {
    const date = localTime(e.startsAt, e.timezone).slice(0, 10);
    if (!groups.has(date)) groups.set(date, []);
    groups.get(date).push(e);
  }
  return (
    <section
      className="attendance-picker"
      aria-labelledby="session-picker-heading"
    >
      <h2 id="session-picker-heading">Find a session</h2>
      <div className="filters">
        <Field
          label="Search sessions by program, venue or date"
          value={f.search}
          onChange={(e) => update("search", e.target.value)}
        />
        <Select
          label="Program"
          value={f.program}
          onChange={(x) => update("program", x)}
          options={[
            { value: "", label: "All programs" },
            ...data.programs
              .filter((p) => !p.deletedAt)
              .map((p) => ({ value: p.id, label: p.name })),
          ]}
        />
        <Select
          label="Sport"
          value={f.sport}
          onChange={(x) => update("sport", x)}
          options={[
            { value: "", label: "All sports" },
            { value: "tennis", label: "Tennis" },
            { value: "pickleball", label: "Pickleball" },
          ]}
        />
        <Field
          label="From date"
          type="date"
          value={f.from}
          onChange={(e) => update("from", e.target.value)}
        />
        <Field
          label="Through date"
          type="date"
          value={f.to}
          onChange={(e) => update("to", e.target.value)}
        />
      </div>
      <div className="quick-dates">
        <Button secondary onClick={() => quick("today")}>
          Today
        </Button>
        <Button secondary onClick={() => quick("week")}>
          This week
        </Button>
        <Button secondary onClick={() => quick("nearby")}>
          Last / next 14 days
        </Button>
        <Button secondary onClick={() => quick("all")}>
          All dates
        </Button>
      </div>
      <p className="muted">
        {rows.length} matching sessions · nearest to now first · dates shown in
        each venue’s timezone
      </p>
      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}
      <div className="session-results">
        {[...groups].map(([date, events]) => (
          <section key={date} aria-label={"Sessions on " + date}>
            <h3>{date}</h3>
            <ul>
              {events.map((e) => (
                <li key={e.id}>
                  <button
                    className="session-result"
                    aria-pressed={selected === e.id}
                    onClick={() => onSelect(e.id)}
                  >
                    <span>
                      <strong>
                        {data.programs.find((p) => p.id === e.programId)
                          ?.name ?? e.name}
                      </strong>
                      <small>
                        {e.venue?.name} · {e.venue?.suburb}
                      </small>
                      <time dateTime={e.startsAt}>
                        {displaySessionTime(e.startsAt, e.timezone)} ·{" "}
                        {e.timezone}
                      </time>
                    </span>
                    <span className="session-counts">
                      {counts[e.id] ? (
                        <>
                          {counts[e.id].limited ? "At least " : ""}
                          {counts[e.id].registered} registered /{" "}
                          {counts[e.id].checkedIn} checked in
                        </>
                      ) : (
                        <>Loading attendance counts…</>
                      )}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
      {!rows.length && (
        <p>
          No sessions match these filters. Try All dates or a different search.
        </p>
      )}
      {rows.length > 24 && (
        <div className="pager">
          <Button
            secondary
            disabled={!offset}
            onClick={() => setOffset(Math.max(0, offset - 24))}
          >
            Previous sessions
          </Button>
          <span>
            {offset + 1}–{Math.min(offset + 24, rows.length)} of {rows.length}
          </span>
          <Button
            secondary
            disabled={offset + 24 >= rows.length}
            onClick={() => setOffset(offset + 24)}
          >
            Next sessions
          </Button>
        </div>
      )}
    </section>
  );
}
export function PersonAttendance({ api }) {
  const [search, setSearch] = useState(""),
    [people, setPeople] = useState([]),
    [cursor, setCursor] = useState(null),
    [finding, setFinding] = useState(false),
    [person, setPerson] = useState(null),
    [history, setHistory] = useState([]),
    [historyCursor, setHistoryCursor] = useState(null),
    [offset, setOffset] = useState(0),
    [peopleOffset, setPeopleOffset] = useState(0),
    [working, setWorking] = useState(false),
    [error, setError] = useState("");
  const request = useRef(0);
  async function find(term, next = null, append = false) {
    const seq = ++request.current;
    setFinding(true);
    setError("");
    try {
      let matches = [],
        after = next;
      for (let i = 0; i < 5; i++) {
        const r = await api("adminFindPeople", {
          search: term,
          ...(after ? { cursor: after } : {}),
        });
        if (seq !== request.current) return;
        matches.push(...r.people);
        after = r.cursor;
        if (matches.length || !after) break;
      }
      setPeople((old) => (append ? [...old, ...matches] : matches));
      setCursor(after);
    } catch (e) {
      if (seq === request.current) setError(adminError(e));
    } finally {
      if (seq === request.current) setFinding(false);
    }
  }
  useEffect(() => {
    request.current++;
    setPeople([]);
    setCursor(null);
    setPeopleOffset(0);
    if (search.trim().length < 2) {
      setFinding(false);
      return;
    }
    const timer = setTimeout(() => find(search.trim()), 350);
    return () => {
      clearTimeout(timer);
      request.current++;
    };
  }, [search, api]);
  async function loadPerson(p, append = false) {
    if (working) return;
    setWorking(true);
    setError("");
    if (!append) {
      setPerson(p);
      setHistory([]);
      setHistoryCursor(null);
      setOffset(0);
    }
    try {
      const r = await api("adminPersonAttendance", {
        uid: p.uid,
        ...(append && historyCursor ? { cursor: historyCursor } : {}),
      });
      setHistory((old) => sortHistory(append ? [...old, ...r.rows] : r.rows));
      setHistoryCursor(r.cursor);
    } catch (e) {
      setError(adminError(e));
    } finally {
      setWorking(false);
    }
  }
  async function exportPerson() {
    if (working || !person) return;
    setWorking(true);
    setError("");
    try {
      let all = [...history],
        next = historyCursor;
      while (next) {
        const r = await api("adminPersonAttendance", {
          uid: person.uid,
          cursor: next,
        });
        all.push(...r.rows);
        if (r.cursor === next)
          throw Error("History could not be fully exported. Please retry.");
        next = r.cursor;
      }
      downloadFile(
        "attendance-" + person.uid + ".csv",
        csv(
          sortHistory(all).map((r) => ({
            ...r,
            uid: person.uid,
            name: [person.firstName, person.lastName].filter(Boolean).join(" "),
            email: person.email,
          })),
          [
            "uid",
            "name",
            "email",
            "startsAt",
            "timezone",
            "program",
            "venue",
            "status",
            "countedIn",
            "walkIn",
            "scannedAt",
            "distanceM",
            "confirmedBy",
            "decision",
          ],
        ),
      );
    } catch (e) {
      setError(adminError(e));
    } finally {
      setWorking(false);
    }
  }
  return (
    <section
      className="person-attendance"
      aria-labelledby="person-search-heading"
    >
      <h2 id="person-search-heading">Search a person</h2>
      <Field
        label="Name or email"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Type at least two characters"
      />
      {finding && <p role="status">Searching profiles…</p>}
      {search.trim().length >= 2 && !finding && !people.length && (
        <p>
          No matches in this page of profiles.
          {cursor ? " Search the next page below." : ""}
        </p>
      )}
      <ul className="person-matches">
        {people.slice(peopleOffset, peopleOffset + 20).map((p) => (
          <li key={p.uid}>
            <Button secondary disabled={working} onClick={() => loadPerson(p)}>
              {p.firstName} {p.lastName}
              <small>
                {p.email}
                {p.guest ? " · Walk-in profile" : ""}
              </small>
            </Button>
          </li>
        ))}
      </ul>
      {(people.length > 20 || cursor) && (
        <div className="pager">
          <Button
            secondary
            disabled={!peopleOffset}
            onClick={() => setPeopleOffset(Math.max(0, peopleOffset - 20))}
          >
            Previous people
          </Button>
          <Button
            secondary
            disabled={finding}
            onClick={async () => {
              if (peopleOffset + 20 < people.length)
                setPeopleOffset(peopleOffset + 20);
              else {
                const oldLength = people.length;
                await find(search.trim(), cursor, true);
                setPeopleOffset(oldLength);
              }
            }}
          >
            {peopleOffset + 20 < people.length
              ? "More matches"
              : "Search next profiles"}
          </Button>
        </div>
      )}
      {error && (
        <p className="notice error" role="alert">
          {error}
        </p>
      )}
      {person && (
        <>
          <div className="section-line">
            <h3>
              {person.firstName} {person.lastName} · {person.email}
            </h3>
            <div className="row-actions">
              <Button
                secondary
                disabled={working}
                onClick={() => loadPerson(person)}
              >
                Refresh person
              </Button>
              <Button secondary disabled={working} onClick={exportPerson}>
                {working ? "Loading…" : "Export person CSV"}
              </Button>
            </div>
          </div>
          <p className="muted">
            {history.length} records loaded
            {historyCursor ? " · more history available" : ""}. Sorted by
            session date; Export includes all pages.
          </p>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Date / program</th>
                  <th>Venue</th>
                  <th>Status</th>
                  <th>Scanned at</th>
                  <th>Distance</th>
                  <th>Coach decision</th>
                </tr>
              </thead>
              <tbody>
                {history.slice(offset, offset + 25).map((r) => (
                  <tr key={r.eventId}>
                    <td>
                      <strong>
                        {r.startsAt
                          ? displaySessionTime(r.startsAt, r.timezone)
                          : "Session unavailable"}
                      </strong>
                      <small>{r.program}</small>
                    </td>
                    <td>{r.venue}</td>
                    <td>
                      <Status value={r.status} />
                      {r.walkIn && <small>Walk-in</small>}
                    </td>
                    <td>
                      {r.scannedAt
                        ? displaySessionTime(r.scannedAt, r.timezone)
                        : "Not scanned"}
                    </td>
                    <td>
                      {r.distanceM == null
                        ? "—"
                        : Math.round(r.distanceM) + " m"}
                    </td>
                    <td>{r.decision}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {!history.length && !working && (
            <p>No attendance or reservations found.</p>
          )}
          <div className="pager">
            <Button
              secondary
              disabled={!offset || working}
              onClick={() => setOffset(Math.max(0, offset - 25))}
            >
              Previous history
            </Button>
            <Button
              secondary
              disabled={offset + 25 >= history.length || working}
              onClick={() => setOffset(offset + 25)}
            >
              Next history
            </Button>
            {historyCursor && (
              <Button
                secondary
                disabled={working}
                onClick={() => loadPerson(person, true)}
              >
                Load more history
              </Button>
            )}
          </div>
        </>
      )}
    </section>
  );
}
export function Attendance({ data, action, busy, api = call }) {
  const [view, setView] = useState("session"),
    [id, setId] = useState(""),
    [roster, setRoster] = useState(null),
    [filter, setFilter] = useState("all");
  const rows = (roster?.roster ?? []).filter(
    (r) =>
      filter === "all" ||
      (filter === "counted-in" && r.countedIn) ||
      (filter === "checked-in" && r.checkinStatus) ||
      (filter === "walk-ins" && r.walkIn),
  );
  const load = (x) => {
    setId(x);
    setRoster(null);
    if (x)
      action(
        async () => setRoster(await api("getEventConsole", { eventId: x })),
        "Roster loaded",
      );
  };
  return (
    <>
      <div className="quick-dates" aria-label="Attendance search mode">
        <Button
          secondary
          aria-pressed={view === "session"}
          onClick={() => setView("session")}
        >
          By session
        </Button>
        <Button
          secondary
          aria-pressed={view === "person"}
          onClick={() => setView("person")}
        >
          Search a person
        </Button>
      </div>
      {view === "person" ? (
        <PersonAttendance api={api} />
      ) : (
        <>
          <SessionPicker data={data} api={api} onSelect={load} selected={id} />
          <section className="session-attendance">
            <h2>
              Session attendance{roster?.event ? " · " + roster.event.name : ""}
            </h2>
            <div className="filters">
              <Select
                label="Show"
                value={filter}
                onChange={setFilter}
                options={["all", "counted-in", "checked-in", "walk-ins"]}
              />
              <Button secondary disabled={!id || busy} onClick={() => load(id)}>
                Refresh attendance
              </Button>
              <Button
                secondary
                disabled={!roster}
                onClick={() =>
                  downloadFile(
                    "attendance-" + id + ".csv",
                    csv(
                      rows.map((r) => ({
                        ...r,
                        name: r.firstName ?? r.name,
                        email: r.emailLower ?? r.email,
                        checkedIn: !!r.checkinStatus,
                        status: r.checkinStatus,
                      })),
                      [
                        "uid",
                        "name",
                        "email",
                        "countedIn",
                        "checkedIn",
                        "status",
                        "walkIn",
                        "scannedAt",
                        "distanceM",
                      ],
                    ),
                  )
                }
              >
                Export CSV
              </Button>
            </div>
            {roster ? (
              <>
                <p>{rows.length} people · intent and attendance are separate</p>
                {roster.limited && (
                  <div className="notice">
                    This roster reached its 500-record safety limit. Request a
                    complete server export before reporting totals.
                  </div>
                )}
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Name / email</th>
                        <th>Counted in</th>
                        <th>Check-in</th>
                        <th>Walk-in</th>
                        <th>Scanned at</th>
                        <th>Distance</th>
                        <th>Decision</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((r) => (
                        <tr key={r.uid}>
                          <td>
                            <strong>{r.firstName ?? r.name ?? "Member"}</strong>
                            <small>{r.emailLower ?? r.email ?? r.uid}</small>
                          </td>
                          <td>{r.countedIn ? "Yes" : "No"}</td>
                          <td>
                            {r.checkinStatus ? (
                              <Status value={r.checkinStatus} />
                            ) : (
                              "Not scanned"
                            )}
                          </td>
                          <td>{r.walkIn ? "Yes" : "No"}</td>
                          <td>
                            {r.scannedAt
                              ? displaySessionTime(
                                  r.scannedAt,
                                  roster.event?.timezone,
                                )
                              : "—"}
                          </td>
                          <td>
                            {r.distanceM == null
                              ? "—"
                              : Math.round(r.distanceM) + " m"}
                          </td>
                          <td>
                            {r.checkinStatus === "pending" && (
                              <div className="row-actions">
                                {["confirm", "reject"].map((decision) => (
                                  <button
                                    key={decision}
                                    disabled={busy}
                                    onClick={() =>
                                      action(async () => {
                                        await api("coachDecision", {
                                          eventId: id,
                                          uid: r.uid,
                                          decision,
                                        });
                                        setRoster(
                                          await api("getEventConsole", {
                                            eventId: id,
                                          }),
                                        );
                                      }, "Attendance updated")
                                    }
                                  >
                                    {decision === "confirm"
                                      ? "Confirm"
                                      : "Reject"}
                                  </button>
                                ))}
                              </div>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {!rows.length && <p>No attendance records in this view.</p>}
                </div>
              </>
            ) : (
              <p>Choose a session to view its intent and attendance records.</p>
            )}
          </section>
        </>
      )}
    </>
  );
}
