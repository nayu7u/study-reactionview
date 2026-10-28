# Settings Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/settings` as the sixth showcase: a client-mode settings page with three tabs, dependent fields, a dirty state, and a demo save/reset, all at zero slots requests.

**Architecture:** A single client-mode template declares the form states and their derived gates (`name_ok`, `email_ok`, `bio_ok`, `handle_ok`, `form_ok`, `can_save`, `over`). Tabs and dependent fields are top-level parked branches. A panel-level `input`/`change` wrapper marks the form dirty; plan/frequency buttons carry their own literal sets so no `$value` + literal mixing is needed. Save/reset are browser state only.

> **Implementation ruling (2026-10-28, Task 3):** the parked tab branches were replaced with `hidden` presence panels. The browser probe showed the parked branch materialized its nested `digest` arm false and left the boolean `checked` binding unapplied, so the frequency controls disappeared while the switch rendered off. The tab/dependent markup in Tasks 1–2 below is superseded by that ruling; the measured result is 0 slots requests.

**Tech Stack:** Rails 8.1, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest integration tests, plain CSS, Playwright capture outside the repo.

**Spec:** `docs/superpowers/specs/2026-10-28-settings-screen-design.md`

## Global Constraints

- Client mode (`<%# herb:slots client %>`). Every tab, dependent field, dirty/save/reset operation sends **0 slots requests**.
- No DB, model, migration, real save, email, payment, or auth. Save is a demo; reload resets.
- Three tabs: `profile`, `notifications`, `billing`. The tab switch must not mark the form dirty.
- The dirty state is explicit. A panel-level wrapper listens to `input` and `change`; text/textarea/switch keep their automatic `value`/`checked` bindings. Plan/frequency buttons use literal `data-herb-set` values.
- Save button: `disabled="<%= !can_save %>"` (a single-negation presence). `can_save: dirty && form_ok`.
- `form_ok` is split into `name_ok`, `email_ok`, `bio_ok`, `handle_ok`; do not put the whole compound in the save button.
- Use buttons, not `<select>`, for the plan and frequency. The reset must visually restore the selected plan/frequency through `aria-pressed` state reads.
- Reset must not include derived states (`name_ok` etc.) in `data-herb-reset`, and must not reset `tab`.
- Textarea: use `value="<%= bio %>"`, never raw text.
- Media uses the app's Japanese font stack (`Hiragino Sans`, `Noto Sans CJK JP`, `Meiryo`, `Yu Gothic`) and verifies the actual platform font with Chromium CDP.
- Turbo comparison (D) is out of scope. The HTML twin is E, after B/C.
- **Final review of this plan must use GLM 5.3 Flash. Kimi is prohibited.**
- Japanese prose in README/docs/commit messages goes through the yomiyasu skill.

## Review Focus

1. **Tab branch materialization**: switching tabs must retain typed values and send 0 requests. The Lab wizard already measured this for top-level step branches; the Settings probe must re-check it after edits.
2. **Wrapper dirty composition**: the panel-level `input`/`change` action must compose with auto-bound text/textarea/switch writes. If it does not, fall back to per-element `data-herb-set="dirty=true saved=false"` (or a two-button switch), and record the change.
3. **Derived gates**: `handle_ok` (`!public_profile || handle != ""`), `form_ok` (`&&` of the four), and `can_save` (`dirty && form_ok`) must compile; the save button must be a single `!can_save` presence.
4. **Reset/save/no-persistence**: reset restores fields and plan/frequency selection; save marks saved and disables; reload resets everything; all with 0 requests.
5. **Media font and height**: Settings stills/GIF must use the JP platform font and avoid a stitched sticky header.

---

## File Structure

- `config/routes.rb` — add `GET /settings`.
- `app/controllers/settings_controller.rb` — empty index action; state lives in the view.
- `app/views/settings/index.html.erb` — tabs, panels, fields, save bar, state declarations.
- `app/views/layouts/application.html.erb` — Settings nav link.
- `app/assets/stylesheets/app.css` — `.settings-*` layout/nav/panel/save bar.
- `test/controllers/settings_controller_test.rb` — initial HTML, manifest, parked panels, reset list.
- `docs/media/settings-light.png`, `settings-dark.png`, `17-settings.gif` — new media.
- `README.md`, `docs/hotwire-comparison.md`, `AGENTS.md` — 6-screen docs.
- `/tmp/opencode/capture/*` — probe and capture scripts outside the repo.

---

### Task 1: Settings route, profile panel, save bar, and tests

**Files:**
- Create: `app/controllers/settings_controller.rb`
- Create: `app/views/settings/index.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Test: `test/controllers/settings_controller_test.rb`

**Interfaces:**
- Consumes: the existing client-mode patterns (`,seg`, `.field`, `.switch`, `.btn`, `.pill`, `herb:state`).
- Produces: `settings_path`; `SettingsController#index`; the state names `tab`, `name`, `email`, `bio`, `public_profile`, `handle`, `dirty`, `saved`, `name_ok`, `email_ok`, `bio_ok`, `handle_ok`, `form_ok`, `can_save`, `over`; field IDs `settings_name`, `settings_email`, `settings_bio`, `settings_handle`; classes `.settings-layout`, `.settings-nav`, `.settings-panel`, `.settings-save`, `.settings-dirty`, `.settings-saved`.

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/settings_controller_test.rb`:

```ruby
require "test_helper"

# What is covered here: the Settings screen contract — a client-mode form with
# three parked tabs, a dirty state, a derived save gate, and a demo save.
class SettingsFlowTest < ActionDispatch::IntegrationTest
  TEMPLATE = "app/views/settings/index.html.erb"

  def manifest
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    JSON.parse(json).values.first
  end

  test "settings renders the profile tab, tabs, and save bar" do
    get settings_path

    assert_response :success
    assert_select "h1", "Settings"
    assert_select ".settings-nav button", count: 3
    assert_select '.settings-nav button[aria-pressed="true"]', count: 1
    assert_select "#settings_name"
    assert_select "#settings_email"
    assert_select "#settings_bio"
    assert_select ".settings-save"
    assert_select ".settings-save button[disabled]"
    assert_select ".settings-dirty", count: 0
    assert_select ".settings-saved", count: 0
    assert_match(/<template data-herb-region=/, response.body)
  end

  test "the manifest declares the profile states and the save gate" do
    get settings_path
    states = manifest.dig("states")

    names = states["declarations"].map { |d| d["name"] }
    %w[tab name email bio public_profile handle dirty saved
       name_ok email_ok bio_ok handle_ok form_ok can_save over].each do |name|
      assert_includes names, name
    end

    form_ok = states["declarations"].find { |d| d["name"] == "form_ok" }
    assert form_ok["derived"].is_a?(Hash) && form_ok["derived"]["all"],
      "the save gate is an AND of the field gates"
    can_save = states["declarations"].find { |d| d["name"] == "can_save" }
    assert can_save["derived"].is_a?(Hash) && can_save["derived"]["all"],
      "can_save is dirty AND form_ok"
    handle_ok = states["declarations"].find { |d| d["name"] == "handle_ok" }
    assert handle_ok["derived"].is_a?(Hash) && handle_ok["derived"]["any"],
      "handle_ok is public_profile false OR a present handle"

    conditions = states["conditionals"].values
      .flat_map { |c| Array(c["arms"]) }
      .map { |a| a["condition"]&.first }
      .compact
    %w[tab public_profile dirty saved].each { |name| assert_includes conditions, name }

    presence = states["presence"].values.select { |p| p.is_a?(Array) }.map(&:first)
    assert_includes presence, "can_save", "the save button's disabled is a presence read"
    assert_includes presence, "public_profile", "the switch binds its boolean state"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/settings_controller_test.rb`

Expected: FAIL because `settings_path` and the settings template do not exist.

- [ ] **Step 3: Add the route, controller, and nav**

In `config/routes.rb`, add:

```ruby
  get "/settings", to: "settings#index"
```

Create `app/controllers/settings_controller.rb`:

```ruby
class SettingsController < ApplicationController
  def index
  end
end
```

In `app/views/layouts/application.html.erb`, add after Pricing:

```erb
        <%= link_to "Settings", settings_path %>
```

- [ ] **Step 4: Build the client-mode view shell**

Create `app/views/settings/index.html.erb` with the state declaration, hero, tabs, Profile panel, and save bar. Use the exact state line (one line in the file):

```erb
<%# herb:slots client %>
<%# herb:state (tab: "profile", name: "山田 太郎", email: "taro@example.com", bio: "", public_profile: false, handle: "", dirty: false, saved: false, name_ok: name != "", email_ok: email != "", bio_ok: bio.length <= 120, handle_ok: !public_profile || handle != "", form_ok: name_ok && email_ok && bio_ok && handle_ok, can_save: dirty && form_ok, over: bio.length > 120) %>
```

Layout:

```erb
<section class="hero">
  <div class="hero-badge">Client mode — 0往復</div>
  <h1>Settings</h1>
  <p class="hero-sub">タブ・依存フィールド・未保存状態を、ブラウザ内だけで組み立てます。</p>
</section>

<div class="settings-layout">
  <nav class="settings-nav" aria-label="設定">
    <button class="seg-btn" data-herb-set="tab=profile" aria-pressed="<%= tab == "profile" %>">Profile</button>
    <button class="seg-btn" data-herb-set="tab=notifications" aria-pressed="<%= tab == "notifications" %>">Notifications</button>
    <button class="seg-btn" data-herb-set="tab=billing" aria-pressed="<%= tab == "billing" %>">Billing</button>
  </nav>

  <div class="settings-panel"
    data-herb-set="input->dirty=true saved=false change->dirty=true saved=false">
    <% if tab == "profile" %>
      ... Profile fields ...
    <% elsif tab == "notifications" %>
      <p class="task-note">通知タブ（Task 2 で実装）</p>
    <% else %>
      <p class="task-note">請求タブ（Task 2 で実装）</p>
    <% end %>
  </div>

  <div class="settings-save">
    <% if dirty %><span class="pill settings-dirty">未保存の変更があります</span><% end %>
    <% if saved %><span class="pill settings-saved">保存しました（デモ）</span><% end %>
    <button class="btn btn-primary" disabled="<%= !can_save %>" data-herb-set="dirty=false saved=true">保存</button>
    <button class="btn btn-ghost" data-herb-reset="name email bio public_profile handle dirty saved">リセット</button>
  </div>
</div>
```

Profile fields:

```erb
<div class="field-group">
  <label class="field-label" for="settings_name">表示名</label>
  <input class="field" id="settings_name" value="<%= name %>">
  <label class="field-label" for="settings_email">メール</label>
  <input class="field" id="settings_email" type="email" value="<%= email %>">
  <label class="field-label" for="settings_bio">自己紹介</label>
  <textarea class="field" id="settings_bio" value="<%= bio %>"></textarea>
  <p class="char-hint"><%= bio.length %>/120字</p>
  <% if over %><p class="over-pill">⚠ 120字を超えています</p><% end %>
  <label class="task-check">
    <input type="checkbox" class="switch" checked="<%= public_profile %>">
    <span>公開プロフィール</span>
  </label>
  <% if public_profile %>
    <label class="field-label" for="settings_handle">ハンドル名</label>
    <input class="field" id="settings_handle" value="<%= handle %>">
  <% end %>
</div>
```

- [ ] **Step 5: Add the settings CSS**

In `app/assets/stylesheets/app.css`, add:

```css
/* ---------- settings ---------- */

.settings-layout {
  display: grid;
  grid-template-columns: 12rem minmax(0, 1fr);
  gap: 1.25rem;
  align-items: start;
}

@media (max-width: 52rem) {
  .settings-layout { grid-template-columns: 1fr; }
}

.settings-nav {
  display: grid;
  gap: 0.35rem;
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  padding: 0.6rem;
}

.settings-nav .seg-btn {
  text-align: left;
  justify-content: flex-start;
  width: 100%;
}

.settings-nav .seg-btn[aria-pressed="true"] {
  background: var(--accent-soft);
}

.settings-panel {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  padding: 1.35rem 1.5rem;
}

.settings-save {
  grid-column: 2;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.6rem;
  position: sticky;
  bottom: 1rem;
  background: color-mix(in srgb, var(--surface) 90%, transparent);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  padding: 0.7rem 0.9rem;
  backdrop-filter: blur(8px);
}

@media (max-width: 52rem) {
  .settings-save { grid-column: 1; }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/settings_controller_test.rb`

Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/settings_controller.rb app/views/settings/index.html.erb app/views/layouts/application.html.erb app/assets/stylesheets/app.css test/controllers/settings_controller_test.rb
git commit -m "feat(settings): 設定画面のProfileタブと保存バーを追加 — 未保存状態を0往復で扱う土台にするため" -m "client mode の状態宣言、タブ、Profileの依存フィールド、can_saveの保存ゲート、デモ保存/リセットを追加した。"
```

---

### Task 2: Notifications, Billing, dependent fields, and validation hints

**Files:**
- Modify: `app/views/settings/index.html.erb`
- Test: `test/controllers/settings_controller_test.rb`

**Interfaces:**
- Consumes: Task 1's tab shell, wrapper, save bar, profile fields, and `can_save`.
- Produces: `digest`, `frequency`, `updates`, `plan`, `annual`, `invoice_name` states; Notifications/Billing panels; plan/frequency buttons; validation hints; the full reset list.

- [ ] **Step 1: Add the failing tests**

Append to `test/controllers/settings_controller_test.rb`:

```ruby
  test "notifications and billing panels are parked with dependent fields" do
    get settings_path

    assert_includes response.body, "まとめ通知"
    assert_includes response.body, "年払い"
    assert_includes response.body, "請求書の宛名"
    assert_includes response.body, 'data-herb-set="frequency=daily dirty=true saved=false"'
    assert_includes response.body, 'data-herb-set="plan=starter dirty=true saved=false"'
    assert_includes response.body,
      'data-herb-reset="name email bio public_profile handle digest frequency updates plan annual invoice_name dirty saved"'
  end

  test "the manifest declares the notification and billing states" do
    get settings_path
    states = manifest.dig("states")

    names = states["declarations"].map { |d| d["name"] }
    %w[digest frequency updates plan annual invoice_name].each do |name|
      assert_includes names, name
    end

    conditions = states["conditionals"].values
      .flat_map { |c| Array(c["arms"]) }
      .map { |a| a["condition"]&.first }
      .compact
    %w[digest annual].each { |name| assert_includes conditions, name }

    presence = states["presence"].values.select { |p| p.is_a?(Array) }.map(&:first)
    %w[digest updates annual].each { |name| assert_includes presence, name }
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/settings_controller_test.rb`

Expected: FAIL on the missing notification/billing content, states, and reset list.

- [ ] **Step 3: Implement the Notifications panel**

Replace the Notifications placeholder with:

```erb
      <label class="task-check">
        <input type="checkbox" class="switch" checked="<%= digest %>">
        <span>まとめ通知</span>
      </label>
      <% if digest %>
        <div class="toolbar">
          <span class="field-label">頻度</span>
          <div class="seg">
            <button class="seg-btn" data-herb-set="frequency=daily dirty=true saved=false"
              aria-pressed="<%= frequency == "daily" %>">毎日</button>
            <button class="seg-btn" data-herb-set="frequency=weekly dirty=true saved=false"
              aria-pressed="<%= frequency == "weekly" %>">毎週</button>
          </div>
        </div>
      <% else %>
        <p class="toolbar-note">まとめ通知はオフです。</p>
      <% end %>
      <label class="task-check">
        <input type="checkbox" class="switch" checked="<%= updates %>">
        <span>プロダクト更新</span>
      </label>
```

- [ ] **Step 4: Implement the Billing panel**

Replace the Billing placeholder with:

```erb
      <span class="field-label">プラン</span>
      <div class="seg" role="group" aria-label="プラン">
        <button class="seg-btn" data-herb-set="plan=starter dirty=true saved=false"
          aria-pressed="<%= plan == "starter" %>">Starter</button>
        <button class="seg-btn" data-herb-set="plan=team dirty=true saved=false"
          aria-pressed="<%= plan == "team" %>">Team</button>
        <button class="seg-btn" data-herb-set="plan=business dirty=true saved=false"
          aria-pressed="<%= plan == "business" %>">Business</button>
      </div>
      <label class="task-check">
        <input type="checkbox" class="switch" checked="<%= annual %>">
        <span>年払い</span>
      </label>
      <% if annual %>
        <label class="field-label" for="settings_invoice_name">請求書の宛名</label>
        <input class="field" id="settings_invoice_name" value="<%= invoice_name %>">
      <% end %>
```

- [ ] **Step 5: Extend the reset list and validation**

Change the reset list to:

```erb
    <button class="btn btn-ghost" data-herb-reset="name email bio public_profile handle digest frequency updates plan annual invoice_name dirty saved">リセット</button>
```

Add the validation hints to the save bar so they are visible on every tab:

```erb
    <% if !name_ok || !email_ok %><span class="toolbar-note">表示名とメールは必須です。</span><% end %>
    <% if over %><span class="over-pill">⚠ 自己紹介は120字までです。</span><% end %>
    <% if public_profile && !handle_ok %><span class="toolbar-note">公開プロフィールにはハンドル名が必要です。</span><% end %>
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/settings_controller_test.rb`

Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/views/settings/index.html.erb test/controllers/settings_controller_test.rb
git commit -m "feat(settings): NotificationsとBillingの依存フィールドを追加 — タブ内の条件表示も0往復にするため" -m "まとめ通知→頻度、年払い→請求書宛名、公開プロフィール→ハンドル名を分岐で出し分け、プラン/頻度はリテラルsetのボタンにした。"
```

---

### Task 3: Browser probe, Settings media, and docs

**Files:**
- Create: `/tmp/opencode/capture/settings-probe.js` (outside the repo)
- Create: `/tmp/opencode/capture/settings-capture.js` (outside the repo)
- Create: `docs/media/settings-light.png`, `settings-dark.png`, `17-settings.gif`
- Modify: `docs/media/hub-light.png`, `hub-dark.png`, `patterns-light.png`, `patterns-dark.png`, `lab-light.png`, `lab-dark.png`, `pricing-light.png`, `pricing-dark.png`, `03-optimistic-add.gif`, `04-window-clauses.gif`
- Modify: `README.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 1/2's states, tabs, dependent fields, dirty/save/reset.
- Produces: browser evidence (0 requests, tab value retention, dirty/save/reset, font), Settings stills/GIF, 6-screen docs.

- [ ] **Step 1: Write and run the browser probe**

Create `/tmp/opencode/capture/settings-probe.js` with Playwright:

- Hide Herb dev tools.
- Record `?format=slots` requests.
- Open `/settings`.
- Check the computed and actual platform font; fail unless the actual font is a JP face (CDP `CSS.getPlatformFontsForNode`).
- Switch tabs (Notifications, Billing, Profile) and assert 0 slots.
- Notifications: digest off hides the frequency controls; on shows them; 0 slots.
- Profile: public_profile on shows the handle input; off hides it; 0 slots.
- Billing: annual on shows the invoice name; off hides it; 0 slots.
- Fill the name, assert the dirty pill and an enabled save; 0 slots.
- Clear the name, assert the required hint and a disabled save; restore; 0 slots.
- Turn public_profile on with an empty handle, assert the handle hint and a disabled save; fill the handle; 0 slots.
- Fill the bio with 121 characters, assert the over hint and a disabled save; restore; 0 slots.
- Save, assert the saved pill, no dirty pill, and a disabled save; 0 slots.
- Reset, assert the default name, no dirty/saved pills, and a disabled save; 0 slots.
- Billing: select Business; Notifications: select 毎日; reset; assert Team and 毎週 are selected again; 0 slots.
- Fill the name, switch tabs, return, and assert the value is retained; 0 slots.
- Reload and assert the defaults and 0 slots.

Run with the dev server up: `node settings-probe.js`

Expected: all assertions pass; 0 slots requests.

- [ ] **Step 2: Capture the Settings media**

Create `/tmp/opencode/capture/settings-capture.js` with the existing GIF helpers:

- `settings-light.png` / `settings-dark.png`: 1000×900 @2x, clipped/full-page so the sticky header does not stitch; assert the JP platform font.
- `17-settings.gif`: clip `.settings-layout`; frames: Profile initial, Notifications with digest on, digest off (frequency hidden), digest on, Profile with edited name (dirty), saved (saved pill). 6 frames.
- The capture must not add DB rows; no form POST.

Because the global nav gains a sixth link, also recapture the screen stills that show the nav (Hub, Patterns, Client Lab, Pricing) and the Hub `03-optimistic-add.gif` / `04-window-clauses.gif` with the 6-link nav and the JP font. Feature clips that do not show the nav (01/02/16-pin/08–14/UI components) stay unchanged. Clean up any task added by the Hub 03 capture.

Expected: stills and GIF show the JP glyphs, the 6-link nav, and the dirty/saved states; no sticky header artifact.

- [ ] **Step 3: Update README**

- Change 5 screens to 6; add Settings to the table with `<%# herb:slots client %>` and "タブ・依存フィールド・未保存状態".
- Add the Settings section with 機能⑰, the `17-settings.gif`, and bullets:
  - tabs switch parked branches at 0 requests;
  - dependent fields (digest→frequency, public→handle, annual→invoice);
  - dirty is explicit; save is a demo; reset restores; reload resets;
  - no DB, no custom JS.
- Add the stills after the intro, matching the other screens.
- Add `settings_controller_test` to the test list.

- [ ] **Step 4: Update docs/hotwire-comparison.md**

- Add a Settings row to the proof map: client mode, tabs/dependent/dirty, Stimulus form controller → state + branches.
- Add a §⑤ line: Settings interactions are 0 slots requests.
- Keep D out of the repo; HTML twin is E.

- [ ] **Step 5: Update AGENTS.md**

Add a Settings measured-facts section:

- top-level tab/dependent branches materialize with current state values and 0 requests (Lab wizard measured, Settings probe);
- the panel wrapper composes dirty with auto-bound inputs/switches; fallback if not;
- `can_save` is a derived AND; save disabled is a single `!can_save` presence;
- plan/frequency are buttons, avoiding `<select>` reset/value issues;
- save is a demo; reset includes the writable states only; the Settings media use the JP font.

- [ ] **Step 6: Run the gate**

Run:

```bash
grep -n "5画面\|五つ" README.md docs/hotwire-comparison.md
bin/rails test
bin/ci
```

Expected: no current screen-count mismatch; tests and CI green.

- [ ] **Step 7: Commit**

```bash
git add docs/media/settings-light.png docs/media/settings-dark.png docs/media/17-settings.gif \
  docs/media/hub-light.png docs/media/hub-dark.png docs/media/patterns-light.png docs/media/patterns-dark.png \
  docs/media/lab-light.png docs/media/lab-dark.png docs/media/pricing-light.png docs/media/pricing-dark.png \
  docs/media/03-optimistic-add.gif docs/media/04-window-clauses.gif \
  README.md docs/hotwire-comparison.md AGENTS.md
git commit -m "docs(settings): 設定画面のGIFと静止画を追加 — タブ・依存フィールド・未保存状態を0往復で見せるため" -m "ブラウザプローブでタブ値保持・0 slotsリクエスト・dirty/save/resetを確認し、メディアは日本語フォントスタックで撮影した。6項目ナビに合わせて既存の画面 stills と Hub 03/04 も撮り直した。"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 covers the route, controller, nav, profile fields, state gates, save bar, and tests. Task 2 covers Notifications/Billing, dependent fields, plan/frequency buttons, validation hints, and the full reset. Task 3 covers the probe, media, and 6-screen docs. D and the HTML twin are out of scope.
- **Type consistency:** `settings_path`; state names match the design; `settings_name`/`settings_email`/`settings_bio`/`settings_handle`/`settings_invoice_name`; `.settings-*` classes; `can_save`/`form_ok`/`handle_ok` shapes.
- **Review Focus:** each of the five lines has a test/probe/media check in Task 1/2/3.
- **Proportion:** the plan gives the test code and the delicate state/save/dirty markup; it does not restate the whole field copy.
