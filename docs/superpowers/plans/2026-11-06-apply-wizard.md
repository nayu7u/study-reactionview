# Apply Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nav-less `/apply` three-step proposal wizard with per-step server validation, a session-linked draft, explicit back links, a 422 re-render, and a final `Proposal` creation.

**Architecture:** An `ApplicationDraft` row stores the fields; `session[:application_draft_id]` links it. `ApplicationsController#show` renders the requested step (clamped 1..3); `#update` validates the step-specific fields and either advances, re-renders 422, or creates a `Proposal` in a transaction and redirects to `/forms`.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest, Playwright outside the repo, plain CSS.

**Spec:** `docs/superpowers/specs/2026-11-06-apply-wizard-design.md`

## Global Constraints

- Standard HTML forms only. No slots, no `data-herb-into`, no custom JS.
- Steps are 1..3; `?step=` is clamped and the step-specific validations run.
- The draft is session-linked; its id never appears in the URL.
- The final step creates exactly one `Proposal`, deletes the draft, clears the session, and redirects with a flash.
- `bin/rails test` and `bin/ci` green.

## Review Focus

1. **Step-skipping URL**: `?step=3` with an empty draft must fail validation on the final PATCH, not create a proposal. Pinned by the model/controller tests.
2. **Draft isolation**: two sessions must not share a draft. Pinned by the `open_session` test.
3. **422 keeps the step and values**: an invalid step 1/2 PATCH re-renders the same step with errors and values. Pinned by the integration tests.
4. **Final transaction**: the proposal is created and the draft removed together; the session is cleared. Pinned by the final test.
5. **No-JS and no slots**: every step is a GET/PATCH document; no client runtime dependency. Pinned by the forms assertions and the probe.

---

## File Structure

- `db/migrate/<timestamp>_create_application_drafts.rb`
- `app/models/application_draft.rb`
- `test/models/application_draft_test.rb`
- `config/routes.rb`
- `app/controllers/applications_controller.rb`
- `app/views/applications/show.html.erb`
- `app/assets/stylesheets/app.css`
- `test/controllers/applications_controller_test.rb`
- `/tmp/opencode/capture/apply-probe.js`
- `/tmp/opencode/capture/apply-capture.js`
- `docs/media/apply-light.png`, `apply-dark.png`, `22-apply.gif`
- `docs/wizard.md`, `README.md`, `AGENTS.md`, `docs/hotwire-comparison.md/html`, `app/views/patterns/index.html.erb`

---

### Task 1: ApplicationDraft model, migration, model tests

**Files:**
- Create: `db/migrate/<timestamp>_create_application_drafts.rb`
- Create: `app/models/application_draft.rb`
- Create: `test/models/application_draft_test.rb`

**Interfaces:**
- Produces: `ApplicationDraft` with the five fields, `step` accessor, step-dependent validations, `proposal_attributes -> Hash`.

- [ ] **Step 1: Write the failing model test**

```ruby
require "test_helper"

class ApplicationDraftTest < ActiveSupport::TestCase
  test "an empty draft is valid at step 0" do
    assert ApplicationDraft.new(step: 0).valid?
  end

  test "step 1 requires a speaker and a valid email" do
    draft = ApplicationDraft.new(step: 1, speaker_name: "", email: "not-an-email")
    assert_not draft.valid?
    assert draft.errors[:speaker_name].any?
    assert draft.errors[:email].any?
  end

  test "step 2 requires the talk fields" do
    draft = ApplicationDraft.new(step: 2, speaker_name: "山田 太郎", email: "taro@example.com",
      title: "短い", abstract: "短い", category: "unknown")
    assert_not draft.valid?
    assert draft.errors[:title].any?
    assert draft.errors[:abstract].any?
    assert draft.errors[:category].any?
  end

  test "step 3 requires every field" do
    draft = ApplicationDraft.new(step: 3)
    assert_not draft.valid?
    assert draft.errors[:speaker_name].any?
    assert draft.errors[:email].any?
    assert draft.errors[:title].any?
    assert draft.errors[:abstract].any?
    assert draft.errors[:category].any?
  end

  test "proposal_attributes returns the five fields" do
    draft = ApplicationDraft.new(speaker_name: "山田 太郎", email: "taro@example.com",
      title: "タイトルです", abstract: "あ" * 40, category: "rails")
    assert_equal(
      { "speaker_name" => "山田 太郎", "email" => "taro@example.com",
        "title" => "タイトルです", "abstract" => "あ" * 40, "category" => "rails" },
      draft.proposal_attributes
    )
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/models/application_draft_test.rb`
Expected: FAIL with a missing constant/table.

- [ ] **Step 3: Add the migration and model**

Migration:

```ruby
class CreateApplicationDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :application_drafts do |t|
      t.string :speaker_name
      t.string :email
      t.string :title
      t.text :abstract
      t.string :category
      t.timestamps
    end
  end
end
```

Model:

```ruby
class ApplicationDraft < ApplicationRecord
  attr_accessor :step

  validates :speaker_name, presence: true, length: { maximum: 40 }, if: -> { step.to_i >= 1 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { step.to_i >= 1 }
  validates :title, presence: true, length: { minimum: 5, maximum: 80 }, if: -> { step.to_i >= 2 }
  validates :abstract, presence: true, length: { minimum: 30, maximum: 600 }, if: -> { step.to_i >= 2 }
  validates :category, inclusion: { in: Proposal::CATEGORIES }, if: -> { step.to_i >= 2 }

  def proposal_attributes
    attributes.slice("speaker_name", "email", "title", "abstract", "category")
  end
end
```

- [ ] **Step 4: Run the migration and the model test**

Run: `bin/rails db:migrate`; `bin/rails test test/models/application_draft_test.rb`.
Expected: PASS, 5 runs.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb app/models/application_draft.rb test/models/application_draft_test.rb
git commit -m "feat(apply): add the step-aware draft model — each wizard step validates only what it asks"
```

---

### Task 2: Routes, controller, wizard view, CSS, flow tests

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/applications_controller.rb`
- Create: `app/views/applications/show.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Create: `test/controllers/applications_controller_test.rb`

- [ ] **Step 1: Write the failing flow test**

Create `test/controllers/applications_controller_test.rb` with tests for: GET step 1 + draft creation; invalid/valid step 1; invalid/valid step 2; step 3 confirm; final creation; back; clamps; session isolation; no-slot forms. Use `apply_path(step: n)` and `params: { application_draft: {...} }`. The final test asserts `Proposal.count +1`, `ApplicationDraft.count -1`, redirect to `forms_path` with the flash.

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/applications_controller_test.rb`
Expected: FAIL with a missing `apply_path`/constant.

- [ ] **Step 3: Add routes, controller, view, CSS**

Routes:

```ruby
get "/apply", to: "applications#show", as: :apply
patch "/apply", to: "applications#update"
```

Controller: `show`/`update` as in the spec, with `normalized_step`, `current_application`, `application_params`, and `submit` (transaction + session delete + redirect).

View: one `show.html.erb` with the step indicator, the step 1/2 forms, the step 3 confirmation form, the error summary, and the back/next links. Use `apply_path(step: @step)` and `method: :patch`; the step 3 form has no fields.

CSS: `.wizard`, `.wizard-steps`, `.wizard-step`, `.wizard-actions`, `.wizard-confirm`; reuse the existing form styles.

- [ ] **Step 4: Run the flow test and the full suite**

Run: `bin/rails test test/controllers/applications_controller_test.rb`; then `bin/rails test`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/applications_controller.rb app/views/applications app/assets/stylesheets/app.css test/controllers/applications_controller_test.rb
git commit -m "feat(apply): add the three-step server-validated wizard — each step answers 422 and keeps the draft"
```

---

### Task 3: Browser probe

Create `/tmp/opencode/capture/apply-probe.js`. Flow: `/apply` → empty next → 422 → valid step 1 → step 2 → invalid → 422 → valid → step 3 → back to step 2 → forward → confirm → submit → `/forms` flash and new card. Assert 0 slots and the document requests; repeat in a no-JS context. Run with the server and `db:seed`; keep the output for the docs.

---

### Task 4: Media

Extend `forms-capture` style into `/tmp/opencode/capture/apply-capture.js`: stills `/apply` light/dark; GIF `22-apply` with step 1 → 422 → step 2 → step 3 → success. Fixed clip, Japanese font, frame-size assert. Commit the three media files.

---

### Task 5: Docs and final verification

- `docs/wizard.md`: the three steps, per-step 422, session draft, back, final transaction, slots 0, no-JS, constraints.
- README: a `/apply` section with the stills/GIF and the test list.
- hotwire-comparison: add 対比 8 (7→8) and the HTML twin.
- AGENTS.md: a Wizard section.
- Patterns footer: add the `/apply` link.
- Run `bin/rails test` and `bin/ci`; commit.
