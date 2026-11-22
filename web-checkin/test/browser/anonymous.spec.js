import {
  test,
  expect,
} from "../../../web-admin/node_modules/@playwright/test/index.mjs";
test.beforeEach(async ({ page }) => {
  await page.route("https://**", (r) => r.abort());
  await page.goto("/test/fixture.html");
});
test("anonymous +1 skips personal data, requires agreements, and reuses device/session token", async ({
  page,
}) => {
  await page
    .getByRole("button", { name: "Skip details — count me as +1" })
    .click();
  await expect(page.getByLabel("Your name")).toHaveCount(0);
  await expect(page.getByLabel("Email", { exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Check in", exact: true }).click();
  expect(
    await page.evaluate(
      () => window.calls.filter((c) => c.name === "beginNoAppCheckIn").length,
    ),
  ).toBe(0);
  for (const id of ["Code of Conduct", "Data Collection", "Photo Release"])
    await page
      .getByRole("checkbox", {
        name: "I have read and agree to " + id + ".",
        exact: true,
      })
      .check();
  await page.screenshot({
    path: new URL("../../../docs/screenshots/anonymous-plus-one/web-agreements.png", import.meta.url).pathname,
    fullPage: true,
  });
  await page.getByRole("button", { name: "Check in", exact: true }).click();
  await expect(
    page.getByText("You are recorded only as Anonymous +1.", { exact: false }),
  ).toBeVisible();
  const payload = await page.evaluate(
    () => window.calls.find((c) => c.name === "beginNoAppCheckIn").data,
  );
  expect(payload.countOnly).toBe(true);
  expect(payload.email).toBeUndefined();
  expect(payload.firstName).toBeUndefined();
  expect(Object.keys(payload.signedVersions)).toEqual(["conduct", "waiver", "data-collection", "photo-release"]);
  expect(payload.anonymousToken).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(
    await page.evaluate(() =>
      localStorage.getItem("r4e-anonymous-checkin:fixture-session"),
    ),
  ).toBe(payload.anonymousToken);
  await page.screenshot({
    path: new URL("../../../docs/screenshots/anonymous-plus-one/web-pending.png", import.meta.url).pathname,
    fullPage: true,
  });
});
test("expired QR gives a visible error and no success screen", async ({
  page,
}) => {
  await page
    .getByRole("button", { name: "Skip details — count me as +1" })
    .click();
  for (const id of ["Code of Conduct", "Data Collection", "Photo Release"])
    await page
      .getByRole("checkbox", {
        name: "I have read and agree to " + id + ".",
        exact: true,
      })
      .check();
  await page.evaluate(() => (window.testFailure = true));
  await page.getByRole("button", { name: "Check in", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("This QR expired");
  await expect(
    page.getByText("You are recorded only as Anonymous +1.", { exact: false }),
  ).toHaveCount(0);
});
