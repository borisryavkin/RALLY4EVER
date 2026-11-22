import React from "react";
import {
  operationsFields,
  operationsStatuses,
} from "../../functions/src/operations_schema.ts";
import { Field, Button, Select } from "./controls.jsx";

export function initialOperations(row = {}) {
  const v = row.venue ?? {};
  return {
    fields: {
      location: v.suburb ?? v.name ?? "",
      state: v.state ?? "",
      status: "",
      scName: row.name ?? "",
      scActivities: row.sport ?? "",
      facilityName: v.name ?? "",
      tennisCentre: v.name ?? "",
      address: v.address ?? "",
      ...(row.operations?.fields ?? {}),
    },
    contacts: row.operations?.contacts ?? [],
  };
}
// Keep publication/booking state separate from the spreadsheet workflow status.
export function OperationsStatus({ value = {}, onChange }) {
  const status = value.fields?.status ?? "";
  return (
    <Select
      label="Operational status"
      value={status}
      onChange={(status) =>
        onChange({ ...value, fields: { ...value.fields, status } })
      }
      options={[
        { value: "", label: "Not set" },
        ...(status && !operationsStatuses.includes(status)
          ? [{ value: status, label: `${status} (existing value)` }]
          : []),
        ...operationsStatuses,
      ]}
    />
  );
}

export function OperationsEditor({ value = {}, onChange, inherited = false }) {
  const fields = value.fields ?? {},
    contacts = value.contacts ?? [];
  const groups = [...new Set(operationsFields.map((f) => f.group))];
  const set = (key, v) =>
    onChange({ ...value, fields: { ...fields, [key]: v } });
  const contact = (i, key, v) =>
    onChange({
      ...value,
      contacts: contacts.map((c, n) => (n === i ? { ...c, [key]: v } : c)),
    });
  return (
    <details className="editor spreadsheet-details">
      <summary>Spreadsheet details (admin only)</summary>
      <p>
        Contact details and internal notes are private to administrators.{" "}
        {inherited
          ? "These details are inherited from the program; saving creates a session-specific copy."
          : ""}{" "}
        Spreadsheet Status, Attendance and Closed Program preserve source
        values. Use the publishing, registration and Venue controls above to
        change live availability or map location.
      </p>
      {groups.map((group) => (
        <fieldset key={group}>
          <legend>{group}</legend>
          <div className="form-grid">
            {operationsFields
              .filter((f) => f.group === group && f.key !== "status")
              .map((f) => (
                <Field key={f.key} label={f.label}>
                  <textarea
                    rows={f.group === "Notes and community survey" ? 3 : 1}
                    maxLength={8000}
                    value={fields[f.key] ?? ""}
                    onChange={(e) => set(f.key, e.target.value)}
                  />
                </Field>
              ))}
          </div>
        </fieldset>
      ))}
      <fieldset>
        <legend>People of contact</legend>
        {contacts.map((c, i) => (
          <section className="editor" key={i}>
            <h4>Contact {i + 1}</h4>
            <div className="form-grid">
              {[
                ["name", "Person of Contact"],
                ["email", "Email"],
                ["phone", "Phone Number"],
                ["position", "Position"],
              ].map(([key, label]) => (
                <Field
                  key={key}
                  label={`${label} · contact ${i + 1}`}
                  value={c[key] ?? ""}
                  maxLength={1000}
                  onChange={(e) => contact(i, key, e.target.value)}
                />
              ))}
            </div>
            <Button
              type="button"
              secondary
              onClick={() =>
                onChange({
                  ...value,
                  contacts: contacts.filter((_, n) => n !== i),
                })
              }
            >
              Remove contact {i + 1}
            </Button>
          </section>
        ))}
        <Button
          type="button"
          secondary
          disabled={contacts.length >= 25}
          onClick={() =>
            onChange({
              ...value,
              contacts: [
                ...contacts,
                { name: "", email: "", phone: "", position: "" },
              ],
            })
          }
        >
          Add contact
        </Button>
      </fieldset>
    </details>
  );
}
