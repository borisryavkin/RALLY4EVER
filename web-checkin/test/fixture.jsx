import React from "react";
import { createRoot } from "react-dom/client";
import { CheckIn } from "../src/check-in.jsx";
import "../src/style.css";
history.replaceState(null, "", "/c/SESSION-1?k=" + "a".repeat(43));
window.calls = [];
const call = async (name, data) => {
  window.calls.push({ name, data });
  if (name === "getNoAppForms")
    return {
      eventId: "fixture-session",
      name: "Community pickleball",
      venue: { name: "UNSW courts", suburb: "Kensington" },
      startsAt: new Date().toISOString(),
      endsAt: new Date(Date.now() + 3600000).toISOString(),
      opensAt: new Date(Date.now() - 600000).toISOString(),
      timezone: "Australia/Sydney",
      forms: ["conduct", "waiver", "photo-release", "data-collection"].map(
        (id) => ({
          id,
          title: id,
          body: "Fixture agreement for browser tests only.",
          version: "2026-11-20",
          required: ["conduct", "waiver"].includes(id),
        }),
      ),
    };
  if (window.testFailure) throw { details: { reason: "invalid-secret" } };
  return { status: "pending", checkinId: "fixture-checkin", anonymous: true };
};
createRoot(document.getElementById("root")).render(<CheckIn call={call} />);
