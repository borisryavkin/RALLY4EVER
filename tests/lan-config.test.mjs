import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import {
  isPrivateIPv4,
  makeLanConfig,
  requireLocalInterface,
} from "../scripts/lan-config.mjs";
const base = JSON.parse(
  await readFile(new URL("../firebase.json", import.meta.url), "utf8"),
);
const opted = { LAN_TESTING: "true", LAN_HOST: "192.168.1.50" };
test("only canonical RFC1918 IPv4 addresses qualify", () => {
  for (const ip of [
    "10.0.0.1",
    "10.255.255.254",
    "172.16.0.1",
    "172.31.255.254",
    "192.168.0.1",
    "192.168.255.254",
  ])
    assert.equal(isPrivateIPv4(ip), true, ip);
  for (const ip of [
    "8.8.8.8",
    "172.15.0.1",
    "172.32.0.1",
    "192.169.1.1",
    "0.0.0.0",
    "127.0.0.1",
    "169.254.1.1",
    "100.64.0.1",
    "localhost",
    "10.example.test",
    "::1",
    "fc00::1",
    "10.0.0.256",
    "010.0.0.1",
    "10.0.0.1:9099",
    "http://192.168.1.1",
    "10.0.0.1 ",
    "10.0.0.1/24",
  ])
    assert.equal(isPrivateIPv4(ip), false, ip);
});
test("LAN configuration requires both flags and refuses production project/credentials", () => {
  for (const env of [
    {},
    { LAN_HOST: opted.LAN_HOST },
    { LAN_TESTING: "true" },
    { ...opted, LAN_HOST: "8.8.8.8" },
    { ...opted, NODE_ENV: "production" },
    { ...opted, GOOGLE_APPLICATION_CREDENTIALS: "/private/key.json" },
    ...["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "FIREBASE_PROJECT_ID"].map(
      (k) => ({ ...opted, [k]: "production-rally4ever" }),
    ),
  ])
    assert.throws(() => makeLanConfig(base, env));
});
test("only explicit LAN config exposes the data emulators; original config and admin UI stay local", () => {
  const original = structuredClone(base),
    lan = makeLanConfig(base, opted);
  for (const service of ["auth", "firestore", "functions"]) {
    assert.equal(lan.emulators[service].host, "0.0.0.0");
    assert.equal(base.emulators[service].host, "127.0.0.1");
  }
  for (const service of ["ui", "hub", "logging"])
    assert.equal(lan.emulators[service].host, "127.0.0.1");
  assert.deepEqual(base, original);
});
test("launcher requires an IP actually assigned to the Mac, not a router/other machine", () => {
  const interfaces = { en0: [{ address: "192.168.1.50", internal: false }] };
  requireLocalInterface(opted.LAN_HOST, interfaces);
  assert.throws(() => requireLocalInterface("192.168.1.1", interfaces));
});
test("default invocation refuses before generating config or starting any emulator", () => {
  const env = { ...process.env };
  delete env.LAN_TESTING;
  delete env.LAN_HOST;
  const result = spawnSync(process.execPath, ["scripts/emulators-lan.mjs"], {
    env,
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Explicit LAN_TESTING=true/);
});
