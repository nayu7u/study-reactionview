# Nested Thread (`/thread`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nav-less `/thread` page with posts and nested keyed replies, a standard reply form, and a `$refresh` slots request that reveals how nested collections behave.

**Architecture:** `Post has_many :replies`. `PostsController#index` renders a server-mode page with `<%# herb:key post.id %>` outside and `<%# herb:key reply.id %>` inside. `RepliesController#create` is a standard HTML POST with redirect + flash. A `$refresh` button requests the slots payload and the probe records whether the nested collection survives the wire and client apply.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest, Playwright outside the repo, plain CSS.

**Spec:** `docs/superpowers/specs/2026-11-06-thread-nested-design.md`

## Global Constraints

- The reply form is a standard POST; no `data-herb-into` in the shipped form.
- Both collection levels use `herb:key`; the page is server mode with a `$refresh` control.
- The nested outbox (`data-herb-into="replies"`) is a spike only; record the result, do not ship it if it mis-splices.
- `/forms`, `/apply`, `/outbox`, `/catalog` stay unchanged.
- `bin/rails test` and `bin/ci` green.

## Review Focus

1. **Nested keys compile and arrive**: both `herb:key` markers exist in the served HTML/slots. Pinned by the pages test.
2. **Reply creation works without JS**: a standard POST redirects with a flash and the count rises. Pinned by the replies test and probe.
3. **`$refresh` does not rebuild the outer post row**: the probe checks the outer DOM node identity and the reply count.
4. **Nested slots shape is recorded**: the payload's items/order/statics for the inner collection, or the absence of it. Pinned by the slots test/probe.
5. **Nested outbox spike is honest**: if `data-herb-into="replies"` cannot target the nested collection, the docs say so and the shipped form stays standard.

---

## File Structure

- `db/migrate/<timestamp>_create_posts.rb`, `..._create_replies.rb`
- `app/models/post.rb`, `app/models/reply.rb`
- `test/fixtures/posts.yml`, `replies.yml`
- `test/models/post_test.rb`, `reply_test.rb`
- `db/seeds.rb` (3 posts with replies)
- `config/routes.rb`
- `app/controllers/posts_controller.rb`, `app/controllers/replies_controller.rb`
- `app/views/posts/index.html.erb`
- `app/assets/stylesheets/app.css`
- `test/controllers/posts_controller_test.rb`, `replies_controller_test.rb`
- `/tmp/opencode/capture/thread-probe.js`
- `/tmp/opencode/capture/thread-capture.js`
- `docs/media/thread-light.png`, `thread-dark.png`, `24-thread.gif`
- `docs/thread.md`, `README.md`, `AGENTS.md`, `docs/hotwire-comparison.md/html`, `app/views/patterns/index.html.erb`

---

### Task 1: Post and Reply models

- [ ] Write model tests (presence, association, dependent destroy), watch them fail.
- [ ] Add the migrations, models, fixtures, and seeds; run `bin/rails db:migrate` and the tests; commit.

### Task 2: Thread page, reply create, nested keys, refresh

- [ ] Write integration tests for the posts page (posts, nested replies, reply counts, form, refresh) and the replies create (redirect, flash, count, no-JS). Watch them fail.
- [ ] Add routes, controllers, the view with nested `herb:key`s and the reply form, and CSS. Run the tests and the full suite; commit.

### Task 3: Probe (including the nested outbox spike)

- [ ] Write `/tmp/opencode/capture/thread-probe.js`: reply add, `$refresh`, outer DOM identity, nested reply count, record the slots payload shape; try `data-herb-into="replies"` in a throwaway DOM mutation and record whether the outbox finds the nested collection. Run with the server; keep the output.

### Task 4: Media

- [ ] `thread-capture.js`: stills light/dark; `24-thread.gif` (reply → refresh), fixed clip, Japanese font, frame-size assert. Commit.

### Task 5: Docs and final verification

- [ ] `docs/thread.md`: nested keys, slots shape, `$refresh`, the reply form, the nested outbox spike, constraints.
- [ ] README, hotwire-comparison (9→10), AGENTS.md, Patterns footer.
- [ ] Run `bin/rails test` and `bin/ci`; commit.
