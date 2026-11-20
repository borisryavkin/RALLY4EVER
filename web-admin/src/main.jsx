import React, { useState, useEffect, useRef } from "react";
import { createRoot } from "react-dom/client";
import {
  GoogleAuthProvider,
  signInWithPopup,
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  signOut,
  onIdTokenChanged,
  linkWithCredential,
} from "firebase/auth";
import {
  CalendarDots,
  Stack,
  MapPin,
  Users,
  ClipboardText,
  SignOut,
  ArrowClockwise,
  Plus,
  DownloadSimple,
  UploadSimple,
  ShieldCheck,
} from "@phosphor-icons/react";
import { resolvePhoto, photoDimensions, displaySessionTime } from './helpers.mjs';
import { auth, call, photoBytes, uploadVenuePhoto, uploadPhoto } from "./firebase";
import {
  fields,
  at,
  localTime,
  zonedISO,
  filterSessions,
  csv,
  matchUploads,
  cropRect,
  sessionChanges,
} from "./helpers.mjs";
import "./style.css";
const pages = [
  ["Sessions", CalendarDots],
  ["Programs", Stack],
  ["Venues", MapPin],
  ["Users", Users],
  ["Attendance", ClipboardText],
];
const errorText = (e) =>
  e?.details?.reason
    ? `${e.message} (${e.details.reason})`
    : (e.message ?? String(e));
function Field({ label, children, ...props }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children ?? <input {...props} />}
    </label>
  );
}
function Select({ label, value, onChange, options, multiple = false }) {
  return (
    <Field label={label}>
      <select
        multiple={multiple}
        value={value}
        onChange={(e) =>
          onChange(
            multiple
              ? [...e.target.selectedOptions].map((o) => o.value)
              : e.target.value,
          )
        }
      >
        {options.map((o) => (
          <option
            key={typeof o === "string" ? o : o.value}
            value={typeof o === "string" ? o : o.value}
          >
            {typeof o === "string" ? o : o.label}
          </option>
        ))}
      </select>
    </Field>
  );
}
function Button({ children, secondary = false, ...p }) {
  return (
    <button className={secondary ? "secondary" : ""} {...p}>
      {children}
    </button>
  );
}
function Status({ value }) {
  return (
    <span className={"status " + value}>
      {value === "active" ? "published" : value}
    </span>
  );
}
function Photo({ url, alt = "" }) {
  const [src, setSrc] = useState("");
  useEffect(() => {
    let active = true,
      object;
    setSrc("");
    if (url?.startsWith("gs://"))
      photoBytes(url)
        .then((bytes) => {
          if (!active) return;
          object = URL.createObjectURL(new Blob([bytes]));
          if (active) setSrc(object);
        })
        .catch(() => {});
    else setSrc(url ?? "");
    return () => {
      active = false;
      if (object) URL.revokeObjectURL(object);
    };
  }, [url]);
  return src ? (
    <img src={src} alt={alt} className="venue-photo" />
  ) : (
    <div className="photo-empty">
      <img src="/logo.svg" alt="RALLY4EVER" className="photo-brand" />
      <span>No photo</span>
    </div>
  );
}
function Login() {
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false);
  const pending = useRef(null);
  async function run(fn) {
    setBusy(true);
    setMessage("");
    try {
      await fn();
    } catch (e) {
      setMessage(errorText(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="login">
      <div className="login-brand">
        <img src="/logo.svg" alt="Rally4Ever" />
        <span>ADMINISTRATION</span>
        <h1>
          More time
          <br />
          on the court.
        </h1>
        <p>
          Programs, people and sessions.
          <br />
          One place to keep play moving.
        </p>
        <div className="court-lines" aria-hidden="true" />
      </div>
      <section>
        <div className="eyebrow">
          <ShieldCheck size={19} /> RALLY4EVER · ADMIN ONLY
        </div>
        <h2>Welcome back</h2>
        <p>Sign in with your verified admin account.</p>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            run(async () => {
              if (
                pending.current &&
                pending.current.email !== email.trim().toLowerCase()
              ) {
                throw Error(
                  "Use the same email as the pending Google sign-in.",
                );
              }
              const result = await signInWithEmailAndPassword(
                auth,
                email,
                password,
              );
              if (
                pending.current &&
                result.user.email?.toLowerCase() === email.trim().toLowerCase()
              ) {
                await linkWithCredential(
                  result.user,
                  pending.current.credential,
                );
                pending.current = null;
              }
            });
          }}
        >
          <Field
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            autoComplete="username"
          />
          <Field
            label="Password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete="current-password"
          />
          <Button disabled={busy}>Sign in</Button>
        </form>
        <Button
          secondary
          disabled={busy}
          onClick={() =>
            run(async () => {
              try {
                await signInWithPopup(auth, new GoogleAuthProvider());
              } catch (e) {
                if (
                  e.code === "auth/account-exists-with-different-credential"
                ) {
                  pending.current = {
                    credential: GoogleAuthProvider.credentialFromError(e),
                    email: (e.customData?.email ?? "").trim().toLowerCase(),
                  };
                  setEmail(e.customData?.email ?? "");
                  throw Error(
                    "Sign in with your existing email/password to link Google to the same account.",
                  );
                }
                throw e;
              }
            })
          }
        >
          Continue with Google
        </Button>
        <button
          className="text-button"
          onClick={() =>
            run(async () => {
              if (!email) throw Error("Enter your email first");
              await sendPasswordResetEmail(auth, email);
              setMessage(
                "If an account exists, a password link has been sent.",
              );
            })
          }
        >
          Forgot / set a password
        </button>
        {message && (
          <div role="alert" className="notice">
            {message}
          </div>
        )}
        <small>
          Access requires an admin custom claim.
          <br />A Rally4Ever email address alone does not grant access.
        </small>
      </section>
    </main>
  );
}
function App() {
  const [user, setUser] = useState(undefined),
    [access, setAccess] = useState(false),
    [page, setPage] = useState("Sessions"),
    [data, setData] = useState(null),
    [users, setUsers] = useState([]),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  useEffect(
    () =>
      onIdTokenChanged(auth, async (u) => {
        setUser(u);
        setAccess(false);
        setData(null);
        if (u) {
          const t = await u.getIdTokenResult();
          setAccess(u.emailVerified && t.claims.role === "admin");
        }
      }),
    [],
  );
  async function refresh() {
    setData(await call("adminCatalogue"));
    let all = [],
      cursor;
    do {
      const u = await call("listUsers", cursor ? { cursor } : {});
      all.push(...u.users);
      cursor = u.cursor;
    } while (cursor && all.length < 1000);
    setUsers(all);
  }
  async function action(fn, message = "Saved") {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await fn();
      await refresh();
      setNotice(message);
      return true;
    } catch (e) {
      setError(errorText(e));
      if (e.code === "functions/permission-denied") {
        setData(null);
        setAccess(false);
      }
      return false;
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    if (access) action(async () => {}, "");
  }, [access]);
  if (user === undefined) return <div className="boot">Checking account…</div>;
  if (!user) return <Login />;
  if (!access)
    return (
      <main className="no-access">
        <ShieldCheck size={48} />
        <h1>No access</h1>
        <p>This account needs a verified email and an admin role.</p>
        <p>{user.email}</p>
        <Button onClick={() => signOut(auth)}>Sign out</Button>
      </main>
    );
  return (
    <div className="shell">
      <aside>
        <a href="#sessions" className="brand">
          <img src="/logo.svg" alt="Rally4Ever" />
          <span>ADMIN</span>
        </a>
        <nav>
          {pages.map(([p, Icon]) => (
            <button
              key={p}
              aria-current={page === p ? "page" : undefined}
              onClick={() => {
                setPage(p);
                setError("");
                setNotice("");
              }}
            >
              <Icon size={21} />
              {p}
            </button>
          ))}
        </nav>
        <div className="sidebar-foot">
          <ShieldCheck size={18} />
          <span>Staging · rally4ever-3adaf</span>
          <small>{user.email}</small>
          <button onClick={() => signOut(auth)}>
            <SignOut size={18} /> Sign out
          </button>
        </div>
      </aside>
      <main>
        <header>
          <div>
            <div className="eyebrow">RALLY4EVER / ADMINISTRATION</div>
            <h1>{page}</h1>
          </div>
          <Button
            secondary
            disabled={busy}
            onClick={() => action(async () => {}, "Refreshed")}
          >
            <ArrowClockwise size={17} /> Refresh
          </Button>
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
        {busy && (
          <div className="progress" role="status">
            Working…
          </div>
        )}
        {!data ? (
          error ? (
            <Empty text="Catalogue could not be loaded. Use Refresh to try again." />
          ) : (
            <div className="skeleton">Loading catalogue…</div>
          )
        ) : (
          <>
            {page === "Sessions" && (
              <Sessions data={data} users={users} action={action} busy={busy} />
            )}{" "}
            {page === "Programs" && (
              <Programs data={data} users={users} action={action} busy={busy} />
            )}{" "}
            {page === "Venues" && (
              <Venues data={data} action={action} busy={busy} />
            )}{" "}
            {page === "Users" && (
              <UserList
                users={users}
                setUsers={setUsers}
                action={action}
                busy={busy}
              />
            )}{" "}
            {page === "Attendance" && (
              <Attendance data={data} action={action} busy={busy} />
            )}
          </>
        )}
      </main>
    </div>
  );
}
function download(name, body) {
  const url = URL.createObjectURL(
    new Blob([body], { type: "text/csv;charset=utf-8" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
const zones = [
  "Australia/Sydney",
  "Australia/Melbourne",
  "Australia/Brisbane",
  "Australia/Perth",
  "Australia/Adelaide",
  "Australia/Darwin",
  "Australia/Hobart",
  "Australia/Lord_Howe",
  "Australia/Eucla",
  "Australia/Broken_Hill",
];
const blankVenue = {
  name: "",
  address: "",
  suburb: "",
  postcode: "",
  state: "NSW",
  lat: null,
  lng: null,
};
const blankSession = (formIds = []) => ({
  name: "",
  code: "s-" + crypto.randomUUID(),
  sport: "tennis",
  status: "draft",
  registrationStatus: "open",
  startsAt: new Date(Date.now() + 86400000).toISOString(),
  endsAt: new Date(Date.now() + 90000000).toISOString(),
  timezone: "Australia/Sydney",
  capacity: null,
  coachUids: [],
  coachNames: [],
  venue: { ...blankVenue },
  geofenceRadiusM: 150,
  requiredFormIds: formIds,
  notes: "",
  photoUrl: "",
  isDemo: false,
  seedBatch: "",
  programId: null,
  revision: 0,
});
function Sessions({ data, users, action, busy }) {
  const [f, setF] = useState({}),
    [edit, setEdit] = useState(null),
    [demo, setDemo] = useState(null);
  const rows = filterSessions(data.events, f).sort((a, b) =>
    a.startsAt.localeCompare(b.startsAt),
  );
  const filter = (k, v) => setF({ ...f, [k]: v });
  return (
    <>
      <div className="section-line">
        <p>
          <strong>{rows.length}</strong> sessions · {data.events.length} total
        </p>
        <div className="actions">
          <Button
            secondary
            disabled={busy}
            onClick={() => download("sessions.csv", csv(rows, fields))}
          >
            <DownloadSimple size={17} /> Export CSV
          </Button>
          <Button
            disabled={busy}
            onClick={() =>
              setEdit(blankSession(data.forms?.map((f) => f.id) ?? []))
            }
          >
            <Plus size={17} /> New session
          </Button>
        </div>
      </div>
      <div className="filters">
        <Select
          label="Sport"
          value={f.sport ?? ""}
          onChange={(v) => filter("sport", v)}
          options={[{ value: "", label: "All sports" }, "tennis", "pickleball"]}
        />
        <Select
          label="Status"
          value={f.status ?? ""}
          onChange={(v) => filter("status", v)}
          options={[
            { value: "", label: "All statuses" },
            "draft",
            "published",
            "cancelled",
            "archived",
          ]}
        />
        <Field
          label="Local date"
          type="date"
          value={f.date ?? ""}
          onChange={(e) => filter("date", e.target.value)}
        />
        <Field
          label="Suburb"
          value={f.suburb ?? ""}
          onChange={(e) => filter("suburb", e.target.value)}
        />
        <label className="check">
          <input
            type="checkbox"
            checked={!!f.demo}
            onChange={(e) => filter("demo", e.target.checked)}
          />
          Demo only
        </label>
      </div>
      {edit && !edit.id && (
        <SessionEditor
          key={edit.code}
          row={edit}
          data={data}
          users={users}
          busy={busy}
          onClose={() => setEdit(null)}
          onSave={async (changes) => {
            if (
              await action(
                () => call("adminSaveSession", { changes }),
                "Session created",
              )
            )
              setEdit(null);
          }}
        />
      )}
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th className="sticky">Session / actions</th>
              {fields.map((k) => (
                <th key={k}>{k}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <React.Fragment key={r.id}>
                <tr>
                  <td className="sticky">
                    <strong>{r.name}</strong>
                    <div className="row-actions">
                      <button
                        onClick={() => setEdit(edit?.id === r.id ? null : r)}
                      >
                        Edit
                      </button>
                      <button
                        disabled={busy}
                        onClick={() => {
                          const copy = {
                            ...r,
                            id: undefined,
                            revision: 0,
                            code: "s-" + crypto.randomUUID(),
                            status: "draft",
                          };
                          setEdit(copy);
                        }}
                      >
                        Duplicate
                      </button>
                      <button
                        disabled={busy}
                        onClick={() =>
                          action(() =>
                            call("adminSaveSession", {
                              eventId: r.id,
                              revision: r.revision ?? 0,
                              changes: {
                                status:
                                  r.status === "published"
                                    ? "draft"
                                    : "published",
                              },
                            }),
                          )
                        }
                      >
                        {r.status === "published" ? "Unpublish" : "Publish"}
                      </button>
                      <button
                        disabled={busy || r.status === "cancelled"}
                        onClick={() => {
                          if (
                            confirm(
                              `Cancel “${r.name}”? Attendance history is retained.`,
                            )
                          )
                            action(
                              () =>
                                call("adminSaveSession", {
                                  eventId: r.id,
                                  revision: r.revision ?? 0,
                                  changes: { status: "cancelled" },
                                }),
                              "Session cancelled",
                            );
                        }}
                      >
                        Cancel
                      </button>
                    </div>
                  </td>
                  {fields.map((k) => (
                    <td key={k}>
                      {k === "status" ? (
                        <Status value={r.status} />
                      ) : k === "photoUrl" ? (
                        <Photo url={resolvePhoto(r,data.venues)} alt={r.venue?.name} />
                      ) : k === "startsAt" || k === "endsAt" ? (
                        <>
                          <time>
                            {displaySessionTime(r[k], r.timezone)}
                          </time>
                          <small>{r.timezone}</small>
                        </>
                      ) : typeof at(r, k) === "boolean" ? (
                        String(at(r, k))
                      ) : Array.isArray(at(r, k)) ? (
                        at(r, k).join(", ")
                      ) : (
                        String(at(r, k) ?? "—")
                      )}
                    </td>
                  ))}
                </tr>
                {edit?.id === r.id && (
                  <tr>
                    <td colSpan={fields.length + 1}>
                      <SessionEditor
                        key={r.id + ":" + r.revision}
                        row={r}
                        data={data}
                        users={users}
                        busy={busy}
                        onClose={() => setEdit(null)}
                        onSave={async (changes) => {
                          if (
                            await action(() =>
                              call("adminSaveSession", {
                                eventId: r.id,
                                revision: r.revision ?? 0,
                                changes,
                              }),
                            )
                          )
                            setEdit(null);
                        }}
                      />
                    </td>
                  </tr>
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>
        {!rows.length && <Empty text="No sessions match these filters." />}
      </div>
      <section className="danger-zone">
        <h3>Remove demo data</h3>
        <p>
          Only catalogue records marked isDemo = true: sessions, programs and
          venues. Profiles, sign-ins and attendance records are kept. Removed
          documents are backed up; real records cannot lose a linked program or
          venue.
        </p>
        <Button
          secondary
          disabled={busy}
          onClick={() =>
            action(
              async () => setDemo(await call("adminRemoveDemo")),
              "Preview ready",
            )
          }
        >
          Preview removal
        </Button>
        {demo && (
          <div>
            <p>
              <strong>{demo.count} demo records</strong> will be removed:{" "}
              {demo.counts.events} sessions, {demo.counts.programs} programs,{" "}
              {demo.counts.venues} venues.
            </p>
            <details>
              <summary>Review every document</summary>
              <pre>{demo.paths.join("\n") || "None"}</pre>
            </details>
            <Button
              disabled={busy || demo.count === 0}
              onClick={() => {
                if (
                  confirm(
                    `Remove exactly ${demo.count} demo catalogue records? A server-side backup is retained.`,
                  )
                )
                  action(async () => {
                    await call("adminRemoveDemo", {
                      apply: true,
                      expectedPaths: demo.paths,
                    });
                    setDemo(null);
                  }, "Demo catalogue records removed with backups");
              }}
            >
              Remove {demo.count} demo records
            </Button>
          </div>
        )}
      </section>
    </>
  );
}
function Empty({ text }) {
  return (
    <div className="empty">
      <CalendarDots size={32} />
      <p>{text}</p>
    </div>
  );
}
function VenueFields({ value, onChange, venues = [] }) {
  const set = (k, v) => onChange({ ...value, [k]: v });
  return (
    <>
      <Select
        label="Use a venue"
        value={value.id ?? ""}
        onChange={(id) => {
          const v = venues.find((v) => v.id === id);
          if (v)
            onChange(
              Object.fromEntries(
                [
                  "id",
                  "code",
                  "name",
                  "address",
                  "suburb",
                  "postcode",
                  "state",
                  "lat",
                  "lng",
                  "photoUrl",
                ]
                  .filter((k) => v[k] !== undefined)
                  .map((k) => [k, v[k]]),
              ),
            );
        }}
        options={[
          { value: "", label: "Custom venue" },
          ...venues.map((v) => ({
            value: v.id,
            label: `${v.code} · ${v.name}`,
          })),
        ]}
      />
      {["name", "address", "suburb", "postcode"].map((k) => (
        <Field
          key={k}
          label={"Venue " + k}
          value={value[k] ?? ""}
          onChange={(e) => set(k, e.target.value)}
          required={["name", "suburb"].includes(k)}
        />
      ))}
      <Select
        label="State"
        value={value.state ?? ""}
        onChange={(v) => set("state", v)}
        options={[
          { value: "", label: "Choose state" },
          "ACT",
          "NSW",
          "NT",
          "QLD",
          "SA",
          "TAS",
          "VIC",
          "WA",
        ]}
      />
      {["lat", "lng"].map((k) => (
        <Field
          key={k}
          label={k === "lat" ? "Latitude" : "Longitude"}
          type="number"
          step="any"
          min={k === "lat" ? -90 : -180}
          max={k === "lat" ? 90 : 180}
          value={value[k] ?? ""}
          onChange={(e) =>
            set(k, e.target.value === "" ? null : Number(e.target.value))
          }
        />
      ))}
    </>
  );
}
function StaffSelect({ users, value, onChange }) {
  return (
    <Select
      label="Coaches (hold ⌘ / Ctrl to select several)"
      multiple
      value={value ?? []}
      onChange={onChange}
      options={users
        .filter(
          (u) =>
            ["coach", "admin"].includes(u.role) &&
            !u.mergedInto &&
            (u.role === "admin" || u.coachEnabled !== false),
        )
        .map((u) => ({
          value: u.uid,
          label: `${u.firstName || "Staff"} · ${u.email}`,
        }))}
    />
  );
}
function SessionEditor({ row, data, users, busy, onSave, onClose }) {
  const [v, setV] = useState({ ...blankSession(), ...row }),
    [err, setErr] = useState(""), [photoBusy,setPhotoBusy]=useState(false);
  const set = (k, val) => setV({ ...v, [k]: val });
  async function submit(e) {
    e.preventDefault();
    setErr("");
    try {
      if (new Date(v.endsAt) <= new Date(v.startsAt))
        throw Error("End must be after start");
      const changes = sessionChanges(v);
      if (row.id) {
        for (const k of Object.keys(changes))
          if (JSON.stringify(changes[k]) === JSON.stringify(row[k]))
            delete changes[k];
      }
      await onSave(changes);
    } catch (e) {
      setErr(errorText(e));
    }
  }
  return (
    <form className="editor" onSubmit={submit}>
      <div className="section-line">
        <h2>{row.id ? "Edit session" : "Create session"}</h2>
        <button type="button" className="text-button" onClick={onClose}>
          Close
        </button>
      </div>
      <div className="form-grid">
        <Select
          label="Program"
          value={v.programId ?? ""}
          onChange={(id) => {
            const p = data.programs.find((p) => p.id === id);
            if (p)
              setV({
                ...v,
                ...sessionChanges(p),
                status: "draft",
                programId: id,
                code: v.code,
                startsAt: v.startsAt,
                endsAt: v.endsAt,
              });
            else set("programId", null);
          }}
          options={[
            { value: "", label: "Standalone session" },
            ...data.programs.map((p) => ({
              value: p.id,
              label:
                p.name +
                " (" +
                (p.status === "active" ? "published" : p.status) +
                ")",
            })),
          ]}
        />
        <Field
          label="Name"
          value={v.name}
          onChange={(e) => set("name", e.target.value)}
          required
        />
        <Field
          label="Code"
          value={v.code}
          onChange={(e) => set("code", e.target.value)}
          pattern="[A-Za-z0-9-]+"
          required
        />
        <Select
          label="Sport"
          value={v.sport}
          onChange={(x) => set("sport", x)}
          options={["tennis", "pickleball"]}
        />
        <Select
          label="Status"
          value={v.status}
          onChange={(x) => set("status", x)}
          options={["draft", "published", "cancelled", "archived"]}
        />
        <Select
          label="Registration"
          value={v.registrationStatus}
          onChange={(x) => set("registrationStatus", x)}
          options={["open", "full", "closed"]}
        />
        <Select
          label="Timezone (IANA)"
          value={v.timezone}
          onChange={(x) => set("timezone", x)}
          options={[...new Set([v.timezone, ...zones])]}
        />
        {["startsAt", "endsAt"].map((k) => (
          <Field
            key={k}
            label={
              k === "startsAt" ? "Starts (venue time)" : "Ends (venue time)"
            }
          >
            <input
              type="datetime-local"
              required
              value={localTime(v[k], v.timezone)}
              onChange={(e) => {
                try {
                  set(k, zonedISO(e.target.value, v.timezone));
                  setErr("");
                } catch (err) {
                  setErr(err.message);
                }
              }}
            />
          </Field>
        ))}
        <Field
          label="Capacity (blank = unlimited)"
          type="number"
          min="1"
          max="5000"
          value={v.capacity ?? ""}
          onChange={(e) =>
            set(
              "capacity",
              e.target.value === "" ? null : Number(e.target.value),
            )
          }
        />
        <Field
          label="Booked count (derived)"
          value={row.bookedCount ?? 0}
          readOnly
        />
        <Field
          label="Geofence radius (m)"
          type="number"
          min="10"
          max="2000"
          value={v.geofenceRadiusM}
          onChange={(e) => set("geofenceRadiusM", Number(e.target.value))}
        />
        <StaffSelect
          users={users}
          value={v.coachUids}
          onChange={(x) => set("coachUids", x)}
        />
        <Field
          label={
            "Required form IDs · available: " +
            (data.forms?.map((f) => f.id).join(", ") || "none configured")
          }
          value={v.requiredFormIds.join(", ")}
          onChange={(e) =>
            set(
              "requiredFormIds",
              e.target.value
                .split(",")
                .map((s) => s.trim())
                .filter(Boolean),
            )
          }
        />
        <VenueFields
          value={v.venue}
          onChange={(venue) =>
            setV({ ...v, venue })
          }
          venues={data.venues}
        />
        <Field
          label="Photo URL (or upload in Venues)"
          value={v.photoUrl}
          onChange={(e) => set("photoUrl", e.target.value)}
        />
        <Field
          label="Seed batch"
          value={v.seedBatch}
          onChange={(e) => set("seedBatch", e.target.value)}
        />
        <label className="check">
          <input
            type="checkbox"
            checked={v.isDemo}
            onChange={(e) => set("isDemo", e.target.checked)}
          />
          Demo session
        </label>
        <Field label="Notes">
          <textarea
            value={v.notes}
            maxLength={4000}
            onChange={(e) => set("notes", e.target.value)}
          />
        </Field>
      </div>
      <p className="muted">
        Revision {row.revision ?? 0}. Changes record your account, server time
        and before/after values automatically. Original scan context is
        protected.
      </p>
      {err && (
        <p role="alert" className="notice error">
          {err}
        </p>
      )}
      <Button disabled={busy}>Save session</Button>
    </form>
  );
}
const programFields = [
  "name",
  "sport",
  "status",
  "venue",
  "timezone",
  "scheduleText",
  "coachUids",
  "coachNames",
  "notes",
  "photoUrl",
  "capacity",
  "registrationStatus",
];
const programInput = (p) =>
  Object.fromEntries(
    programFields.map((k) => [
      k,
      p[k] ??
        {
          coachUids: [],
          coachNames: [],
          capacity: null,
          photoUrl: "",
          notes: "",
          registrationStatus: "open",
        }[k] ??
        "",
    ]),
  );
function Programs({ data, users, action, busy }) {
  const [edit, setEdit] = useState(null),
    [generate, setGenerate] = useState(null),
    [search, setSearch] = useState(""),
    [status, setStatus] = useState("");
  const rows = data.programs.filter(
    (p) =>
      (!status || p.status === status) &&
      p.name.toLowerCase().includes(search.toLowerCase()),
  );
  async function save(p, patch = {}) {
    return action(() =>
      call("saveProgram", {
        programId: p.id,
        revision: p.revision,
        program: programInput({ ...p, ...patch }),
      }),
    );
  }
  return (
    <>
      <div className="section-line">
        <p>{rows.length} programs</p>
        <Button
          onClick={() =>
            setEdit({
              ...programInput({
                ...blankSession(),
                status: "draft",
                scheduleText: "",
              }),
              id: undefined,
            })
          }
        >
          <Plus size={17} /> New program
        </Button>
      </div>
      <div className="filters">
        <Field
          label="Search programs"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <Select
          label="Status"
          value={status}
          onChange={setStatus}
          options={[
            { value: "", label: "All statuses" },
            { value: "active", label: "published" },
            "draft",
            "archived",
          ]}
        />
      </div>
      {edit && (
        <ProgramEditor
          key={edit.id ?? "new"}
          row={edit}
          data={data}
          users={users}
          busy={busy}
          onClose={() => setEdit(null)}
          onSave={async (p) => {
            if (await save(p)) setEdit(null);
          }}
        />
      )}
      {generate && (
        <GenerateSessions
          key={generate.id}
          program={generate}
          events={data.events}
          formIds={data.forms?.map((f) => f.id) ?? []}
          busy={busy}
          action={action}
          onClose={() => setGenerate(null)}
        />
      )}
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Program / venue</th>
              <th>Sport</th>
              <th>Status</th>
              <th>Schedule</th>
              <th>Coaches</th>
              <th>Revision</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.id}>
                <td>
                  <Photo url={resolvePhoto(p,data.venues)} alt={p.venue?.name} />
                  <strong>{p.name}</strong>
                  <small>
                    {p.venue?.name} · {p.venue?.suburb}
                  </small>
                </td>
                <td>{p.sport}</td>
                <td>
                  <Status value={p.status} />
                </td>
                <td>{p.scheduleText}</td>
                <td>{p.coachNames?.join(", ")}</td>
                <td>{p.revision ?? 0}</td>
                <td className="row-actions">
                  <button onClick={() => setEdit(p)}>Edit</button>
                  <button
                    disabled={busy}
                    onClick={() =>
                      save(p, {
                        status: p.status === "active" ? "draft" : "active",
                      })
                    }
                  >
                    {p.status === "active" ? "Unpublish" : "Publish"}
                  </button>
                  <button
                    disabled={busy || p.status === "archived"}
                    onClick={() => save(p, { status: "archived" })}
                  >
                    Archive
                  </button>
                  <button
                    disabled={p.status !== "active"}
                    onClick={() => setGenerate(p)}
                  >
                    Generate sessions
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.length && <Empty text="No matching programs." />}
      </div>
    </>
  );
}
function ProgramEditor({ row, data, users, busy, onSave, onClose }) {
  const [v, setV] = useState(row),
    set = (k, x) => setV({ ...v, [k]: x });
  return (
    <form
      className="editor"
      onSubmit={(e) => {
        e.preventDefault();
        onSave(v);
      }}
    >
      <div className="section-line">
        <h2>{row.id ? "Edit program" : "Create program"}</h2>
        <button type="button" className="text-button" onClick={onClose}>
          Close
        </button>
      </div>
      <div className="form-grid">
        <Field
          label="Name"
          value={v.name}
          onChange={(e) => set("name", e.target.value)}
          required
        />
        <Select
          label="Sport"
          value={v.sport}
          onChange={(x) => set("sport", x)}
          options={["tennis", "pickleball"]}
        />
        <Select
          label="Status"
          value={v.status}
          onChange={(x) => set("status", x)}
          options={[
            "draft",
            { value: "active", label: "published" },
            "archived",
          ]}
        />
        <Field
          label="Schedule text"
          value={v.scheduleText}
          onChange={(e) => set("scheduleText", e.target.value)}
          required
        />
        <Select
          label="Timezone"
          value={v.timezone}
          onChange={(x) => set("timezone", x)}
          options={[...new Set([v.timezone, ...zones])]}
        />
        <Field
          label="Capacity (blank = unlimited)"
          type="number"
          min="1"
          max="5000"
          value={v.capacity ?? ""}
          onChange={(e) =>
            set("capacity", e.target.value ? Number(e.target.value) : null)
          }
        />
        <Select
          label="Registration"
          value={v.registrationStatus}
          onChange={(x) => set("registrationStatus", x)}
          options={["open", "full", "closed"]}
        />
        <StaffSelect
          users={users}
          value={v.coachUids}
          onChange={(uids) =>
            setV({
              ...v,
              coachUids: uids,
              coachNames: uids.map(
                (id) => users.find((u) => u.uid === id)?.firstName ?? "Coach",
              ),
            })
          }
        />
        <VenueFields
          value={v.venue}
          onChange={(venue) =>
            setV({ ...v, venue })
          }
          venues={data.venues}
        />
        <Field
          label="Photo URL"
          value={v.photoUrl}
          onChange={(e) => set("photoUrl", e.target.value)}
        />
        <Field label="Notes">
          <textarea
            value={v.notes}
            onChange={(e) => set("notes", e.target.value)}
          />
        </Field>
      </div>
      <Button disabled={busy}>Save program</Button>
    </form>
  );
}
function GenerateSessions({ program, events, formIds, action, busy, onClose }) {
  const [start, setStart] = useState(""),
    [end, setEnd] = useState(""),
    [time, setTime] = useState("18:30"),
    [duration, setDuration] = useState(60),
    [weekday, setWeekday] = useState("2"),
    [preview, setPreview] = useState([]),
    [err, setErr] = useState("");
  function make(e) {
    e.preventDefault();
    try {
      if (!start || !end || end < start)
        throw Error("Choose a valid date range");
      const rows = [];
      for (
        let d = new Date(start + "T12:00Z");
        d <= new Date(end + "T12:00Z");
        d.setUTCDate(d.getUTCDate() + 1)
      ) {
        if (rows.length > 52)
          throw Error("Generate at most 52 sessions per preview");
        if (d.getUTCDay() !== Number(weekday)) continue;
        const startsAt = zonedISO(
          d.toISOString().slice(0, 10) + "T" + time,
          program.timezone,
        );
        if (new Date(startsAt) <= new Date()) continue;
        rows.push({
          startsAt,
          endsAt: new Date(
            Date.parse(startsAt) + duration * 60000,
          ).toISOString(),
          exists: events.some(
            (r) =>
              r.programId === program.id &&
              Date.parse(r.startsAt) === Date.parse(startsAt),
          ),
        });
      }
      setPreview(rows);
      setErr("");
    } catch (e) {
      setErr(e.message);
    }
  }
  return (
    <form className="editor" onSubmit={make}>
      <div className="section-line">
        <h2>Generate · {program.name}</h2>
        <button type="button" className="text-button" onClick={onClose}>
          Close
        </button>
      </div>
      <div className="form-grid">
        <Field
          label="From"
          type="date"
          required
          value={start}
          onChange={(e) => setStart(e.target.value)}
        />
        <Field
          label="Through"
          type="date"
          required
          value={end}
          onChange={(e) => setEnd(e.target.value)}
        />
        <Select
          label="Weekday"
          value={weekday}
          onChange={setWeekday}
          options={[
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
          ].map((label, i) => ({ value: String(i), label }))}
        />
        <Field
          label={"Start · " + program.timezone}
          type="time"
          value={time}
          onChange={(e) => setTime(e.target.value)}
          required
        />
        <Field
          label="Duration (minutes)"
          type="number"
          min="15"
          max="1440"
          value={duration}
          onChange={(e) => setDuration(Number(e.target.value))}
        />
      </div>
      <Button secondary>Preview dates</Button>
      {err && <p role="alert">{err}</p>}
      {preview.length > 0 && (
        <>
          <ul>
            {preview.map((r) => (
              <li key={r.startsAt}>
                {localTime(r.startsAt, program.timezone).replace("T", " ")}{" "}
                {r.exists ? "— already exists" : ""}
              </li>
            ))}
          </ul>
          <Button
            type="button"
            disabled={busy || preview.every((r) => r.exists)}
            onClick={() =>
              action(async () => {
                for (const r of preview.filter((r) => !r.exists)) {
                  await call("adminSaveSession", {
                    eventId: "g-" + program.id + "-" + Date.parse(r.startsAt),
                    changes: sessionChanges({
                      ...blankSession(),
                      ...sessionChanges(program),
                      code: "g-" + program.id + "-" + Date.parse(r.startsAt),
                      programId: program.id,
                      status: "published",
                      startsAt: r.startsAt,
                      endsAt: r.endsAt,
                      requiredFormIds: formIds,
                    }),
                  });
                  r.exists = true;
                }
                setPreview([...preview]);
              }, "Sessions generated. Existing dates were skipped.")
            }
          >
            Create {preview.filter((r) => !r.exists).length} published sessions
          </Button>
        </>
      )}
    </form>
  );
}
async function loadImage(file) {
  if (
    !/^image\/(jpeg|png|webp)$/.test(file.type) ||
    file.size > 20 * 1024 * 1024
  )
    throw Error("Use a JPEG, PNG or WebP under 20 MB");
  const bitmap = await createImageBitmap(file);
  if (bitmap.width * bitmap.height > 50000000) {
    bitmap.close();
    throw Error("Source image is too large (maximum 50 megapixels)");
  }
  return bitmap;
}
async function compressCrop(file, settings = {}) {
  const image = await loadImage(file);
  try {
    const c = cropRect(
        image.width,
        image.height,
        settings.zoom ?? 1,
        settings.x ?? 0.5,
        settings.y ?? 0.5,
      ),
      canvas = document.createElement("canvas");
    const dimensions = photoDimensions(c.w,c.h);
    canvas.width = dimensions.width;
    canvas.height = dimensions.height;
    const ctx = canvas.getContext("2d");
    ctx.drawImage(image, c.x, c.y, c.w, c.h, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", 0.8),
    );
    if (!blob || blob.size > 5 * 1024 * 1024)
      throw Error("Compressed image exceeds the upload limit");
    return blob;
  } finally {
    image.close();
  }
}
function RecordPhotoEditor({kind,record,venues=[],busy,onSaved,onBusy=()=>{}}) {
 const [file,setFile]=useState(null),[blob,setBlob]=useState(null),[working,setWorking]=useState(false),[progress,setProgress]=useState(0),[error,setError]=useState('');const picker=useRef(null);
 async function save(mode){setWorking(true);onBusy(true);setError('');setProgress(0);try{const photoUrl=mode==='override'?await uploadPhoto(kind,record.id,blob,setProgress):'';const result=await call('adminSetPhoto',{kind,id:record.id,revision:record.revision??0,photoUrl,mode});onSaved({photoUrl,photoMode:mode,revision:result.revision??(record.revision??0)+1});setFile(null);setBlob(null);}catch(e){setError(errorText(e));}finally{setWorking(false);onBusy(false);}}
 return <section className="editor"><h3>Photo</h3><div className="dropzone" onDragOver={e=>e.preventDefault()} onDrop={e=>{e.preventDefault();if(!working)setFile(e.dataTransfer.files[0]);}}><Photo url={resolvePhoto(record,venues)} alt={record.name}/><Button type="button" secondary disabled={working||busy} onClick={()=>picker.current.click()}>Change photo</Button><input type="file" ref={picker} hidden accept="image/jpeg,image/png,image/webp" onChange={e=>setFile(e.target.files[0])}/><p>Drop a photo here or choose a file.</p></div>{file&&<CropPhoto file={file} onReady={setBlob}/>}<div className="actions">{file&&<Button type="button" disabled={!blob||working||busy} onClick={()=>save('override')}>Replace / Upload photo</Button>}{kind==='session'&&<Button type="button" secondary disabled={working||busy} onClick={()=>save('venue')}>Use venue photo</Button>}<Button type="button" secondary disabled={working||busy} onClick={()=>save('none')}>Remove photo</Button></div>{working&&<><progress max="1" value={progress}/><p>{progress<1?'Uploading '+Math.round(progress*100)+'%':'Saving photo…'}</p></>}{error&&<p role="alert">{error}</p>}</section>;
}
function CropPhoto({ file, onReady }) {
  const [zoom, setZoom] = useState(1),
    [x, setX] = useState(0.5),
    [y, setY] = useState(0.5),
    [url, setUrl] = useState(""),
    [error, setError] = useState("");
  useEffect(() => {
    let active = true,
      object;
    onReady(null);
    compressCrop(file, { zoom, x, y })
      .then((blob) => {
        if (!active) return;
        object = URL.createObjectURL(blob);
        if (active) {
          setUrl(object);
          onReady(blob);
          setError("");
        }
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
      if (object) URL.revokeObjectURL(object);
    };
  }, [file, zoom, x, y]);
  return (
    <div className="crop">
      <img src={url || undefined} alt="16:9 cropped preview" />
      <div className="form-grid">
        {[
          ["Zoom", zoom, setZoom, 1, 3],
          ["Horizontal position", x, setX, 0, 1],
          ["Vertical position", y, setY, 0, 1],
        ].map(([label, val, set, min, max]) => (
          <Field
            key={label}
            label={label}
            type="range"
            min={min}
            max={max}
            step=".01"
            value={val}
            onChange={(e) => set(Number(e.target.value))}
          />
        ))}
      </div>
      <small>1600 × 900 · JPEG · compressed before upload</small>
      {error && <p role="alert">{error}</p>}
    </div>
  );
}
function Venues({ data, action, busy }) {
  const [edit, setEdit] = useState(null),
    [search, setSearch] = useState(""),
    [batch, setBatch] = useState([]);
  const input = useRef(null);
  const rows = data.venues.filter((v) =>
    `${v.name} ${v.code} ${v.suburb}`
      .toLowerCase()
      .includes(search.toLowerCase()),
  );
  async function preview(files) {
    try {
      const matched = matchUploads([...files], data.venues);
      for (const item of matched) {
        if (item.error) continue;
        item.blob = await compressCrop(item.file);
        item.preview = URL.createObjectURL(item.blob);
      }
      setBatch((old) => {
        old.forEach((b) => b.preview && URL.revokeObjectURL(b.preview));
        return matched;
      });
    } catch (e) {
      action(() => Promise.reject(e));
    }
  }
  useEffect(
    () => () => {
      batch.forEach((b) => b.preview && URL.revokeObjectURL(b.preview));
    },
    [batch],
  );
  return (
    <>
      <div className="section-line">
        <p>{rows.length} venues · including legacy program/session venues</p>
        <Button
          onClick={() =>
            setEdit({
              ...blankVenue,
              code: "",
              photoUrl: "",
              revision: 0,
              isDemo: false,
            })
          }
        >
          <Plus size={17} /> New venue
        </Button>
      </div>
      <Field
        label="Search venue, suburb or code"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      {edit && (
        <VenueEditor
          key={edit.id ?? "new"}
          row={edit}
          action={action}
          busy={busy}
          onClose={() => setEdit(null)}
        />
      )}
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Photo</th>
              <th>Code / venue</th>
              <th>Address</th>
              <th>Coordinates</th>
              <th>Revision</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((v) => (
              <tr key={v.id}>
                <td>
                  <Photo url={v.photoUrl} alt={v.name} />
                </td>
                <td>
                  <strong>{v.code}</strong>
                  <small>{v.name}</small>
                </td>
                <td>
                  {v.address}
                  <small>
                    {v.suburb} {v.state} {v.postcode}
                  </small>
                </td>
                <td>
                  {v.lat ?? "Not set"}, {v.lng ?? "Not set"}
                </td>
                <td>{v.revision ?? 0}</td>
                <td>
                  <Button secondary onClick={() => setEdit(v)}>
                    Edit / upload photo
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <section className="editor">
        <h2>Bulk venue photos</h2>
        <p>
          Name each file with its venue code, for example{" "}
          <code>BONDI-01.jpg</code>. Images are centre-cropped to 16:9 and
          compressed. Review every match before saving; use the venue editor for
          a custom crop.
        </p>
        <div
          className="dropzone"
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            preview(e.dataTransfer.files);
          }}
        >
          <UploadSimple size={28} />
          <p>Drop venue photos here</p>
          <Button
            secondary
            disabled={busy}
            onClick={() => input.current.click()}
          >
            Choose files
          </Button>
          <input
            ref={input}
            type="file"
            hidden
            multiple
            accept="image/jpeg,image/png,image/webp"
            onChange={(e) => preview(e.target.files)}
          />
        </div>
        {batch.length > 0 && (
          <>
            <div className="bulk-preview">
              {batch.map((b, i) => (
                <div key={i}>
                  {b.preview && (
                    <img src={b.preview} alt="Cropped upload preview" />
                  )}
                  <strong>{b.file.name}</strong>
                  <p>{b.error || b.venue.name}</p>
                  <small>
                    {b.blob
                      ? Math.ceil(b.blob.size / 1024) + " KB · ready to upload"
                      : ""}
                  </small>
                </div>
              ))}
            </div>
            <Button
              disabled={busy || batch.some((b) => b.error || !b.blob)}
              onClick={() => {
                if (
                  confirm(
                    `Upload and apply ${batch.length} venue photos? Linked session/program photos will also update.`,
                  )
                )
                  action(async () => {
                    for (const b of batch) {
                      const photoUrl = await uploadVenuePhoto(
                        b.venue.id,
                        b.blob,
                      );
                      await call("adminSaveVenue", {
                        venueId: b.venue.id,
                        revision: b.venue.revision ?? 0,
                        venue: venueInput({ ...b.venue, photoUrl }),
                      });
                    }
                    setBatch([]);
                  }, "Venue photos uploaded and linked records updated");
              }}
            >
              Upload {batch.length} matched photos
            </Button>
          </>
        )}
      </section>
    </>
  );
}
const venueInput = (v) =>
  Object.fromEntries(
    [
      "name",
      "code",
      "address",
      "suburb",
      "postcode",
      "state",
      "lat",
      "lng",
      "photoUrl",
      "isDemo",
    ].map((k) => [k, v[k] ?? { isDemo: false, lat: null, lng: null }[k] ?? ""]),
  );
function VenueEditor({ row, action, busy, onClose }) {
  const [v, setV] = useState(row),
    [file, setFile] = useState(null),
    [blob, setBlob] = useState(null), [progress,setProgress] = useState(null);
  const picker = useRef(null);
  return (
    <form
      className="editor"
      onSubmit={(e) => {
        e.preventDefault();
        action(async () => {
          const id = v.id ?? crypto.randomUUID();
          let photoUrl = v.photoUrl ?? "";
          if (blob) photoUrl = await uploadVenuePhoto(id, blob,setProgress);
          await call("adminSaveVenue", {
            venueId: id,
            revision: v.revision ?? 0,
            venue: venueInput({ ...v, photoUrl }),
          });
          onClose();
        }, "Venue saved; linked photos updated");
      }}
    >
      <div className="section-line">
        <h2>{v.id ? "Edit venue" : "Create venue"}</h2>
        <button type="button" className="text-button" onClick={onClose}>
          Close
        </button>
      </div>
      <div className="form-grid">
        <Field
          label="Venue code (unique; used for bulk photos)"
          value={v.code}
          pattern="[A-Za-z0-9-]+"
          required
          onChange={(e) => setV({ ...v, code: e.target.value })}
        />
        <VenueFields value={v} onChange={(x) => setV({ ...v, ...x })} />
        <label className="check">
          <input
            type="checkbox"
            checked={!!v.isDemo}
            onChange={(e) => setV({ ...v, isDemo: e.target.checked })}
          />
          Demo / test venue
        </label>
      </div>
      <div
        className="dropzone"
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => {
          e.preventDefault();
          setFile(e.dataTransfer.files[0]);
        }}
      >
        <Photo url={v.photoUrl} alt={v.name} />
        <Button type="button" secondary onClick={() => picker.current.click()}>
          <UploadSimple size={17} /> Change photo / Replace
        </Button>
        <p>
          Or drop a photo here. JPEG, PNG or WebP; up to 20 MB before
          compression.
        </p>
        <input
          ref={picker}
          hidden
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(e) => setFile(e.target.files[0])}
        />
      </div>
      {file && <CropPhoto file={file} onReady={setBlob} />}
      {progress!==null && <progress value={progress} max="1" aria-label="Photo upload progress" />}
      <Button type="button" secondary disabled={busy} onClick={()=>{setFile(null);setBlob(null);setV({...v,photoUrl:''});}}>Remove photo</Button>
      <p className="muted">
        Revision {v.revision ?? 0}. Photos update linked programs and sessions.
        Started sessions keep their original coordinates.
      </p>
      <Button disabled={busy || (!!file && !blob)}>
        Save venue{blob ? " and photo" : ""}
      </Button>
    </form>
  );
}
function UserList({ users, setUsers, action, busy }) {
  const [query, setQuery] = useState(""),
    [cursor, setCursor] = useState(null),
    [result, setResult] = useState(null);
  const rows = result ?? users;
  async function search(next = false) {
    const r = await call("listUsers", {
      query,
      ...(next && cursor ? { cursor } : {}),
    });
    setResult(next ? [...rows, ...r.users] : r.users);
    setCursor(r.cursor);
  }
  return (
    <>
      <form
        className="filters"
        onSubmit={(e) => {
          e.preventDefault();
          action(() => search(), "Search complete");
        }}
      >
        <Field
          label="Search by email prefix"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <Button disabled={busy}>Search</Button>
      </form>
      <p className="muted">
        Role changes are audited and require a verified account. A domain alone
        grants no access. You cannot change your own role or remove the final
        admin.
      </p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Name / email</th>
              <th>Current role</th>
              <th>Set role</th>
              <th>Profile</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((u) => (
              <UserRow
                key={u.uid + u.role}
                user={u}
                busy={busy}
                onSave={async (role) => {
                  if (confirm(`Set ${u.email} to ${role}?`))
                    await action(async () => {
                      await call("setUserRole", {
                        uid: u.uid,
                        role,
                        reason: "Role changed in web admin",
                      });
                      await search();
                    }, "Role updated; user must refresh their sign-in token.");
                }}
              />
            ))}
          </tbody>
        </table>
      </div>
      {cursor && (
        <Button
          secondary
          disabled={busy}
          onClick={() => action(() => search(true), "More users loaded")}
        >
          Load more
        </Button>
      )}
      <p>Assign coaches under Sessions → Edit → Coaches.</p>
    </>
  );
}
function UserRow({ user: u, busy, onSave }) {
  const [role, setRole] = useState(u.role);
  return (
    <tr>
      <td>
        <strong>{u.firstName || "Member"}</strong>
        <small>{u.email}</small>
      </td>
      <td>
        <Status value={u.role} />
      </td>
      <td>
        <div className="actions">
          <select
            aria-label={"Role for " + u.email}
            value={role}
            onChange={(e) => setRole(e.target.value)}
          >
            <option>participant</option>
            <option>coach</option>
            <option>admin</option>
          </select>
          <Button
            secondary
            disabled={busy || role === u.role || !!u.mergedInto}
            onClick={() => onSave(role)}
          >
            Apply role
          </Button>
        </div>
      </td>
      <td>{u.mergedInto ? "Merged into " + u.mergedInto : u.uid}</td>
    </tr>
  );
}
function Attendance({ data, action, busy }) {
  const [id, setId] = useState(""),
    [roster, setRoster] = useState(null),
    [filter, setFilter] = useState("all");
  const rows = (roster?.roster ?? []).filter(
    (r) =>
      filter === "all" ||
      (filter === "counted-in" && r.countedIn) ||
      (filter === "checked-in" && r.checkinStatus) ||
      (filter === "walk-ins" && r.walkIn),
  );
  return (
    <>
      <div className="filters">
        <Select
          label="Session"
          value={id}
          onChange={(x) => {
            setId(x);
            setRoster(null);
            if (x)
              action(
                async () =>
                  setRoster(await call("getEventConsole", { eventId: x })),
                "Roster loaded",
              );
          }}
          options={[
            { value: "", label: "Choose a session" },
            ...data.events.map((e) => ({
              value: e.id,
              label:
                e.name +
                " · " +
                localTime(e.startsAt, e.timezone).replace("T", " "),
            })),
          ]}
        />
        <Select
          label="Show"
          value={filter}
          onChange={setFilter}
          options={["all", "counted-in", "checked-in", "walk-ins"]}
        />
        <Button
          secondary
          disabled={!roster}
          onClick={() =>
            download(
              "attendance-" + id + ".csv",
              csv(
                rows.map((r) => ({
                  uid: r.uid,
                  name: r.firstName ?? r.name,
                  email: r.emailLower ?? r.email,
                  countedIn: r.countedIn,
                  checkedIn: !!r.checkinStatus,
                  status: r.checkinStatus,
                  walkIn: r.walkIn,
                  scannedAt: r.scannedAt,
                  distanceM: r.distanceM,
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
          <DownloadSimple size={17} /> Export CSV
        </Button>
      </div>
      {roster ? (
        <>
          <p>{rows.length} people · intent and attendance are separate</p>
          {roster.limited && (
            <div className="notice">
              This large roster reached the 500-record safety limit. Request a
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
                        ? new Date(r.scannedAt).toLocaleString("en-AU", {
                            timeZone:
                              roster.event?.timezone ?? "Australia/Sydney",
                          })
                        : "—"}
                    </td>
                    <td>
                      {r.distanceM != null
                        ? Math.round(r.distanceM) + " m"
                        : "—"}
                    </td>
                    <td>
                      {r.checkinStatus === "pending" && (
                        <div className="row-actions">
                          {["confirmed", "rejected"].map((status) => (
                            <button
                              key={status}
                              disabled={busy}
                              onClick={() =>
                                action(async () => {
                                  await call("coachDecision", {
                                    eventId: id,
                                    uid: r.uid,
                                    decision:
                                      status === "confirmed"
                                        ? "confirm"
                                        : "reject",
                                  });
                                  setRoster(
                                    await call("getEventConsole", {
                                      eventId: id,
                                    }),
                                  );
                                }, "Attendance " + status)
                              }
                            >
                              {status === "confirmed" ? "Confirm" : "Reject"}
                            </button>
                          ))}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!rows.length && (
              <Empty text="No attendance records in this view." />
            )}
          </div>
        </>
      ) : (
        <Empty text="Choose a session to view its intent and attendance records." />
      )}
    </>
  );
}
createRoot(document.getElementById("root")).render(<App />);
