# Server-Validation Forms (`/forms`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nav-less `/forms` page where a standard Rails form owns server validation (422 HTML, errors, preserved values) and a client-mode category filter shares the same page with zero slots requests.

**Architecture:** A `Proposal` model carries presence / length / email-format / inclusion validations. `ProposalsController#create` redirects on success and renders `index` with 422 on failure. The form uses `form_with` and deliberately omits `data-herb-into`, so the browser performs a normal document POST. The page is `herb:slots client` with one `filter_category` state; three category sections toggle via `hidden` presence, so filtering never hits the server and never rewrites the form's server-read values.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest integration tests, Playwright outside the repo for the browser probe, plain CSS.

**Spec:** `docs/superpowers/specs/2026-11-05-server-validation-forms-design.md`

## Global Constraints

- `.html.erb` templates only. No app JavaScript, Stimulus, Turbo, Node, yarn, Tailwind, or build step. The Playwright probe lives outside the repo.
- `/forms` stays out of the global nav. No existing stills or GIFs are re-shot. Patterns gets one footer link.
- The form is a plain `form_with`: no `data-herb-into`, no `data-herb-set` on the form. Success is a 302 redirect; failure is a 422 `text/html` full-page render.
- Validation rules: `speaker_name` presence + max 40; `email` presence + `URI::MailTo::EMAIL_REGEXP`; `title` presence + 5..80; `abstract` presence + 30..600; `category` inclusion in `rails`, `frontend`, `infra`.
- `filter_category` is the only client state; its default is `"all"`. State comparisons must use literals (never loop variables or helper results). The filter is 0 slots requests.
- Error messages are Rails' default English. i18n is out of scope.
- `Proposal::CATEGORIES = %w[rails frontend infra]`. Labels: Rails / フロントエンド / インフラ.
- Japanese prose in docs and commit messages goes through the yomiyasu skill. Commit messages record Why.
- Run `bin/rails test` and `bin/ci` before the final commit.

## Review Focus

These are the input classes and failure modes most likely to bite, with the task that pins each one.

1. **601-character abstract on 422**: the full text must come back in the textarea, not truncate or vanish. Pinned by Task 2's "long invalid abstract is preserved in full".
2. **HTML in user input**: a `<script>` title or abstract must be escaped in the 422 body. Pinned by Task 2's "user input is escaped".
3. **Empty database**: with no proposals, the page still renders the form and three empty category sections. Pinned by Task 2's "empty database still renders".
4. **Crafted client filter state**: `filter_category` set to an unknown value hides all three sections without an error, and "all" restores them, with 0 slots requests. Pinned by Task 4's probe.
5. **Form submit is a document POST**: the form must not send a slots request or be intercepted by the outbox. Pinned by Task 2's `form[data-herb-into]` assertion and Task 4's request counting.

---

## File Structure

- `db/migrate/<timestamp>_create_proposals.rb` — `proposals` table.
- `db/seeds.rb` — three sample proposals after the task seeds.
- `app/models/proposal.rb` — categories, labels, validations.
- `test/fixtures/proposals.yml` — one proposal per category.
- `test/models/proposal_test.rb` — validation contract.
- `config/routes.rb` — `GET /forms` and `POST /forms`.
- `app/controllers/proposals_controller.rb` — index and create; 422 render.
- `app/views/proposals/index.html.erb` — form, error summary, grouped list, client filter.
- `app/assets/stylesheets/app.css` — forms layout, errors, proposal cards.
- `test/controllers/proposals_controller_test.rb` — HTML flow, 422, slots POST boundary, filter manifest.
- `/tmp/opencode/capture/forms-probe.js` — browser probe (outside the repo).
- `docs/forms.md` — the practical evidence write-up.
- `README.md`, `docs/hotwire-comparison.md`, `docs/hotwire-comparison.html`, `AGENTS.md` — docs and measured facts.
- `app/views/patterns/index.html.erb` — one footer link to `/forms`.

---

### Task 1: Proposal model, migration, fixtures, seeds

**Files:**
- Create: `db/migrate/<timestamp>_create_proposals.rb`
- Create: `app/models/proposal.rb`
- Create: `test/fixtures/proposals.yml`
- Create: `test/models/proposal_test.rb`
- Modify: `db/seeds.rb`

**Interfaces:**
- Consumes: `ApplicationRecord`.
- Produces: `Proposal` with `speaker_name:String`, `email:String`, `title:String`, `abstract:Text`, `category:String`; `Proposal::CATEGORIES -> Array<String>`; `Proposal::CATEGORY_LABELS -> Hash<String,String>`; validations as listed in Global Constraints.

- [ ] **Step 1: Write the failing model test**

Create `test/models/proposal_test.rb`:

```ruby
require "test_helper"

# What is covered here: the server-side contract the form relies on.
# The browser never validates these rules; it posts and reads the 422.
class ProposalTest < ActiveSupport::TestCase
  test "a fixture proposal is valid" do
    assert proposals(:rails_talk).valid?
  end

  test "requires a speaker name and caps it at 40 characters" do
    proposal = proposals(:rails_talk)

    proposal.speaker_name = ""
    assert_not proposal.valid?
    assert proposal.errors[:speaker_name].any?

    proposal.speaker_name = "あ" * 41
    assert_not proposal.valid?
    assert proposal.errors[:speaker_name].any?
  end

  test "requires an email in a valid format" do
    proposal = proposals(:rails_talk)

    proposal.email = ""
    assert_not proposal.valid?
    assert proposal.errors[:email].any?

    proposal.email = "not-an-email"
    assert_not proposal.valid?
    assert proposal.errors[:email].any?
  end

  test "requires a title between 5 and 80 characters" do
    proposal = proposals(:rails_talk)

    proposal.title = "短い"
    assert_not proposal.valid?
    assert proposal.errors[:title].any?

    proposal.title = "a" * 81
    assert_not proposal.valid?
    assert proposal.errors[:title].any?
  end

  test "requires an abstract between 30 and 600 characters" do
    proposal = proposals(:rails_talk)

    proposal.abstract = "短い"
    assert_not proposal.valid?
    assert proposal.errors[:abstract].any?

    proposal.abstract = "あ" * 601
    assert_not proposal.valid?
    assert proposal.errors[:abstract].any?
  end

  test "requires a known category" do
    proposal = proposals(:rails_talk)

    proposal.category = "unknown"
    assert_not proposal.valid?
    assert proposal.errors[:category].any?
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/proposal_test.rb`
Expected: FAIL with `NameError: uninitialized constant Proposal` (or a missing-table error once the class exists).

- [ ] **Step 3: Create the migration, model, fixtures, and seeds**

Generate the migration:

```bash
bin/rails generate migration CreateProposals
```

Fill the migration body:

```ruby
class CreateProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :proposals do |t|
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

Create `app/models/proposal.rb`:

```ruby
class Proposal < ApplicationRecord
  CATEGORIES = %w[rails frontend infra].freeze
  CATEGORY_LABELS = {
    "rails" => "Rails",
    "frontend" => "フロントエンド",
    "infra" => "インフラ"
  }.freeze

  # Why not uniqueness: the same speaker may submit more than one talk, and a
  # unique index would add DB state that this evidence page does not measure.
  validates :speaker_name, presence: true, length: { maximum: 40 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :title, presence: true, length: { minimum: 5, maximum: 80 }
  validates :abstract, presence: true, length: { minimum: 30, maximum: 600 }
  validates :category, inclusion: { in: CATEGORIES }
end
```

If `URI::MailTo::EMAIL_REGEXP` is not defined in this environment, add `require "uri"` at the top of the model.

Create `test/fixtures/proposals.yml`:

```yaml
rails_talk:
  speaker_name: 山田 太郎
  email: taro@example.com
  title: ERBだけで作るリアクティブUI
  abstract: ReActionViewのスロットとクライアント状態を使い、ビルドなしで細粒度の更新を組み立てる話です。
  category: rails

frontend_talk:
  speaker_name: 佐藤 花子
  email: hanako@example.com
  title: フォームのバリデーションをサーバーに残す
  abstract: クライアント検証とサーバー検証の役割を分け、422の応答をどう扱うかを整理します。
  category: frontend

infra_talk:
  speaker_name: 鈴木 一郎
  email: ichiro@example.com
  title: 小さなRailsアプリの運用
  abstract: 依存を増やさずに運用するための構成と、障害時の切り分けを紹介します。
  category: infra
```

Add to `db/seeds.rb` after the existing `Task` seeds:

```ruby
Proposal.destroy_all

[
  [ "山田 太郎", "taro@example.com", "ERBだけで作るリアクティブUI",
    "ReActionViewのスロットとクライアント状態を使い、ビルドなしで細粒度の更新を組み立てる話です。", "rails" ],
  [ "佐藤 花子", "hanako@example.com", "フォームのバリデーションをサーバーに残す",
    "クライアント検証とサーバー検証の役割を分け、422の応答をどう扱うかを整理します。", "frontend" ],
  [ "鈴木 一郎", "ichiro@example.com", "小さなRailsアプリの運用",
    "依存を増やさずに運用するための構成と、障害時の切り分けを紹介します。", "infra" ]
].each do |speaker_name, email, title, abstract, category|
  Proposal.create!(speaker_name: speaker_name, email: email, title: title, abstract: abstract, category: category)
end
```

- [ ] **Step 4: Run the migration and the model test**

Run: `bin/rails db:migrate`
Then: `bin/rails test test/models/proposal_test.rb`
Expected: PASS, 6 runs.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb db/seeds.rb app/models/proposal.rb test/fixtures/proposals.yml test/models/proposal_test.rb
git commit -m "feat(forms): add Proposal validations for the server-validation page — the form needs a model whose 422 is worth showing"
```

---

### Task 2: Route, controller, form, grouped list, 422 flow

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/proposals_controller.rb`
- Create: `app/views/proposals/index.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Create: `test/controllers/proposals_controller_test.rb`

**Interfaces:**
- Consumes: `Proposal` and its validations from Task 1.
- Produces: `forms_path` (`/forms`); `ProposalsController#index` setting `@proposal` and `@proposals` (a `Hash<String, Array<Proposal>>`); `#create` redirecting on success and rendering `index` with 422 on failure; form fields named `proposal[speaker_name]`, `proposal[email]`, `proposal[title]`, `proposal[abstract]`, `proposal[category]`; `.proposal-group` sections; `.proposal-card`; `.form-errors`; `.field-error`.

- [ ] **Step 1: Write the failing integration test**

Create `test/controllers/proposals_controller_test.rb`:

```ruby
require "test_helper"

# What is covered here: the standard HTML write path. The form deliberately
# does not carry data-herb-into, so a 422 renders a whole document and the
# slots client never applies the error body.
class ProposalsControllerTest < ActionDispatch::IntegrationTest
  test "index renders the form and the grouped list without a slots write" do
    get forms_path

    assert_response :success
    assert_select "h1", "Proposal Submission"
    assert_select "form[action='#{forms_path}'][method='post']"
    assert_select "form[data-herb-into]", count: 0
    assert_select "input[name='proposal[speaker_name]']"
    assert_select "input[name='proposal[email]'][type='email']"
    assert_select "input[name='proposal[title]']"
    assert_select "textarea[name='proposal[abstract]']"
    assert_select "select[name='proposal[category]']"
    assert_select ".proposal-group", count: 3
    assert_select ".proposal-card", count: Proposal.count
  end

  test "an invalid submission answers 422 HTML with errors and preserved values" do
    post forms_path, params: { proposal: {
      speaker_name: "", email: "not-an-email", title: "短い",
      abstract: "短い", category: "unknown"
    } }

    assert_response :unprocessable_entity
    assert_equal "text/html", response.media_type
    assert_select ".form-errors[role='alert']"
    assert_select ".field-error", minimum: 3
    assert_select "input[name='proposal[email]'][value='not-an-email']"
    assert_select "input[name='proposal[title]'][value='短い']"
    assert_includes css_select("textarea[name='proposal[abstract]']").first.text, "短い"
  end

  test "a long invalid abstract is preserved in full" do
    long = "あ" * 601

    post forms_path, params: { proposal: {
      speaker_name: "山田 太郎", email: "taro@example.com",
      title: "長すぎる概要のテスト", abstract: long, category: "rails"
    } }

    assert_response :unprocessable_entity
    assert_includes css_select("textarea[name='proposal[abstract]']").first.text, long
  end

  test "user input is escaped in the 422 response" do
    post forms_path, params: { proposal: {
      speaker_name: "山田 太郎", email: "taro@example.com",
      title: "<script>alert(1)</script>", abstract: "<script>alert(2)</script>",
      category: "rails"
    } }

    assert_response :unprocessable_entity
    assert_no_match(/<script>alert/, response.body)
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "a valid submission creates a proposal and redirects" do
    assert_difference -> { Proposal.count }, 1 do
      post forms_path, params: { proposal: {
        speaker_name: "田中 次郎", email: "jiro@example.com",
        title: "標準フォームで作るサーバー検証",
        abstract: "422の応答を全画面で描き直し、入力値とエラーを保持する構成を紹介します。",
        category: "rails"
      } }
    end

    assert_redirected_to forms_path
    follow_redirect!
    assert_select ".flash", text: /プロポーザルを送信しました/
    assert_select ".proposal-card", text: /標準フォームで作るサーバー検証/
  end

  test "an empty database still renders the form and three empty groups" do
    Proposal.delete_all

    get forms_path

    assert_response :success
    assert_select "form[action='#{forms_path}']"
    assert_select ".proposal-card", count: 0
    assert_select ".proposal-group", count: 3
    assert_select ".proposal-group .task-note", count: 3
  end

  test "a slots POST of invalid data answers 422 slots, which the client discards" do
    post forms_path(format: "slots"),
      params: { proposal: {
        speaker_name: "", email: "bad", title: "", abstract: "", category: ""
      } },
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :unprocessable_entity
    assert_equal "application/vnd.herb.slots+json", response.media_type
    payload = JSON.parse(response.body)
    assert_includes payload["template"], "app/views/proposals/index.html.erb"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/proposals_controller_test.rb`
Expected: FAIL with a routing error for `/forms`.

- [ ] **Step 3: Add the route, controller, view, and CSS**

Add to `config/routes.rb` near the other top-level pages:

```ruby
get "/forms", to: "proposals#index", as: :forms
post "/forms", to: "proposals#create"
```

Create `app/controllers/proposals_controller.rb`:

```ruby
class ProposalsController < ApplicationController
  def index
    @proposal = Proposal.new
    @proposals = Proposal.order(created_at: :desc).group_by(&:category)
  end

  def create
    @proposal = Proposal.new(proposal_params)

    if @proposal.save
      redirect_to forms_path, notice: "プロポーザルを送信しました"
    else
      # Why not status: :ok or a slots envelope: the form is a normal HTML
      # form. Rails' 422 is the honest contract, and the browser re-renders
      # the whole document with the invalid values still attached.
      @proposals = Proposal.order(created_at: :desc).group_by(&:category)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def proposal_params
    params.require(:proposal).permit(:speaker_name, :email, :title, :abstract, :category)
  end
end
```

Create `app/views/proposals/index.html.erb` with this structure. The three category sections are explicit; a loop variable cannot be used in a state comparison later, and explicit literals keep Task 3 simple.

```erb
<section class="hero">
  <div class="hero-badge">サーバー検証 — 422 は標準フォームに残す</div>
  <h1>Proposal Submission</h1>
  <p class="hero-sub">このフォームは <code>data-herb-into</code> を使いません。送信は通常の POST で、失敗時は 422 の HTML が全画面を描き直します。</p>
</section>

<div class="forms-layout">
  <section class="feature">
    <h2>プロポーザルを送る</h2>

    <%= form_with model: @proposal, url: forms_path, class: "proposal-form" do |form| %>
      <% if @proposal.errors.any? %>
        <div class="form-errors" role="alert">
          <p><%= @proposal.errors.count %> 件の入力エラーがあります</p>
          <ul>
            <% @proposal.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div class="form-field">
        <%= form.label :speaker_name, "発表者名", class: "field-label" %>
        <%= form.text_field :speaker_name, class: "field", aria: { invalid: @proposal.errors[:speaker_name].any? } %>
        <% if @proposal.errors[:speaker_name].any? %>
          <p class="field-error"><%= @proposal.errors.full_message(:speaker_name, @proposal.errors[:speaker_name].first) %></p>
        <% end %>
      </div>

      <div class="form-field">
        <%= form.label :email, "メール", class: "field-label" %>
        <%= form.email_field :email, class: "field", aria: { invalid: @proposal.errors[:email].any? } %>
        <% if @proposal.errors[:email].any? %>
          <p class="field-error"><%= @proposal.errors.full_message(:email, @proposal.errors[:email].first) %></p>
        <% end %>
      </div>

      <div class="form-field">
        <%= form.label :title, "タイトル", class: "field-label" %>
        <%= form.text_field :title, class: "field", aria: { invalid: @proposal.errors[:title].any? } %>
        <% if @proposal.errors[:title].any? %>
          <p class="field-error"><%= @proposal.errors.full_message(:title, @proposal.errors[:title].first) %></p>
        <% end %>
      </div>

      <div class="form-field">
        <%= form.label :abstract, "概要", class: "field-label" %>
        <%= form.text_area :abstract, class: "field", rows: 6, aria: { invalid: @proposal.errors[:abstract].any? } %>
        <% if @proposal.errors[:abstract].any? %>
          <p class="field-error"><%= @proposal.errors.full_message(:abstract, @proposal.errors[:abstract].first) %></p>
        <% end %>
      </div>

      <div class="form-field">
        <%= form.label :category, "カテゴリ", class: "field-label" %>
        <%= form.select :category,
          Proposal::CATEGORIES.map { |category| [ Proposal::CATEGORY_LABELS.fetch(category), category ] },
          { include_blank: "選択してください" }, class: "select" %>
        <% if @proposal.errors[:category].any? %>
          <p class="field-error"><%= @proposal.errors.full_message(:category, @proposal.errors[:category].first) %></p>
        <% end %>
      </div>

      <%= form.submit "送信する", class: "btn btn-primary" %>
    <% end %>
  </section>

  <section class="feature">
    <h2>提出済み</h2>

    <section class="proposal-group" data-category="rails">
      <h3>Rails <span class="group-count"><%= @proposals.fetch("rails", []).size %> 件</span></h3>
      <% @proposals.fetch("rails", []).each do |proposal| %>
        <article class="proposal-card">
          <h4><%= proposal.title %></h4>
          <p class="proposal-meta"><%= proposal.speaker_name %> ・ <%= Proposal::CATEGORY_LABELS.fetch(proposal.category, proposal.category) %></p>
          <p><%= proposal.abstract %></p>
        </article>
      <% end %>
      <% if @proposals.fetch("rails", []).empty? %>
        <p class="task-note">まだありません。</p>
      <% end %>
    </section>

    <section class="proposal-group" data-category="frontend">
      <h3>フロントエンド <span class="group-count"><%= @proposals.fetch("frontend", []).size %> 件</span></h3>
      <% @proposals.fetch("frontend", []).each do |proposal| %>
        <article class="proposal-card">
          <h4><%= proposal.title %></h4>
          <p class="proposal-meta"><%= proposal.speaker_name %> ・ <%= Proposal::CATEGORY_LABELS.fetch(proposal.category, proposal.category) %></p>
          <p><%= proposal.abstract %></p>
        </article>
      <% end %>
      <% if @proposals.fetch("frontend", []).empty? %>
        <p class="task-note">まだありません。</p>
      <% end %>
    </section>

    <section class="proposal-group" data-category="infra">
      <h3>インフラ <span class="group-count"><%= @proposals.fetch("infra", []).size %> 件</span></h3>
      <% @proposals.fetch("infra", []).each do |proposal| %>
        <article class="proposal-card">
          <h4><%= proposal.title %></h4>
          <p class="proposal-meta"><%= proposal.speaker_name %> ・ <%= Proposal::CATEGORY_LABELS.fetch(proposal.category, proposal.category) %></p>
          <p><%= proposal.abstract %></p>
        </article>
      <% end %>
      <% if @proposals.fetch("infra", []).empty? %>
        <p class="task-note">まだありません。</p>
      <% end %>
    </section>
  </section>
</div>
```

Add to `app/assets/stylesheets/app.css`, near the settings block:

```css
/* ---------- forms: server validation + client filter ---------- */

.forms-layout {
  display: grid;
  gap: 1.25rem;
  grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
  align-items: start;
}

@media (max-width: 52rem) {
  .forms-layout { grid-template-columns: 1fr; }
}

.proposal-form .form-field { margin-bottom: 0.9rem; }

.form-errors {
  margin-bottom: 1rem;
  padding: 0.75rem 0.95rem;
  color: #b91c1c;
  background: color-mix(in srgb, #b91c1c 8%, var(--surface-2));
  border: 1px solid color-mix(in srgb, #b91c1c 28%, transparent);
  border-radius: var(--radius-sm);
  font-size: 0.9rem;
}

.form-errors ul { margin: 0.35rem 0 0; padding-left: 1.1rem; }

.field-error {
  margin: 0.3rem 0 0;
  color: #b91c1c;
  font-size: 0.84rem;
}

.field[aria-invalid="true"] { border-color: #b91c1c; }

.proposal-group { margin-bottom: 1rem; }
.proposal-group h3 { margin: 0 0 0.5rem; font-size: 0.95rem; }
.group-count { color: var(--muted); font-weight: 600; }

.proposal-card {
  padding: 0.7rem 0.85rem;
  margin-bottom: 0.55rem;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface-2);
}

.proposal-card h4 { margin: 0 0 0.25rem; font-size: 0.95rem; }
.proposal-card p { margin: 0.2rem 0 0; font-size: 0.88rem; color: var(--muted); }
.proposal-meta { font-size: 0.8rem !important; }
```

- [ ] **Step 4: Run the integration test**

Run: `bin/rails test test/controllers/proposals_controller_test.rb`
Expected: PASS, 7 runs. If the slots POST is answered with a different status, record the actual status and media type rather than forcing 200; the form never sends slots, and the boundary note in docs must match the measurement.

- [ ] **Step 5: Run the full test suite**

Run: `bin/rails test`
Expected: PASS. Existing tests must remain green.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/proposals_controller.rb app/views/proposals/index.html.erb app/assets/stylesheets/app.css test/controllers/proposals_controller_test.rb
git commit -m "feat(forms): add the standard HTML form and 422 re-render — server validation needs a path the outbox cannot swallow"
```

---

### Task 3: Client-mode category filter

**Files:**
- Modify: `app/views/proposals/index.html.erb`
- Modify: `test/controllers/proposals_controller_test.rb`

**Interfaces:**
- Consumes: the form and list markup from Task 2.
- Produces: `filter_category` client state; `.filter-chip` buttons; `hidden` presence on the three `.proposal-group` sections; `aria-pressed` reflecting the active chip.

- [ ] **Step 1: Write the failing manifest test**

Append to `test/controllers/proposals_controller_test.rb`:

```ruby
  test "the client filter declares one state and three hidden presences" do
    get forms_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json
    manifest = JSON.parse(json).values.first

    declarations = manifest.dig("states", "declarations")
    assert_equal [ "filter_category" ], declarations.map { |d| d["name"] }
    assert_equal "region", declarations.first["scope"]

    presence = manifest.dig("states", "presence")
    assert_equal 3, presence.size
    assert presence.values.all? { |condition| JSON.generate(condition).include?("filter_category") }

    assert_select ".filter-chip", count: 4
    assert_select ".proposal-group[hidden]", count: 0
    assert_equal "すべて", css_select(".filter-chip[aria-pressed='true']").first.text.strip
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/proposals_controller_test.rb -n "/client filter/"`
Expected: FAIL because no manifest or filter chips exist.

- [ ] **Step 3: Add the client state, chips, and hidden sections**

At the top of `app/views/proposals/index.html.erb`, add:

```erb
<%# herb:slots client %>
<%# herb:state (filter_category: "all") %>
```

Above the three sections, add the chips:

```erb
<div class="chips" role="group" aria-label="カテゴリで絞り込む">
  <button class="chip filter-chip" data-herb-set="filter_category=all" aria-pressed="<%= filter_category == "all" %>">すべて</button>
  <button class="chip filter-chip" data-herb-set="filter_category=rails" aria-pressed="<%= filter_category == "rails" %>">Rails</button>
  <button class="chip filter-chip" data-herb-set="filter_category=frontend" aria-pressed="<%= filter_category == "frontend" %>">フロントエンド</button>
  <button class="chip filter-chip" data-herb-set="filter_category=infra" aria-pressed="<%= filter_category == "infra" %>">インフラ</button>
</div>
```

Add the `hidden` presence to each group. The comparison must stay literal; do not replace the category with a loop variable or helper.

```erb
<section class="proposal-group" data-category="rails"
  hidden="<%= filter_category != "all" && filter_category != "rails" %>">
```

```erb
<section class="proposal-group" data-category="frontend"
  hidden="<%= filter_category != "all" && filter_category != "frontend" %>">
```

```erb
<section class="proposal-group" data-category="infra"
  hidden="<%= filter_category != "all" && filter_category != "infra" %>">
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/controllers/proposals_controller_test.rb`
Expected: PASS. If the `&&` condition fails to compile, replace the single state with three boolean states (`show_rails`, `show_frontend`, `show_infra`), have each chip set all three, and bind each section with `hidden="<%= !show_rails %>"`; rerun the test and the Task 4 probe.

- [ ] **Step 5: Commit**

```bash
git add app/views/proposals/index.html.erb test/controllers/proposals_controller_test.rb
git commit -m "feat(forms): filter proposals client-side — the page must keep its form values while the list changes"
```

---

### Task 4: Browser probe

**Files:**
- Create: `/tmp/opencode/capture/forms-probe.js` (outside the repo; not committed)

**Interfaces:**
- Consumes: `/forms` running on `http://localhost:3000`.
- Produces: measured counts for `docs/forms.md` and `AGENTS.md`: initial slots 0, filter slots 0, invalid POST 422 with 0 slots, valid POST 302 with 0 slots, unknown filter state hides all groups.

- [ ] **Step 1: Write the probe**

Create `/tmp/opencode/capture/forms-probe.js`:

```js
// Browser verification for /forms — lives OUTSIDE the repo.
// Run: node forms-probe.js (with bin/rails server up)
const { chromium } = require("playwright");

const BASE = "http://localhost:3000";

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1100, height: 1000 } });
  const slots = [];
  const posts = [];

  page.on("request", (request) => {
    if (/format=slots/.test(request.url())) slots.push(request.url());
  });
  page.on("response", (response) => {
    if (response.request().method() === "POST" && response.url().endsWith("/forms")) {
      posts.push(response.status());
    }
  });

  const assertZero = (label) => {
    if (slots.length !== 0) throw new Error(`${label}: ${slots.length} slots requests`);
  };
  const visibleGroups = () => page.locator(".proposal-group:not([hidden])").count();
  const hiddenGroups = () => page.locator(".proposal-group[hidden]").count();

  await page.goto(`${BASE}/forms`, { waitUntil: "networkidle" });
  await page.waitForTimeout(300);

  if ((await page.locator("form[data-herb-into]").count()) !== 0) {
    throw new Error("the form must not carry data-herb-into");
  }
  if ((await visibleGroups()) !== 3) throw new Error("the initial view must show all groups");
  assertZero("initial");

  await page.fill("input[name='proposal[title]']", "入力途中のタイトル");
  await page.getByRole("button", { name: "Rails", exact: true }).click();
  await page.waitForTimeout(300);
  assertZero("filter");
  if ((await page.inputValue("input[name='proposal[title]']")) !== "入力途中のタイトル") {
    throw new Error("the filter rewrote the form title");
  }
  if ((await visibleGroups()) !== 1 || (await hiddenGroups()) !== 2) {
    throw new Error("the Rails filter did not hide the other groups");
  }

  await page.fill("input[name='proposal[speaker_name]']", "");
  await page.fill("input[name='proposal[email]']", "not-an-email");
  await page.fill("input[name='proposal[title]']", "短い");
  await page.fill("textarea[name='proposal[abstract]']", "短い");
  await page.selectOption("select[name='proposal[category]']", "rails");
  await Promise.all([
    page.waitForNavigation(),
    page.click("input[type='submit']")
  ]);

  if (posts.at(-1) !== 422) throw new Error(`invalid submit answered ${posts.at(-1)}`);
  assertZero("invalid submit");
  if ((await page.locator(".form-errors").count()) !== 1) throw new Error("no error summary");
  if ((await page.inputValue("input[name='proposal[email]']")) !== "not-an-email") {
    throw new Error("the email value was not preserved");
  }
  if ((await page.inputValue("input[name='proposal[title]']")) !== "短い") {
    throw new Error("the title value was not preserved");
  }
  if ((await visibleGroups()) !== 3) throw new Error("the 422 reload must reset the filter to all");

  await page.fill("input[name='proposal[speaker_name]']", "田中 次郎");
  await page.fill("input[name='proposal[email]']", "jiro@example.com");
  await page.fill("input[name='proposal[title]']", "標準フォームで作るサーバー検証");
  await page.fill("textarea[name='proposal[abstract]']", "422の応答を全画面で描き直し、入力値とエラーを保持する構成を紹介します。");
  await page.selectOption("select[name='proposal[category]']", "rails");
  await Promise.all([
    page.waitForNavigation(),
    page.click("input[type='submit']")
  ]);

  if (posts.at(-1) !== 302) throw new Error(`valid submit answered ${posts.at(-1)}`);
  assertZero("valid submit");
  if (!(await page.locator(".flash").isVisible())) throw new Error("no success flash");
  if ((await page.locator(".proposal-card", { hasText: "標準フォームで作るサーバー検証" }).count()) === 0) {
    throw new Error("the new proposal is missing from the list");
  }

  await page.getByRole("button", { name: "Rails", exact: true }).click();
  await page.waitForTimeout(300);
  assertZero("filter after submit");
  if ((await visibleGroups()) !== 1) throw new Error("the filter did not survive the redirect");

  await page.evaluate(() => window.HerbRuntime.state.set({ filter_category: "unknown" }));
  await page.waitForTimeout(200);
  assertZero("unknown filter");
  if ((await visibleGroups()) !== 0) throw new Error("an unknown filter should hide every group");
  await page.evaluate(() => window.HerbRuntime.state.set({ filter_category: "all" }));
  await page.waitForTimeout(200);
  if ((await visibleGroups()) !== 3) throw new Error("'all' did not restore the groups");

  console.log(JSON.stringify({
    initialSlots: 0,
    filterSlots: 0,
    invalidStatuses: [422],
    validStatuses: [302],
    preserved: true,
    filterAfterSubmit: true,
    unknownFilterHidden: true
  }, null, 2));

  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
```

- [ ] **Step 2: Start the server and run the probe**

Run: `bin/rails server -p 3000 -d`
Then: `node /tmp/opencode/capture/forms-probe.js`
Expected: the JSON summary prints, with `initialSlots: 0`, `filterSlots: 0`, `invalidStatuses: [422]`, `validStatuses: [302]`, `preserved: true`. If a step throws, fix the page or the probe and rerun; do not weaken an assertion without recording why.

- [ ] **Step 3: Stop the server**

Run: `kill "$(cat tmp/pids/server.pid)"`
Expected: the server stops.

- [ ] **Step 4: Record the measured output**

Keep the stdout from the probe in the task notes for Task 5. No repository commit is made in this task.

---

### Task 5: Docs, Patterns link, final verification

**Files:**
- Create: `docs/forms.md`
- Modify: `README.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `docs/hotwire-comparison.html`
- Modify: `AGENTS.md`
- Modify: `app/views/patterns/index.html.erb`

**Interfaces:**
- Consumes: the measured output from Task 4 and the implementation from Tasks 1–3.
- Produces: the practical evidence document, updated showcase docs, and a discoverable link from Patterns.

- [ ] **Step 1: Add the Patterns footer link**

In `app/views/patterns/index.html.erb`, inside `<footer class="page-meta">`, add:

```erb
<p>実務検証: <a href="<%= forms_path %>">サーバー検証フォーム（422）</a> — 標準フォームと client mode の共存。</p>
```

Run: `bin/rails test test/controllers/patterns_controller_test.rb`
Expected: PASS.

- [ ] **Step 2: Write `docs/forms.md`**

Use these sections, with the measured numbers from Task 4:

1. **何を確かめたか** — the practical question: can a ReactionView app keep a standard Rails 422 form?
2. **結論** — yes, if the form stays a plain `form_with`; the outbox must not own it.
3. **なぜ slots 書き込みではだめか** — the client's `!response.ok` → `SlotsRequestError`; outbox `fail()` only sets `failed`; the 422 body is discarded.
4. **実装の形** — `form_with` without `data-herb-into`, `render :index, status: :unprocessable_entity`, error summary, preserved values.
5. **同じページの client mode 絞り込み** — `filter_category`, literal comparisons, `hidden` presence, 0 slots, form values untouched.
6. **使い分けの判断表** — client validation (Settings / Lab) / slots write (Hub) / standard HTML form (this page).
7. **実測** — the probe table: initial 0 slots, filter 0, invalid 422 + 0 slots, valid 302 + 0 slots, media types.
8. **制約** — full-page reload on error, filter resets after navigation, English error messages, no partial error updates, no-JS keeps the form but not the client filter.
9. **Why not 200 envelope / custom transport** — Rails convention, custom JS, weaker ERB-only claim.

- [ ] **Step 3: Update `README.md`**

After the UI Kit section and before `## 検証の進め方`, add:

```markdown
## 実務検証: サーバー検証フォーム（`/forms`、ナビ外）

標準の `form_with` と 422 の全画面再描画を、client mode のカテゴリ絞り込みと同じページに置いた検証。フォームは `data-herb-into` を使わず、成功はリダイレクト、失敗は 422 の HTML でエラーと入力値を保持する。絞り込みは 0 往復で、入力途中のフォーム値を壊さない。詳細と実測は [docs/forms.md](docs/forms.md)。
```

- [ ] **Step 4: Update `docs/hotwire-comparison.md`**

- Change `## ③ 実コード対比 — 5つの局面` to `6つの局面`.
- Add `### 対比 6 — サーバー検証（422）は標準フォームに残す` after 対比 5. Include the `form_with` snippet, the `render :index, status: :unprocessable_entity` line, and the outbox explanation.
- In `## ②`, add a note under the table: `ナビ外の実務検証として /forms があり、標準フォームと client mode の共存を測っている。`
- In `## ⑥`, add a bullet: `outbox（data-herb-into）は 422 の本文を適用しない — クライアントは !response.ok で例外を投げ、楽観行に failed を立てるだけ。サーバー検証は標準フォームに残す。`
- In `## ⑦`, replace the "追加候補はありません" sentence with the `/forms` result and the next candidate (if any). Keep the statement that this repo does not add `turbo-rails`.

- [ ] **Step 5: Sync `docs/hotwire-comparison.html`**

Mirror the Markdown changes: update the "5つの局面" label to "6つ", add a compact 対比 6 block using the existing section styling, and add the ② / ⑥ / ⑦ notes. Do not restructure the HTML.

- [ ] **Step 6: Update `AGENTS.md`**

Add a `## Forms 画面で実測した事実（0.6.0 / herb 0.11.1）` section after the Dashboard section. Record:

- `data-herb-into` の outbox は 422 の本文を適用しない（`SlotsRequestError`、`failed` のみ）。
- サーバー検証フォームは `data-herb-into` なしの `form_with` にし、422 の HTML 全画面再描画でエラーと入力値を保持する。
- `POST ?format=slots` の 422 は slots 本文で返るが、クライアントは適用しない（統合テストで固定）。
- client mode の絞り込みは 0 slots で、同じページのフォーム値を上書きしない。
- `filter_category` の `hidden` は `&&` コンボの presence としてコンパイルされる（3セクション）。
- テスト環境の media type は `text/html` / `application/vnd.herb.slots+json` で確認する。
- `/forms` はナビ外。Patterns footer と docs からリンクする。

- [ ] **Step 7: Run the full verification**

Run: `bin/rails test`
Expected: PASS.

Run: `bin/ci`
Expected: PASS (setup, RuboCop, audits, tests, seeds).

- [ ] **Step 8: Commit**

```bash
git add docs/forms.md README.md docs/hotwire-comparison.md docs/hotwire-comparison.html AGENTS.md app/views/patterns/index.html.erb
git commit -m "docs(forms): record the server-validation evidence — the standard HTML form is the practical home for 422"
```

---

## Self-Review

- **Spec coverage**: model/validations (Task 1), route/controller/form/422 (Task 2), client filter (Task 3), browser probe (Task 4), docs and Patterns link (Task 5). The spec's non-goals stay out: no nav link, no media re-shoot, no Hub changes, no i18n, no custom transport.
- **Step scan**: every step has one checkable action. Test expectations are explicit; the view's three repeated sections are intentional because state comparisons must stay literal.
- **Type consistency**: `forms_path`, `Proposal`, `Proposal::CATEGORIES`, `Proposal::CATEGORY_LABELS`, `filter_category`, `.filter-chip`, `.proposal-group`, `.proposal-card`, `.form-errors`, `.field-error` are used consistently across tasks.
- **Review Focus**: each of the five risks has a named test or probe assertion.
- **Proportion**: the plan includes test code and the key markup contract; it does not transcribe every CSS rule or every repeated card line.
