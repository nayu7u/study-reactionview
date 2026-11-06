# Proposal Edit / Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the `/forms` CRUD with a standard-HTML edit page, a 422 update re-render, a delete confirmation page, and a no-JS DELETE.

**Architecture:** Add `edit`, `update`, `confirm_destroy`, and `destroy` to `ProposalsController`. Extract the create form into a shared `_form` partial used by index and edit. The list cards link to the edit and confirm pages. All paths are normal document GET/POST; the page's existing client filter stays untouched.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest, Playwright outside the repo, plain CSS.

**Spec:** `docs/superpowers/specs/2026-11-06-forms-edit-delete-design.md`

## Global Constraints

- Standard HTML forms only. No `data-herb-into`, no custom JS, no Stimulus, no Turbo.
- Update success redirects; update failure is `422 text/html` with errors and preserved values.
- Delete goes through a GET confirmation page and a standard `button_to` DELETE with `_method=delete`.
- The create form markup must stay the same; it moves into a partial.
- `bin/rails test` and `bin/ci` must be green.

## Review Focus

1. **Update 422 keeps the PATCH URL**: the edit form must post to `form_path(@proposal)` with `_method=patch`; a 422 must re-render the same action. Pinned by the update test.
2. **No-JS delete**: the confirmation page's `button_to` must render `_method=delete` and work without JS. Pinned by the integration test and the no-JS probe.
3. **Delete is destructive only after confirmation**: the GET confirm has no side effects; only DELETE removes the row. Pinned by the confirm/destroy tests.
4. **Create still works**: the partial extraction must not change the create form's fields, errors, or no-JS path. Pinned by the existing create tests.
5. **The list actions are scoped per row**: each card links to its own proposal's edit/confirm path. Pinned by the index-link test.

---

## File Structure

- `config/routes.rb` — edit, patch, confirm, delete routes.
- `app/controllers/proposals_controller.rb` — set_proposal, edit, update, confirm_destroy, destroy.
- `app/views/proposals/_form.html.erb` — shared create/edit form.
- `app/views/proposals/index.html.erb` — partial + per-card actions.
- `app/views/proposals/edit.html.erb` — edit page + delete/cancel links.
- `app/views/proposals/confirm_destroy.html.erb` — confirmation page + DELETE button.
- `app/assets/stylesheets/app.css` — action row and confirm styling.
- `test/controllers/proposals_controller_test.rb` — CRUD tests.
- `/tmp/opencode/capture/forms-crud-probe.js` — browser probe.
- `/tmp/opencode/capture/forms-capture.js` — re-shoot the forms stills + GIF; add the CRUD GIF.
- `docs/forms.md`, `README.md`, `AGENTS.md`, `docs/hotwire-comparison.md/html` — docs.

---

### Task 1: Routes, controller, shared form, edit/confirm views, list actions

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/proposals_controller.rb`
- Create: `app/views/proposals/_form.html.erb`
- Modify: `app/views/proposals/index.html.erb`
- Create: `app/views/proposals/edit.html.erb`
- Create: `app/views/proposals/confirm_destroy.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Modify: `test/controllers/proposals_controller_test.rb`

**Interfaces:**
- Consumes: `Proposal` and the existing create/index.
- Produces: `edit_form_path(proposal)`, `form_path(proposal)` (PATCH/DELETE), `confirm_destroy_form_path(proposal)`; `ProposalsController#edit/#update/#confirm_destroy/#destroy`; `_form` partial locals `url`, `method`, `submit_label`; `.proposal-actions`.

- [ ] **Step 1: Write the failing CRUD tests**

Append to `test/controllers/proposals_controller_test.rb`:

```ruby
  test "the list links to edit and delete for every proposal" do
    get forms_path

    Proposal.find_each do |proposal|
      assert_select "a[href='#{edit_form_path(proposal)}']", text: "編集"
      assert_select "a[href='#{confirm_destroy_form_path(proposal)}']", text: "削除"
    end
  end

  test "edit renders the existing values and the update button" do
    proposal = proposals(:rails_talk)

    get edit_form_path(proposal)

    assert_response :success
    assert_select "form[action='#{form_path(proposal)}']"
    assert_select "input[name='_method'][value='patch']"
    assert_select "input[name='proposal[title]'][value='#{proposal.title}']"
    assert_select "input[type='submit'][value='更新する']"
    assert_select "a[href='#{confirm_destroy_form_path(proposal)}']", text: "削除"
  end

  test "an invalid update answers 422 HTML with the PATCH URL, errors and values" do
    proposal = proposals(:rails_talk)
    original = proposal.title

    patch form_path(proposal), params: { proposal: {
      speaker_name: "", email: "not-an-email", title: "短い",
      abstract: "短い", category: "unknown"
    } }

    assert_response :unprocessable_entity
    assert_equal "text/html", response.media_type
    assert_select "form[action='#{form_path(proposal)}']"
    assert_select "input[name='_method'][value='patch']"
    assert_select ".form-errors[role='alert']"
    assert_select ".field-error", minimum: 3
    assert_select "input[name='proposal[email]'][value='not-an-email']"
    assert_equal original, proposal.reload.title
  end

  test "a valid update changes the proposal and redirects" do
    proposal = proposals(:rails_talk)

    patch form_path(proposal), params: { proposal: {
      title: "更新したタイトル", abstract: "更新した概要です。" + "あ" * 30
    } }

    assert_redirected_to forms_path
    follow_redirect!
    assert_select ".flash", text: /プロポーザルを更新しました/
    assert_equal "更新したタイトル", proposal.reload.title
  end

  test "the delete confirmation shows the row and a DELETE form" do
    proposal = proposals(:rails_talk)

    get confirm_destroy_form_path(proposal)

    assert_response :success
    assert_select "h1", "プロポーザルを削除"
    assert_select "form[action='#{form_path(proposal)}'] input[name='_method'][value='delete']"
    assert_select "a[href='#{forms_path}']", text: "キャンセル"
  end

  test "delete removes the proposal and redirects" do
    proposal = proposals(:rails_talk)

    assert_difference -> { Proposal.count }, -1 do
      delete form_path(proposal)
    end

    assert_redirected_to forms_path
    follow_redirect!
    assert_select ".flash", text: /プロポーザルを削除しました/
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/proposals_controller_test.rb`
Expected: FAIL with a missing `edit_form_path` / route.

- [ ] **Step 3: Add routes, controller actions, partial, views, and CSS**

Routes (after the existing forms routes):

```ruby
get "/forms/:id/edit", to: "proposals#edit", as: :edit_form
patch "/forms/:id", to: "proposals#update", as: :form
get "/forms/:id/delete", to: "proposals#confirm_destroy", as: :confirm_destroy_form
delete "/forms/:id", to: "proposals#destroy"
```

Controller additions:

```ruby
before_action :set_proposal, only: %i[edit update confirm_destroy destroy]

def edit; end

def update
  @proposal.assign_attributes(proposal_params)

  if @proposal.save
    redirect_to forms_path, notice: "プロポーザルを更新しました"
  else
    render :edit, status: :unprocessable_entity
  end
end

def confirm_destroy; end

def destroy
  @proposal.destroy
  redirect_to forms_path, notice: "プロポーザルを削除しました"
end

private

def set_proposal
  @proposal = Proposal.find(params[:id])
end
```

Create `app/views/proposals/_form.html.erb` by moving the current create form body there. Use locals:

```erb
<%= form_with model: @proposal, url: local_assigns.fetch(:url, forms_path),
  method: local_assigns.fetch(:method, :post), class: "proposal-form",
  html: { novalidate: true } do |form| %>
  <% if @proposal.errors.any? %>
    <div class="form-errors" role="alert">...</div>
  <% end %>
  ... the existing speaker/email/title/abstract/category fields and errors ...
  <%= form.submit local_assigns.fetch(:submit_label, "送信する"), class: "btn btn-primary" %>
<% end %>
```

In `index.html.erb`, replace the inline `form_with` block with:

```erb
<%= render "form" %>
```

Add the action row to each proposal card (the three category sections):

```erb
<p class="proposal-actions">
  <%= link_to "編集", edit_form_path(proposal), class: "btn btn-ghost" %>
  <%= link_to "削除", confirm_destroy_form_path(proposal), class: "btn btn-ghost" %>
</p>
```

Create `edit.html.erb`:

```erb
<section class="hero">
  <div class="hero-badge">サーバー検証 — 更新も 422 の標準フォーム</div>
  <h1>プロポーザルを編集</h1>
  <p class="hero-sub">更新の失敗も、422 の HTML 全画面再描画でエラーと入力値を保持します。</p>
</section>

<div class="forms-layout">
  <section class="feature">
    <%= render "form", url: form_path(@proposal), method: :patch, submit_label: "更新する" %>
    <p class="proposal-actions">
      <%= link_to "削除", confirm_destroy_form_path(@proposal), class: "btn btn-ghost" %>
      <%= link_to "キャンセル", forms_path, class: "btn btn-ghost" %>
    </p>
  </section>
</div>
```

Create `confirm_destroy.html.erb`:

```erb
<section class="hero">
  <div class="hero-badge">削除の確認 — 標準の DELETE</div>
  <h1>プロポーザルを削除</h1>
  <p class="hero-sub">この操作は取り消せません。確認してから削除してください。</p>
</section>

<div class="forms-layout">
  <section class="feature">
    <h2><%= @proposal.title %></h2>
    <p class="proposal-meta"><%= @proposal.speaker_name %> ・ <%= Proposal::CATEGORY_LABELS.fetch(@proposal.category, @proposal.category) %></p>
    <p><%= @proposal.abstract %></p>
    <div class="proposal-actions">
      <%= button_to "削除する", form_path(@proposal), method: :delete, class: "btn btn-primary" %>
      <%= link_to "キャンセル", forms_path, class: "btn btn-ghost" %>
    </div>
  </section>
</div>
```

CSS:

```css
.proposal-actions { display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; margin-top: 0.6rem; }
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/controllers/proposals_controller_test.rb`
Expected: PASS (the existing tests plus 6 CRUD tests). If the `button_to` renders a `<form class="button_to">` with `input[name='_method']`, the selector matches.

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/proposals_controller.rb app/views/proposals app/assets/stylesheets/app.css test/controllers/proposals_controller_test.rb
git commit -m "feat(forms): complete the CRUD with edit, 422 update and confirmed delete — a real form needs more than create"
```

---

### Task 2: Browser probe

**Files:**
- Create: `/tmp/opencode/capture/forms-crud-probe.js` (outside the repo)

- [ ] **Step 1: Write the probe**

Flow: load `/forms`; click the first proposal's 編集; fill invalid values; submit; assert 422 HTML with errors and values; fix the values; submit; assert the flash and the updated title; click 編集 again; click 削除; assert the confirmation page; click 削除する; assert the row is gone and the flash. Count `format=slots` (expect 0) and document requests. Repeat the edit/delete path in a `javaScriptEnabled: false` context.

- [ ] **Step 2: Run the server and the probe**

Run: `bin/rails db:seed`; `bin/rails server -p 3000 -d`; `node /tmp/opencode/capture/forms-crud-probe.js`
Expected: the JSON summary with `slots: 0`, `update422: true`, `updateSuccess: true`, `deleted: true`, `noJS: true`.

- [ ] **Step 3: Stop the server**

Run: `kill "$(cat tmp/pids/server.pid)"`.

- [ ] **Step 4: Record the output**

Keep the stdout for Task 3/4. No repo commit.

---

### Task 3: Media

**Files:**
- Modify: `/tmp/opencode/capture/forms-capture.js` (outside the repo)
- Modify: `docs/media/forms-light.png`, `forms-dark.png`, `19-forms.gif`
- Create: `docs/media/21-forms-crud.gif`

- [ ] **Step 1: Re-shoot the existing stills and 19-forms GIF**

Run the existing capture with the new action links. The stills and `19-forms.gif` must show the current list. Keep the existing clip/font assertions.

- [ ] **Step 2: Add the CRUD GIF**

Add a second GIF flow to the capture: list → edit → invalid submit (422) → fix → update success → delete confirm → delete success. Use a fixed clip that includes the form and the list; assert every frame has the same dimensions; save `21-forms-crud.gif`.

- [ ] **Step 3: Inspect and commit**

Read the stills and the last frame. Commit:

```bash
git add docs/media/forms-light.png docs/media/forms-dark.png docs/media/19-forms.gif docs/media/21-forms-crud.gif
git commit -m "docs(forms): re-shoot the list and add the CRUD demo — the cards now lead to edit and delete"
```

---

### Task 4: Docs and final verification

**Files:**
- Modify: `docs/forms.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `docs/hotwire-comparison.html`

- [ ] **Step 1: Update `docs/forms.md`**

Add a section `## 編集・削除` covering:

- The edit page uses the shared form, `form_path(@proposal)`, `_method=patch`.
- The update failure is `422 text/html` with the same errors/values; no-JS.
- The delete confirmation is a GET with no side effects; the DELETE is a `button_to` with `_method=delete`.
- The measured probe: slots 0 on edit/update/confirm/delete; the URLs; the no-JS path.
- The media: `21-forms-crud.gif`.

- [ ] **Step 2: Update README / AGENTS / hotwire-comparison**

- README `/forms` section: mention edit/delete and add the `21-forms-crud.gif`.
- AGENTS Forms section: the update 422, the confirm page, the DELETE button, the slots 0, the media.
- hotwire-comparison 対比6: one line that update reuses the 422 HTML path and delete is a standard `button_to`.

- [ ] **Step 3: Run `bin/rails test` and `bin/ci`**

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/forms.md README.md AGENTS.md docs/hotwire-comparison.md docs/hotwire-comparison.html
git commit -m "docs(forms): record the edit/delete path — update is still a 422 form and delete is a confirmed standard DELETE"
```
