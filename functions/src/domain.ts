import { createHash, timingSafeEqual } from "node:crypto";
import { HttpsError, FunctionsErrorCode } from "firebase-functions/v2/https";

export type Input = Record<string, unknown>;
export interface Identity {
  uid: string;
  email: string;
  role?: string;
}
export function fail(
  code: FunctionsErrorCode,
  reason: string,
  message: string,
  extra = {},
): never {
  throw new HttpsError(code, message, { reason, ...extra });
}
export function input(value: unknown, allowed: string[]): Input {
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail("invalid-argument", "invalid-input", "Expected an object");
  const data = value as Input;
  if (Object.keys(data).some((k) => !allowed.includes(k)))
    fail("invalid-argument", "unknown-field", "Unexpected input field");
  return data;
}
export function text(value: unknown, name: string, max = 200, min = 1): string {
  if (
    typeof value !== "string" ||
    value.trim().length < min ||
    value.length > max
  ) {
    fail("invalid-argument", "invalid-input", `Invalid ${name}`);
  }
  return value.trim();
}
export function id(value: unknown, name = "id"): string {
  const result = text(value, name, 128);
  if (!/^[a-zA-Z0-9-]+$/.test(result))
    fail("invalid-argument", "invalid-id", `Invalid ${name}`);
  return result;
}
// Email document IDs match the latest requested normalized-email contract.
export function normalizeEmail(value: unknown): string {
  const email = text(value, "email", 254).toLowerCase();
  if (
    !/^[a-z0-9.!#$%&'*+=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+$/.test(email)
  ) {
    fail("invalid-argument", "invalid-email", "Enter a valid email address");
  }
  return email;
}
export function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
export function secretMatches(secret: string, expected: unknown): boolean {
  if (typeof expected !== "string" || !/^[a-f0-9]{64}$/.test(expected))
    return false;
  return timingSafeEqual(
    Buffer.from(hash(secret), "hex"),
    Buffer.from(expected, "hex"),
  );
}
export function coordinate(value: unknown, name: "lat" | "lng"): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    Math.abs(value) > (name === "lat" ? 90 : 180)
  ) {
    fail("invalid-argument", "invalid-location", `Invalid ${name}`);
  }
  return value;
}
export function distanceM(
  lat: number,
  lng: number,
  venueLat: number,
  venueLng: number,
): number {
  const rad = Math.PI / 180;
  const a =
    Math.sin(((venueLat - lat) * rad) / 2) ** 2 +
    Math.cos(lat * rad) *
      Math.cos(venueLat * rad) *
      Math.sin(((venueLng - lng) * rad) / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, a))));
}
export function checkWindow(
  now: number,
  start: number,
  end: number,
  timezone: string,
): void {
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start)
    fail("failed-precondition", "invalid-event", "Event times are invalid");
  const opens = start - 600000;
  if (now < opens) {
    const label = new Intl.DateTimeFormat("en-AU", {
      hour: "numeric",
      minute: "2-digit",
      timeZone: timezone,
    }).format(opens);
    fail("failed-precondition", "too-early", `Check-in opens at ${label}`, {
      opensAt: new Date(opens).toISOString(),
    });
  }
  if (now > end)
    fail("failed-precondition", "too-late", "Check-in has closed", {
      closedAt: new Date(end).toISOString(),
    });
}
export function checkDistance(
  lat: number,
  lng: number,
  venueLat: number,
  venueLng: number,
  radius: number,
): number {
  if (!Number.isFinite(radius) || radius <= 0)
    fail("failed-precondition", "invalid-event", "Venue radius is invalid");
  const distance = distanceM(lat, lng, venueLat, venueLng);
  if (distance > radius)
    fail("failed-precondition", "too-far", "You are too far from the venue", {
      distanceM: Math.round(distance),
      maxDistanceM: radius,
    });
  return distance;
}
export function authIdentity(
  auth: { uid: string; token: Record<string, unknown> } | undefined,
): Identity {
  if (!auth) fail("unauthenticated", "sign-in-required", "Sign in to continue");
  if (
    auth.token.email_verified !== true ||
    typeof auth.token.email !== "string"
  ) {
    fail(
      "permission-denied",
      "email-unverified",
      "Verify your email to continue",
    );
  }
  return {
    uid: auth.uid,
    email: normalizeEmail(auth.token.email),
    role:
      Array.isArray(auth.token.roles) && auth.token.roles.includes("admin")
        ? "admin"
        : Array.isArray(auth.token.roles) && auth.token.roles.includes("coach")
          ? "coach"
          : typeof auth.token.role === "string"
            ? auth.token.role
            : undefined,
  };
}
