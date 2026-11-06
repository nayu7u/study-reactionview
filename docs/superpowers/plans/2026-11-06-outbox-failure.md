# Outbox Failure / Retry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nav-less `/outbox` page that demonstrates optimistic-add failure (500), `pending`/`failed` rows, retry/discard via the outbox JS API, and a no-JS flash fallback.

**Architecture:** A `Submission` model and a server-mode page with a `data-herb-into="submissions"` form. `create` returns 201 slots on success and 500 slots for a one-shot `fail_once` request; the outbox marks the optimistic row `failed`. A 12-line `app/javascript/outbox_retry.js` adapter calls `HerbRuntime.outbox.retry/discard` for the failed row buttons. The HTML fallback redirects with notice/alert.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest, Playwright outside the repo, plain CSS, one small app JS adapter.

**Spec:** `docs/superpowers/specs/2026-11-06-outbox-failure-design.md`

## Global Constraints

- The outbox is the write path; the page uses `data-herb-into="submissions"` and a server-mode template.
- Success: slots 201; failure: slots 500; the HTML fallback redirects with notice/alert.
- The retry/discard adapter is the only new app JS; importmap pin it.
- `failed`/`pending` are per-row client states; the pills and actions render from presences.
- `/forms` and `/apply` stay unchanged.
- `bin/rails test` and `bin/ci` green.

## Review Focus

1. **500 leaves the optimistic row failed, not confirmed**: the row's `failed` pill appears and the title stays. Pinned by the probe.
2. **Retry re-sends the same FormData and succeeds**: the one-shot session flag clears on success. Pinned by the controller test and probe.
3. **Discard removes the failed row**: the outbox API. Pinned by the probe.
4. **No-JS failure is a flash**: the HTML POST redirects with `alert`; no failed row. Pinned by the controller test.
5. **The adapter is minimal and pinned**: `import "outbox_retry"` works in the browser; the cost is documented. Pinned by the probe.

---

## File Structure

- `db/migrate/<timestamp>_create_submissions.rb`
- `app/models/submission.rb`
- `test/fixtures/submissions.yml`
- `test/models/submission_test.rb`
- `db/seeds.rb` (3 submissions)
- `config/routes.rb` (GET/POST `/outbox`)
- `app/controllers/submissions_controller.rb`
- `app/views/layouts/application.html.erb` (alert flash)
- `app/views/submissions/index.html.erb`
- `app/assets/stylesheets/app.css`
- `test/controllers/submissions_controller_test.rb`
- `app/javascript/outbox_retry.js`
- `app/javascript/application.js`
- `config/importmap.rb`
- `/tmp/opencode/capture/outbox-probe.js`
- `/tmp/opencode/capture/outbox-capture.js`
- `docs/media/outbox-light.png`, `outbox-dark.png`, `23-outbox.gif`
- `docs/outbox-failure.md`, `README.md`, `AGENTS.md`, `docs/hotwire-comparison.md/html`, `app/views/patterns/index.html.erb`

---

### Task 1: Submission model, migration, fixtures, seeds

- [ ] Write `test/models/submission_test.rb` (valid fixture, title presence), watch it fail.
- [ ] Create the migration (`title:string`), the model (`validates :title, presence: true`), the fixtures (2), and 3 seeds with `Submission.destroy_all`.
- [ ] Run `bin/rails db:migrate` and the model test; commit.

---

### Task 2: Route, controller, layout alert, view, CSS, flow tests

- [ ] Write `test/controllers/submissions_controller_test.rb` with: GET page/form/list; slots 201; HTML notice; slots 500 + session flag; retry 201; HTML alert; no-JS form. Watch it fail.
- [ ] Add routes, `SubmissionsController`, the layout `alert` flash, the view (`herb:slots server`, collection, rows with `pending`/`failed`, pills, retry/discard buttons, form + `fail_once`), and CSS. Run the tests and the full suite; commit.

### Task 3: Retry/discard adapter and probe

- [ ] Add `app/javascript/outbox_retry.js` (12 lines), `import "outbox_retry"` in `application.js`, and the importmap pin.
- [ ] Write `/tmp/opencode/capture/outbox-probe.js`: fail_once submit → pending → 500 → failed pill → retry → 201; second failure → discard; no-JS alert; record slots/document counts. Run it with the server and record the output.

### Task 4: Media

- [ ] Add `/tmp/opencode/capture/outbox-capture.js`: stills light/dark; `23-outbox.gif` (fail → failed → retry → success), fixed clip, Japanese font, frame-size assert. Commit the media.

### Task 5: Docs and final verification

- [ ] `docs/outbox-failure.md`: the failure path, pending/failed, retry/discard API, the 12-line adapter cost, no-JS, constraints.
- [ ] README, hotwire-comparison (8→9), AGENTS.md, Patterns footer.
- [ ] Run `bin/rails test` and `bin/ci`; commit.
