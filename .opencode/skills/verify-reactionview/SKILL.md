---
name: verify-reactionview
description: Drive the Study ReActionView app in headless Chrome, prove Sprint Hub search/add/sync and row state, Settings tab switching, Triage bulk selection, Pricing's one-request estimate, the UI Field warning, and the Lab accordion answer, and capture slots request counts plus screenshots. Use for /verify-reactionview, "verify the ReActionView demo", or after changing the reactive ERB screens.
---

# Verify ReActionView

Drive the real app the way a user does and keep the evidence. The harness starts Rails with a disposable test database, opens headless Chrome, records every slots request the client sends, and writes screenshots plus a JSON result.

## Launch

Run all eight journeys:

```console
$ bin/verify-reactionview run --all
```

The runner:

1. Creates `tmp/verify-reactionview/<run-id>/verify.sqlite3` and runs `bin/rails db:prepare` plus `db:seed:replant` against it with `RAILS_ENV=test`.
2. Starts `bin/rails server` on `127.0.0.1:3310`, or the next free port.
3. Launches Chrome for Testing through Selenium, with the slots counter installed before the app JavaScript runs.
4. Drives the journeys and writes the result.
5. Quits Chrome, stops the server, and deletes the disposable database.

The dev database is never touched.

## Doctor

Run this first when a browser or boot problem is suspected:

```console
$ bin/verify-reactionview doctor
```

It prints the Ruby, Selenium, Chrome, and `bin/rails` status, opens a data URL, and exits nonzero if Chrome cannot render. Chrome is downloaded by Selenium Manager on first use. If it exits with `libatk-1.0.so.0` or another missing shared library, install the Chrome runtime libraries for the distro. This container needed `libatk1.0-0`, `libatk-bridge2.0-0`, `libcups2`, `libdrm2`, `libxkbcommon0`, `libxcomposite1`, `libxdamage1`, `libxfixes3`, `libxrandr2`, `libgbm1`, `libpango-1.0-0`, `libcairo2`, `libasound2t64`, and `fonts-noto-cjk`.

## Drive one feature

```console
$ bin/verify-reactionview run --feature sprint-hub-search
$ bin/verify-reactionview run --feature sprint-hub-row-state
$ bin/verify-reactionview run --feature settings-tabs
$ bin/verify-reactionview run --feature triage-bulk
$ bin/verify-reactionview run --feature sprint-hub-add
$ bin/verify-reactionview run --feature pricing-estimate
$ bin/verify-reactionview run --feature ui-field-warning
$ bin/verify-reactionview run --feature lab-accordion-answer
```

Use `--port 3400` to move the server, and `--keep` to keep the disposable database for debugging. The run directory is printed first and is the only place evidence is written.

## Evidence

Each run writes to `tmp/verify-reactionview/<run-id>/`:

- `result.json` has one entry per feature with `status`, `assertions`, `slots.count`, `slots.urls`, and evidence paths.
- `<feature>.png` is the final screen for that feature.
- `<feature>.html` is the final DOM.
- `sprint-hub-add-optimistic.json` and `.png` capture the transient optimistic row before the drawer-close refetch removes it.
- `settings-tabs-notifications.png`, `settings-tabs-billing.png`, and `settings-tabs-profile.png` show each panel.
- `triage-bulk-selected.png` shows the two selected rows and the count fold. `triage-bulk.png` shows the flash and updated priority badges.
- `pricing-estimate.png` shows the final Business, 6-seat, annual, support estimate.
- `ui-field-warning-over.png` shows the 61-character warning; `ui-field-warning.png` shows the field after Backspace.
- `lab-accordion-open.png` shows the open FAQ; `lab-accordion-answer.png` shows it after the second click.
- `server.log` and `database.log` keep the boot and seed output.

`tmp/` is gitignored. Keep the run directory when evidence backs a report or a commit. Delete old run directories when they no longer matter.

## Cleanup

The runner owns its Chrome session, Rails process, and database. It kills only the process it started; never run `pkill` by name. A failed feature still writes `*-failure.png`, `*-failure.html`, and the error in `result.json`, then cleanup runs. Evidence survives cleanup.

## Gotchas

- Slots counts are per page load. The counter is injected with `Page.addScriptToEvaluateOnNewDocument`, so it is installed before the ReActionView client.
- Opening the Sprint Hub drawer costs one slots request. Closing it after add can cost another, and that refetch can remove the optimistic row when a search filter is active. Capture the row snapshot in the same wait loop; a screenshot taken afterward may show only the filtered row.
- The 201 splice does not update the hero. A later GET can, so record `hero_before_add` and `hero_after_add` instead of assuming the post stays optimistic.
- The search clear button resets the state and the note to `全件表示`, but it does not refetch the filtered rows in this build. Use `同期` or reload to return to all rows.
- Settings tab switches are client-only. The harness asserts exactly zero slots requests.
- Triage selection is client-only, and the bulk update is a standard PATCH form. Selection and update both send zero slots requests. There is no select-all; per-item state cannot be written from a global button.
- Pricing choices cost exactly one slots request each while the amounts stay outside the state branches. A server read inside a branch adds a branch refetch. The run asserts each increase and proves the document did not reload with a window marker.
- The UI Field warning is a `hidden` presence binding. Check `displayed?`; the span stays in the DOM. A slots request on either keystroke is a regression.
- The Lab FAQ answer is already outside the per-item branch. The marker still uses a static branch. A slots request on open or close is a regression.
- The test environment disables CSRF and uses `RAILS_ENV=test`; do not use this harness to prove authorization behavior.

The maintained feature map is [`features/README.md`](features/README.md). After changing a screen, route, selector, or seed, run `/pstack/maintain-verification-skill` so the map stays honest.
