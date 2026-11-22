import { input, text, fail } from "./domain";
import { operationsFields } from "./operations_schema";
export function validateOperations(value: unknown) {
  const d = input(value, ["fields", "contacts"]);
  const values = input(
    d.fields ?? {},
    operationsFields.map((f) => f.key),
  );
  const fields = Object.fromEntries(
    operationsFields.map((f) => [
      f.key,
      text(values[f.key] ?? "", f.label, 8000, 0),
    ]),
  );
  if (
    d.contacts !== undefined &&
    (!Array.isArray(d.contacts) || d.contacts.length > 25)
  )
    fail("invalid-argument", "invalid-contacts", "Use up to 25 contacts");
  const contacts = (d.contacts ?? ([] as unknown[])) as unknown[];
  return {
    fields,
    contacts: contacts.map((c) => {
      const p = input(c, ["name", "email", "phone", "position"]);
      return Object.fromEntries(
        ["name", "email", "phone", "position"].map((k) => [
          k,
          text(p[k] ?? "", k, 1000, 0),
        ]),
      );
    }),
  };
}
