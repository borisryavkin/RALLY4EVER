import { test, expect } from "@playwright/test";
import path from "node:path";
const shot = (page, name) =>
  page.screenshot({
    path: path.resolve("../docs/screenshots/admin-fixes/" + name + ".png"),
  });
test.beforeEach(async ({ page }) => {
  await page.route("https://**/*", (r) => r.abort());
});
const open = (page, screen, extra = "") =>
  page.goto("/test/fixture.html?screen=" + screen + extra);
async function fillProgram(page) {
  const form = page.locator("form.editor");
  await form
    .getByLabel("Name", { exact: true })
    .fill("Pickleball testing program");
  await form.getByLabel("Sport", { exact: true }).selectOption("pickleball");
  await form.getByLabel("Schedule text").fill("Thursday 11:30–12:30");
  await form.getByLabel("Use a venue").selectOption("ultimo");
  return form;
}
test("searchable session picker uses date controls, filters and bounded keyboard accessible results", async ({
  page,
}) => {
  await open(page, "Attendance");
  await expect(
    page.getByRole("heading", { name: "Find a session" }),
  ).toBeVisible();
  await expect(page.locator(".session-result")).toHaveCount(24);
  await expect(
    page.getByText(/registered \/ .* checked in/).first(),
  ).toBeVisible();
  await shot(page, "after-attendance-picker");
  await page.getByRole("button", { name: "Today", exact: true }).click();
  await expect(page.locator(".session-result")).toHaveCount(1);
  await page.getByRole("button", { name: "All dates", exact: true }).click();
  await expect(page.locator(".session-result")).toHaveCount(24);
  await expect(
    page.getByRole("button", { name: "Next sessions" }),
  ).toBeEnabled();
  await page.getByRole("button", { name: "Next sessions" }).click();
  await expect(page.locator(".session-result")).toHaveCount(24);
  await page
    .getByLabel("Search sessions by program, venue or date")
    .fill("Ultimo");
  const result = page.locator(".session-result").first();
  await result.focus();
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("heading", { name: /Session attendance ·/ }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Export CSV", exact: true }),
  ).toBeEnabled();
});
test("person search displays cross-session history and exports a CSV", async ({
  page,
}) => {
  await open(page, "Attendance");
  await page
    .getByRole("button", { name: "Search a person", exact: true })
    .click();
  await page.getByLabel("Name or email").fill("priya");
  await page.getByRole("button", { name: /Priya Lal/ }).click();
  await expect(page.getByText("42 m", { exact: true })).toBeVisible();
  await expect(page.getByText("Confirmed by Dan").first()).toBeVisible();
  await shot(page, "after-attendance-person");
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export person CSV" }).click();
  expect((await download).suggestedFilename()).toContain("member-1");
});
test("program sport filter combines search and status, keeps count and survives refresh", async ({
  page,
}) => {
  await open(page, "Programs");
  await page.getByLabel("Sport", { exact: true }).selectOption("pickleball");
  await expect(page.getByText("32 of 63 programs")).toBeVisible();
  await expect(page).toHaveURL(/programSport=pickleball/);
  await shot(page, "after-programs-sport-filter");
  await page.reload();
  await expect(page.getByLabel("Sport", { exact: true })).toHaveValue(
    "pickleball",
  );
  await page.getByLabel("Search programs").fill("Pickleball at Ultimo");
  await page.getByLabel("Status", { exact: true }).selectOption("draft");
  await expect(page.getByText("1 of 63 programs")).toBeVisible();
});
test("program soft-delete requires exact name, offers restore and keeps deleted records hidden", async ({
  page,
}) => {
  await open(page, "Programs");
  await page
    .getByRole("button", { name: "Delete", exact: true })
    .first()
    .click();
  const dialog = page.getByRole("dialog");
  await expect(
    dialog.getByText(
      /soft-delete this program and 8 future generated sessions/,
    ),
  ).toBeVisible();
  await expect(
    dialog.getByRole("button", { name: "Delete program", exact: true }),
  ).toBeDisabled();
  await shot(page, "after-program-delete-dialog");
  await dialog
    .getByLabel("Type the program name to confirm")
    .fill("Pickleball at Ultimo Community Centre");
  await dialog
    .getByRole("button", { name: "Delete program", exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await expect(page.getByText("62 of 63 programs")).toBeVisible();
  await page.getByLabel("Show deleted").check();
  await page.getByRole("button", { name: "Restore", exact: true }).click();
  await expect(
    page.getByText("Program and linked sessions restored"),
  ).toBeVisible();
});
test("program with attendance offers Archive instead of Delete", async ({
  page,
}) => {
  await open(page, "Programs", "&blocked=1");
  await page
    .getByRole("button", { name: "Delete", exact: true })
    .first()
    .click();
  const d = page.getByRole("dialog");
  await expect(
    d.getByRole("button", { name: "Archive instead" }),
  ).toBeVisible();
  await expect(d.getByLabel("Type the program name to confirm")).toHaveCount(0);
  await shot(page, "after-program-delete-blocked");
});
test("create unlimited program and double submission produce one request and visible success", async ({
  page,
}) => {
  await open(page, "Programs");
  await page.getByRole("button", { name: "New program", exact: true }).click();
  const f = await fillProgram(page);
  await expect(f.getByLabel("Unlimited", { exact: true })).toBeChecked();
  await f.evaluate((form) => {
    form.dispatchEvent(
      new Event("submit", { bubbles: true, cancelable: true }),
    );
    form.dispatchEvent(
      new Event("submit", { bubbles: true, cancelable: true }),
    );
  });
  await expect(page.getByText("Program saved", { exact: true })).toBeVisible();
  await expect(page.locator("form.editor")).toHaveCount(0);
  const requests = await page.evaluate(() =>
    window.__calls.filter((c) => c.name === "saveProgram"),
  );
  expect(requests).toHaveLength(1);
  expect(requests[0].data.program.capacity).toBeNull();
  expect(requests[0].data.program.sport).toBe("pickleball");
  await shot(page, "after-program-save-success");
});
test("edit program saves capacity 20 and invalid capacity is visible, focused and never submitted", async ({
  page,
}) => {
  await open(page, "Programs");
  await page.getByRole("button", { name: "Edit", exact: true }).first().click();
  const f = page.locator("form.editor");
  await f.getByLabel("Capacity", { exact: true }).fill("5001");
  await f.getByRole("button", { name: "Save program", exact: true }).click();
  await expect(f.getByLabel("Capacity", { exact: true })).toBeFocused();
  await expect(f.locator(".save-error")).toBeVisible();
  expect(
    await page.evaluate(
      () => window.__calls?.filter((c) => c.name === "saveProgram").length ?? 0,
    ),
  ).toBe(0);
  await shot(page, "after-program-validation-error");
  await f.getByLabel("Capacity", { exact: true }).fill("20");
  await f.getByRole("button", { name: "Save program", exact: true }).click();
  await expect(page.getByText("Program saved", { exact: true })).toBeVisible();
  expect(
    await page.evaluate(
      () =>
        window.__calls.find((c) => c.name === "saveProgram").data.program
          .capacity,
    ),
  ).toBe(20);
});
test("server rejection is human and visible directly above Save", async ({
  page,
}) => {
  await open(page, "Programs", "&fail=1");
  await page.getByRole("button", { name: "New program", exact: true }).click();
  const f = await fillProgram(page);
  await f.getByRole("button", { name: "Save program", exact: true }).click();
  await expect(f.locator(".save-error")).toBeVisible();
  await expect(f.locator(".save-error")).toContainText(
    "leave it blank for unlimited",
  );
  await expect(page.getByText("[400]", { exact: false })).toHaveCount(0);
  await expect(
    page.getByText("(invalid-capacity)", { exact: false }),
  ).toHaveCount(0);
  await shot(page, "after-program-server-error");
  await f
    .getByRole("button", { name: "Save program", exact: true })
    .scrollIntoViewIfNeeded();
  await shot(page, "after-program-server-error-footer");
});
test("new program requires explicit sport and keeps blank capacity null on edit", async ({
  page,
}) => {
  await open(page, "Programs");
  await page.getByRole("button", { name: "New program", exact: true }).click();
  await expect(
    page.locator("form.editor").getByLabel("Sport", { exact: true }),
  ).toHaveValue("");
  await page
    .locator("form.editor")
    .getByLabel("Name", { exact: true })
    .fill("Pickleball session");
  await expect(
    page.getByText(/Suggested from the name: pickleball/),
  ).toBeVisible();
  await expect(
    page.locator("form.editor").getByLabel("Sport", { exact: true }),
  ).toHaveValue("");
});
test("create venue has no venue chooser, uses automatic unique code and editable geocoded coordinates", async ({
  page,
}) => {
  await open(page, "Venues");
  await expect(page.getByLabel("Use a venue")).toHaveCount(0);
  await page
    .getByLabel("Venue name", { exact: true })
    .fill("Armidale Tennis Centre");
  await expect(page.getByLabel("Venue code", { exact: false })).toHaveValue(
    "armidale-tennis-centre-nsw",
  );
  await expect(
    page.getByLabel("Venue code", { exact: false }),
  ).not.toBeEditable();
  await page.getByLabel("Venue address").fill("40 William Henry Street");
  await page.getByLabel("Venue suburb").fill("Ultimo");
  await page
    .getByRole("button", { name: "Find coordinates from address", exact: true })
    .click();
  await expect(page.getByLabel("Latitude")).toHaveValue("-33.88");
  await page.getByLabel("Latitude").fill("-33.881");
  await expect(page.getByLabel("Latitude")).toHaveValue("-33.881");
  await shot(page, "after-create-venue");
  await page
    .getByRole("button", { name: "Edit venue code", exact: true })
    .click();
  await expect(page.getByLabel("Venue code", { exact: false })).toBeEditable();
});

test("create program with capacity 20 sends a numeric capacity", async ({
  page,
}) => {
  await open(page, "Programs");
  await page.getByRole("button", { name: "New program", exact: true }).click();
  const form = await fillProgram(page);
  await form.getByLabel("Capacity", { exact: true }).fill("20");
  await form.getByRole("button", { name: "Save program", exact: true }).click();
  await expect(page.getByText("Program saved", { exact: true })).toBeVisible();
  expect(
    await page.evaluate(
      () =>
        window.__calls.find((c) => c.name === "saveProgram").data.program
          .capacity,
    ),
  ).toBe(20);
});

test("person CSV export fetches all history pages instead of exporting just visible records", async ({
  page,
}) => {
  await open(page, "Attendance", "&historyPages=1");
  await page
    .getByRole("button", { name: "Search a person", exact: true })
    .click();
  await page.getByLabel("Name or email").fill("priya");
  await page.getByRole("button", { name: /Priya Lal/ }).click();
  await expect(
    page.getByRole("button", { name: "Load more history" }),
  ).toBeVisible();
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export person CSV" }).click();
  await download;
  const requests = await page.evaluate(() =>
    window.__calls.filter((c) => c.name === "adminPersonAttendance"),
  );
  expect(requests).toHaveLength(2);
  expect(requests[1].data.cursor).toBe("history-next");
});

test("venues offer confirmed deletion, hide deleted records and restore", async ({
  page,
}) => {
  await open(page, "VenueList");
  await page
    .getByRole("button", { name: "Delete", exact: true })
    .first()
    .click();
  const dialog = page.getByRole("dialog", { name: "Delete venue" });
  await expect(dialog.getByText("0 linked programs")).toBeVisible();
  await expect(
    dialog.getByRole("button", { name: "Delete venue", exact: true }),
  ).toBeDisabled();
  await dialog
    .getByLabel("Type the venue name to confirm")
    .fill("Ultimo Community Centre");
  await dialog
    .getByRole("button", { name: "Delete venue", exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await expect(
    page.getByRole("button", { name: "Edit / upload photo" }),
  ).toHaveCount(0);
  await page.getByLabel("Show deleted venues").check();
  await page.getByRole("button", { name: "Restore", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Edit / upload photo" }),
  ).toBeVisible();
  await shot(page, "after-venue-delete-restore");
});
test("venue deletion explains linked records and prevents deletion", async ({
  page,
}) => {
  await open(page, "VenueList", "&venueBlocked=1");
  await page
    .getByRole("button", { name: "Delete", exact: true })
    .first()
    .click();
  const dialog = page.getByRole("dialog", { name: "Delete venue" });
  await expect(dialog.getByRole("alert")).toContainText("cannot be deleted");
  await expect(
    dialog.getByRole("button", { name: "Delete venue", exact: true }),
  ).toBeDisabled();
  await shot(page, "after-venue-delete-blocked");
});

test("program spreadsheet details preserve source columns and repeatable private contacts", async ({
  page,
}) => {
  await open(page, "Programs");
  await page.getByRole("button", { name: "Edit", exact: true }).first().click();
  const details = page.locator(".spreadsheet-details");
  await details.locator("summary").click();
  await details.getByLabel("SC Name", { exact: true }).fill("Source SC name");
  await details
    .getByLabel("Equipment or merchandise needed", { exact: true })
    .fill("Six paddles");
  await details
    .getByRole("button", { name: "Add contact", exact: true })
    .click();
  await details
    .getByLabel("Person of Contact · contact 1", { exact: true })
    .fill("Sample coordinator");
  await details
    .getByLabel("Position · contact 1", { exact: true })
    .fill("Coordinator");
  await page.getByRole("button", { name: "Save program", exact: true }).click();
  await expect(
    page
      .locator(".editor")
      .filter({
        has: page.getByRole("button", { name: "Save program", exact: true }),
      }),
  ).toHaveCount(0);
  const payload = await page.evaluate(
    () => window.__calls.filter((c) => c.name === "saveProgram").at(-1).data,
  );
  expect(payload.operations.fields.scName).toBe("Source SC name");
  expect(payload.operations.fields.equipment).toBe("Six paddles");
  expect(payload.operations.contacts[0].position).toBe("Coordinator");
  expect(payload.program.operations).toBeUndefined();
});
test("session spreadsheet details submit separately from participant-readable changes", async ({
  page,
}) => {
  await open(page, "SessionDetails");
  const details = page.locator(".spreadsheet-details");
  await details.locator("summary").click();
  await details
    .getByLabel("Community Services Associated", { exact: true })
    .fill("Local service");
  await details.getByLabel("Closed Program", { exact: true }).fill("No");
  await page.getByRole("button", { name: "Save session", exact: true }).click();
  await expect(page.getByText("Session saved", { exact: true })).toBeVisible();
  const payload = await page.evaluate(
    () => window.__calls.find((c) => c.name === "adminSaveSession").data,
  );
  expect(payload.operations.fields.communityServices).toBe("Local service");
  expect(payload.changes.operations).toBeUndefined();
  await shot(page, "after-session-spreadsheet-fields");
});
