import React, { useEffect, useState, useRef } from "react";
import {
  readLink,
  friendlyError,
  timestamp,
  versionMap,
  anonymousTokenFor,
} from "./links.mjs";
export function CheckIn({ call }) {
  const submitting = useRef(false);
  const [countOnly, setCountOnly] = useState(false);
  const [link, setLink] = useState(null),
    [session, setSession] = useState(null),
    [name, setName] = useState(""),
    [email, setEmail] = useState(""),
    [accepted, setAccepted] = useState({}),
    [position, setPosition] = useState(null),
    [state, setState] = useState("loading"),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    let active = true;
    try {
      const parsed = readLink(location.href);
      setLink(parsed);
      call("getNoAppForms", {
        eventCode: parsed.eventCode,
        secret: parsed.secret,
      })
        .then((s) => {
          if (active) {
            setSession(s);
            setState(parsed.requestId && parsed.oobCode ? "verify" : "form");
          }
        })
        .catch((e) => {
          if (active) {
            setError(friendlyError(e));
            setState("failed");
          }
        });
    } catch (e) {
      setError(e.message);
      setState("failed");
    }
    return () => {
      active = false;
    };
  }, []);
  async function run(fn) {
    if (submitting.current) return;
    submitting.current = true;
    setBusy(true);
    setError("");
    try {
      await fn();
    } catch (e) {
      if (e.details?.reason === "already-checked-in") {
        setState("duplicate");
      } else setError(friendlyError(e));
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }
  async function locate() {
    if (!navigator.geolocation)
      throw Error(
        "Location is unavailable in this browser. Ask the coach to add you.",
      );
    const p = await new Promise((resolve, reject) =>
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true,
        timeout: 20000,
        maximumAge: 0,
      }),
    );
    const value = { lat: p.coords.latitude, lng: p.coords.longitude };
    setPosition(value);
    return value;
  }
  async function complete(requestId, oobCode, coordinates) {
    await call("completeNoAppCheckIn", {
      requestId,
      secret: link.secret,
      ...(oobCode ? { oobCode } : {}),
      ...coordinates,
    });
    setState("pending");
    history.replaceState(null, "", location.pathname);
  }
  async function submit(e) {
    e.preventDefault();
    await run(async () => {
      if (session.forms.some((f) => f.required && !accepted[f.id]))
        throw Error("Read and accept every required agreement.");
      const coordinates = await locate();
      const result = await call("beginNoAppCheckIn", {
        eventCode: link.eventCode,
        secret: link.secret,
        ...(countOnly
          ? {
              countOnly: true,
              anonymousToken: anonymousTokenFor(session.eventId),
            }
          : { firstName: name.trim(), email: email.trim() }),
        ...coordinates,
        signedVersions: versionMap(session.forms.filter((f) => accepted[f.id])),
        deferCompletion: true,
      });
      if (result.status === "pending" || result.status === "confirmed") {
        setState("pending");
        history.replaceState(null, "", location.pathname);
      } else if (result.status === "verification-required") setState("email");
      else await complete(result.requestId, null, coordinates);
    });
  }
  return (
    <main>
      <header>
        <img src="/logo.svg" alt="Rally4Ever" />
        <strong>RALLY4EVER</strong>
        <span>COURT CHECK-IN</span>
      </header>
      {state === "loading" ? (
        <section aria-live="polite">
          <p>Finding your session…</p>
        </section>
      ) : (
        <>
          {session && (
            <section className="session">
              <span className="eyebrow">YOUR SESSION</span>
              <h1>{session.name}</h1>
              <p>
                {session.venue.name} · {session.venue.suburb}
              </p>
              <p>{timestamp(session.startsAt, session.timezone)}</p>
            </section>
          )}
          {state === "form" && (
            <form onSubmit={submit}>
              <h2>Check in with your coach</h2>
              <p>
                No app account needed. Your coach confirms attendance in person.
              </p>
              {!countOnly ? (
                <>
                  <button
                    type="button"
                    className="secondary"
                    onClick={() => setCountOnly(true)}
                  >
                    Skip details — count me as +1
                  </button>
                  <p className="small">
                    No name, email or account. Read the required agreements,
                    then ask your coach to confirm your +1.
                  </p>
                  <label>
                    Your name
                    <input
                      autoComplete="name"
                      required
                      maxLength={100}
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                    />
                  </label>
                  <label>
                    Email
                    <input
                      type="email"
                      autoComplete="email"
                      required
                      maxLength={254}
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                    />
                  </label>
                </>
              ) : (
                <section role="status">
                  <h2>Anonymous +1</h2>
                  <p>
                    Your personal details will not be sent. Your coach must
                    confirm attendance.
                  </p>
                  <button
                    type="button"
                    className="secondary"
                    onClick={() => setCountOnly(false)}
                  >
                    Use my details instead
                  </button>
                </section>
              )}
              {session.forms.map((f) => (
                <fieldset key={f.id}>
                  <legend>
                    {f.title} · version {f.version}
                  </legend>
                  <div className="agreement">
                    {(f.body ?? f.content).split("\n").map((line, i) => (
                      <div
                        className={
                          /^(RALLY4EVER|Grievance Procedures|Photo Release|Data Collection|[1-6]\.\s+.{1,40}$)/.test(
                            line,
                          )
                            ? "legal-line legal-heading"
                            : "legal-line"
                        }
                        key={i}
                      >
                        {line}
                      </div>
                    ))}
                  </div>
                  <label className="check">
                    <input
                      type="checkbox"
                      checked={!!accepted[f.id]}
                      onChange={(e) =>
                        setAccepted({ ...accepted, [f.id]: e.target.checked })
                      }
                      required={f.required}
                    />
                    I have read and agree to {f.title}.
                    {!f.required ? " (Optional)" : ""}
                  </label>
                </fieldset>
              ))}
              <p className="small">
                We use your current location to check that you’re at the venue.
                The coach sees the scan time and distance. A known account email
                needs a one-time email link before attendance is attached.
              </p>
              <p className="small">
                Check-in opens {timestamp(session.opensAt, session.timezone)}{" "}
                and closes at the session end.
              </p>
              <button disabled={busy}>
                {busy ? "Checking location and details…" : "Check in"}
              </button>
            </form>
          )}
          {state === "verify" && (
            <section>
              <h2>Confirm your check-in</h2>
              <p>
                Your email link proves ownership of the existing account. We
                will check your location again before completing attendance.
              </p>
              <button
                disabled={busy}
                onClick={() =>
                  run(async () =>
                    complete(link.requestId, link.oobCode, await locate()),
                  )
                }
              >
                {busy ? "Verifying…" : "Verify email and check in"}
              </button>
            </section>
          )}
          {state === "email" && (
            <section>
              <h2>Check your email</h2>
              <p>
                Open the one-time verification link we sent to {email}. It
                protects attendance already attached to your account.
              </p>
              <p className="small">
                Use the link promptly. If the coach’s QR has rotated, scan the
                current code and request a fresh link.
              </p>
            </section>
          )}
          {state === "pending" && (
            <section className="success" role="status">
              <span className="tick">✓</span>
              <h2>
                You’re checked in.
                <br />
                Waiting for your coach.
              </h2>
              <p>
                Please introduce yourself to the coach so they can confirm your
                attendance. No app account was created.
                {countOnly ? " You are recorded only as Anonymous +1." : ""}
              </p>
            </section>
          )}
          {state === "duplicate" && (
            <section role="status">
              <h2>Already checked in</h2>
              <p>
                A check-in is already recorded for this email and session. Ask
                the coach to check its confirmation status.
              </p>
            </section>
          )}
          {error && (
            <div role="alert" className="error">
              <h2>
                {state === "failed"
                  ? "Unable to open check-in"
                  : "Please try again"}
              </h2>
              <p>{error}</p>
              <p>Ask the coach for help or scan their current QR.</p>
            </div>
          )}
        </>
      )}
      <footer>
        <p>Keep playing with Rally4Ever.</p>
        <a href="https://apps.apple.com/app/id6816826035" rel="noreferrer">
          Get the iPhone app
        </a>
        <a
          href="https://play.google.com/store/apps/details?id=org.raly4ever"
          rel="noreferrer"
        >
          Get the Android app
        </a>
        <small>
          Location is checked only for this check-in. Every attendance record
          needs coach approval.
        </small>
      </footer>
    </main>
  );
}
