import React, { useId } from "react";
export function Field({ label, children, error, ...props }) {
  const errorId = useId(),
    control = children ?? <input {...props} />;
  return (
    <label className="field">
      <span>{label}</span>
      {React.cloneElement(control, {
        "aria-label": control.props["aria-label"] ?? label,
        "aria-invalid": error ? true : undefined,
        "aria-describedby": error ? errorId : undefined,
      })}
      {error && (
        <small id={errorId} className="field-error">
          {error}
        </small>
      )}
    </label>
  );
}
export function Select({
  label,
  value,
  onChange,
  options,
  multiple = false,
  error,
  name,
  required = false,
}) {
  return (
    <Field label={label} error={error}>
      <select
        name={name}
        required={required}
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
export function Button({ children, secondary = false, ...p }) {
  return (
    <button className={secondary ? "secondary" : ""} {...p}>
      {children}
    </button>
  );
}
export function Status({ value }) {
  return (
    <span className={"status " + value}>
      {value === "active" ? "published" : value}
    </span>
  );
}
