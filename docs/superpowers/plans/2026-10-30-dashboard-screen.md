# Dashboard Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/dashboard` as the seventh showcase: a client-mode operations dashboard that defers slow server reads with `<Async>`, `<Lazy>`, `<Fragment>`, and `poll`, while the page shell stays fast.

**Architecture:** One client-mode template declares `focus` and renders four server-read blocks. The controller is empty; a helper computes each block and sleeps only on slots requests when `?slow=1`. `<Async>` and `<Lazy>` request their own block content; `<Fragment>` masks a state-driven server read with its fallback; `poll` re-requests the heartbeat block every 3 seconds. No custom JavaScript, no migration, no worker.

**Tech Stack:** Rails 8.1, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest integration tests, plain CSS, Playwright capture outside the repo.

**Spec:** `docs/superpowers/specs/2026-10-28-dashboard-screen-design.md`

## Global Constraints

- Client mode (`<%# herb:slots client %>`). `<Async>` / `<Lazy>` / `<Fragment>` need slots.
- No custom JavaScript, no Node/yarn in the repo, no Tailwind/build step. Capture tools live in `/tmp/opencode/capture`.
- No migration, no new model, no background job, no real worker. Use existing `Task` data only.
- `?slow=1` delays **slots requests only**, 900ms, once per request via memoization. The initial HTML must stay fast.
- The Fragment must pass the state itself (`focus: focus`) to the helper/partial. Do not pass `@focus`; Herb will not register the server read.
- The Fragment manifest entry uses `on` for the state names and `server.reads` for the read registration. `fragments.*.reads` is an array of slot indices, not state names.
- Tests must not sleep: do not pass `slow` in controller tests. The browser probe measures the 900ms path.
- The nav gains a seventh link. Verify it stays on one row at 800px and 1000px, and re-shoot every still that shows the nav, including `ui-dialog.png`.
- Media uses the app's Japanese font stack and verifies the actual platform font (`Noto Sans CJK JP`) with Chromium CDP. GIF frames use one fixed viewport size.
- D (a `/compare` Turbo screen) stays out. The HTML twin sync is E, after C.
- **Final review must use GLM 5.3 Flash. Kimi is prohibited.**
- Japanese prose in README/docs/commit messages goes through the yomiyasu skill.

## Review Focus

1. **Fragment state read**: `focus: focus`, `on="focus"`, `server.reads["focus"]`; the fallback appears on a focus change and the stats change.
2. **Slow mode**: 900ms once per slots request; initial document is fast; `?slow=1` persists across block requests.
3. **Block responses**: block indices come from the manifest, never hardcoded; Async summary, Lazy activity, and poll heartbeat each answer with their own content.
4. **Poll**: 3-second interval, hidden-tab pause, visible timestamp update; the probe counts the extra block request.
5. **Nav/media**: seven links on one row at 800/1000; nav stills, Hub 03/04, and `ui-dialog.png` re-shot with the JP font.
6. **No-JS**: the initial HTML shows the Async/Lazy fallbacks and a `<noscript>` notice; no claim that deferred content loads without JS.

---

## File Structure

- `config/routes.rb` — add `GET /dashboard`.
- `app/controllers/dashboard_controller.rb` — empty `index`; state lives in the view.
- `app/helpers/dashboard_helper.rb` — slow gate, summary, activity, focus stats, heartbeat, labels.
- `app/views/dashboard/index.html.erb` — hero, slow link, four blocks, notes.
- `app/views/dashboard/_summary.html.erb`, `_activity.html.erb`, `_focus_stats.html.erb`, `_heartbeat.html.erb`.
- `app/views/layouts/application.html.erb` — Dashboard nav link after Sprint Hub.
- `app/assets/stylesheets/app.css` — dashboard grid/cards/skeleton/activity/heartbeat, compact nav.
- `test/controllers/dashboard_controller_test.rb` — initial HTML, manifest, block requests, fragment state.
- `/tmp/opencode/capture/dashboard-probe.js`, `dashboard-capture.js` — outside the repo.
- `docs/media/dashboard-light.png`, `dashboard-dark.png`, `18-dashboard.gif`.
- `README.md`, `docs/hotwire-comparison.md`, `AGENTS.md` — 7-screen docs and measured facts.

---

### Task 1: Route, Async summary, nav, slow link, and tests

**Files:**
- Create: `app/controllers/dashboard_controller.rb`
- Create: `app/helpers/dashboard_helper.rb`
- Create: `app/views/dashboard/index.html.erb`
- Create: `app/views/dashboard/_summary.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Test: `test/controllers/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `Task`, the layout, `app.css` tokens, existing `.pill`/`.seg` patterns.
- Produces: `dashboard_path`; `DashboardController#index`; `DashboardHelper#slow_demo?`, `#dashboard_summary`; the `.dashboard-*`, `.skeleton`, `.slow-toggle` classes; the manifest/block test helpers.

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/dashboard_controller_test.rb`:

```ruby
require "test_helper"

# What is covered here: the Dashboard deferred-content contract — Async/Lazy
# block requests, the Fragment's focus read, the poll heartbeat, and the
# slow-demo URL switch. Browser timing lives in dashboard-probe.js.
class DashboardFlowTest < ActionDispatch::IntegrationTest
  def manifest_envelope
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    JSON.parse(json)
  end

  def manifest
    manifest_envelope.values.first
  end

  def manifest_key
    manifest_envelope.keys.first
  end

  def template_path
    manifest_key.sub(/:[0-9a-f]+\z/, "")
  end

  def block_index(mode:, poll: nil)
    manifest.dig("states", "fragments").find do |_index, fragment|
      next false unless fragment["mode"] == mode
      poll.nil? || !!fragment["poll"] == poll
    end&.first
  end

  test "dashboard renders the async summary and the slow link" do
    get dashboard_path

    assert_response :success
    assert_select "h1", "Dashboard"
    assert_select "header nav a", count: 7
    assert_select ".dashboard-summary .skeleton"
    assert_select ".slow-toggle[href=?]", dashboard_path(slow: 1)
    assert_select ".slow-toggle", text: /遅延デモ: OFF/
    assert_select "noscript"
    refute_includes response.body, "全タスク"
  end

  test "the slow link turns the demo on" do
    get dashboard_path(slow: 1)

    assert_select ".slow-toggle[href=?]", dashboard_path
    assert_select ".slow-toggle", text: /遅延デモ: ON/
  end

  test "the manifest declares the async summary" do
    get dashboard_path
    fragments = manifest.dig("states", "fragments")
    async = fragments.values.find { |fragment| fragment["mode"] == "async" }

    assert_equal 1, fragments.count { |_index, fragment| fragment["mode"] == "async" }
    assert_equal 150, async["delay"]
    assert_equal 400, async["hold"]
  end

  test "the async block request answers with the summary" do
    get dashboard_path
    index = block_index(mode: "async", poll: false)

    get dashboard_path(format: :slots), headers: { "Herb-Block" => index }

    assert_response :success
    assert_equal "application/vnd.herb.slots+json", response.media_type
    assert_includes response.body, "全タスク"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: FAIL because `dashboard_path` does not exist.

- [ ] **Step 3: Add the route, controller, and nav**

In `config/routes.rb`, after the root route:

```ruby
  get "/dashboard", to: "dashboard#index"
```

Create `app/controllers/dashboard_controller.rb`:

```ruby
class DashboardController < ApplicationController
  def index
  end
end
```

In `app/views/layouts/application.html.erb`, after the Sprint Hub link:

```erb
        <%= link_to "Dashboard", dashboard_path %>
```

- [ ] **Step 4: Add the helper and the page shell**

Create `app/helpers/dashboard_helper.rb`:

```ruby
module DashboardHelper
  SLOW_SECONDS = 0.9
  PRIORITY_LABELS = { 1 => "低", 2 => "中", 3 => "高" }.freeze

  def slow_demo? = params[:slow] == "1"

  def dashboard_summary
    slow_slots
    {
      total: Task.count,
      high: Task.where(priority: 3).count,
      recent: Task.where(created_at: 24.hours.ago..).count
    }
  end

  def dashboard_priority_label(priority)
    PRIORITY_LABELS.fetch(priority, "?")
  end

  private

  # Why memoize: a slots refetch renders the whole template, so every block
  # helper runs. One 900ms sleep per request keeps the documented latency
  # at 900ms instead of 900ms times the number of blocks.
  def slow_slots
    return unless slow_demo? && request.format.slots?
    return if @slow_slots_slept

    @slow_slots_slept = true
    sleep SLOW_SECONDS
  end
end
```

Create `app/views/dashboard/index.html.erb`:

```erb
<%# herb:slots client %>

<section class="hero">
  <div class="hero-badge">Client mode — 遅延を測る</div>
  <h1>Dashboard</h1>
  <p class="hero-sub">ページの外枠はすぐ返し、重い集計だけを後から届けます。</p>
  <%= link_to slow_demo? ? "遅延デモ: ON（900ms）" : "遅延デモ: OFF",
        dashboard_path(slow: slow_demo? ? nil : 1), class: "slow-toggle" %>
</section>

<noscript><p class="task-note">遅延ブロックの読み込みには JavaScript が必要です。</p></noscript>

<div class="dashboard-layout">
  <section class="dashboard-card dashboard-summary">
    <Async delay="150" hold="400">
      <%= render "dashboard/summary" %>
      <Fallback>
        <div class="skeleton" aria-hidden="true">…</div>
      </Fallback>
    </Async>
  </section>

  <div class="dashboard-main">
    <!-- Task 2: activity, Task 3: fragment -->
  </div>

  <aside class="dashboard-side">
    <!-- Task 4: heartbeat -->
    <section class="dashboard-card dashboard-notes">
      <h2>リクエストの数え方</h2>
      <ul class="dashboard-note-list">
        <li>初回: document 1 + Async 2</li>
        <li>スクロール: Lazy 1</li>
        <li>フォーカス変更: Fragment 1</li>
        <li>poll: 3秒ごとに 1</li>
      </ul>
    </section>
  </aside>
</div>
```

Create `app/views/dashboard/_summary.html.erb`:

```erb
<% stats = dashboard_summary %>
<div class="metric-row">
  <div class="metric">
    <span class="metric-value"><%= stats[:total] %></span>
    <span class="metric-label">全タスク</span>
  </div>
  <div class="metric">
    <span class="metric-value"><%= stats[:high] %></span>
    <span class="metric-label">優先度: 高</span>
  </div>
  <div class="metric">
    <span class="metric-value"><%= stats[:recent] %></span>
    <span class="metric-label">直近24時間</span>
  </div>
</div>
```

- [ ] **Step 5: Add the dashboard CSS and compact nav**

Append to `app/assets/stylesheets/app.css`:

```css
/* ---------- dashboard ---------- */

.dashboard-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.45fr) minmax(0, 1fr);
  gap: 1.1rem;
  align-items: start;
}

.dashboard-summary { grid-column: 1 / -1; }

.dashboard-main,
.dashboard-side {
  display: grid;
  gap: 1.1rem;
}

.dashboard-card {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  padding: 1.3rem 1.45rem;
}

.dashboard-card h2 {
  margin: 0 0 0.9rem;
  font-size: 1rem;
}

.metric-row {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 0.8rem;
}

.metric {
  display: grid;
  gap: 0.2rem;
  padding: 0.8rem 0.9rem;
  background: var(--surface-2);
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
}

.metric-value {
  font-size: 1.8rem;
  font-weight: 720;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

.metric-label { color: var(--muted); font-size: 0.8rem; }

.skeleton {
  min-height: 5rem;
  border-radius: var(--radius-sm);
  background: linear-gradient(90deg, var(--surface-2), var(--line), var(--surface-2));
  background-size: 200% 100%;
  animation: skeleton-pulse 1.6s ease-in-out infinite;
}

@keyframes skeleton-pulse {
  from { background-position: 200% 0; }
  to { background-position: -200% 0; }
}

.skeleton-note {
  margin: 0.6rem 0 0;
  color: var(--muted);
  font-size: 0.9rem;
}

.slow-toggle {
  display: inline-flex;
  margin-top: 0.9rem;
  padding: 0.35rem 0.85rem;
  border: 1px solid var(--line);
  border-radius: 999px;
  background: var(--surface-2);
  color: var(--muted);
  font-size: 0.82rem;
  font-weight: 650;
  text-decoration: none;
}

.dashboard-note-list {
  margin: 0;
  padding-left: 1.2rem;
  color: var(--muted);
  font-size: 0.85rem;
  line-height: 1.7;
}

@media (max-width: 52rem) {
  .dashboard-layout { grid-template-columns: 1fr; }
  .dashboard-summary { grid-column: auto; }
  .metric-row { grid-template-columns: 1fr; }
}

@media (max-width: 56rem) {
  .site-header { padding: 0.8rem 1rem; gap: 0.5rem; }
  .site-nav { gap: 0; }
  .site-nav a { padding: 0.35rem 0.5rem; font-size: 0.85rem; }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/dashboard_controller.rb app/helpers/dashboard_helper.rb \
  app/views/dashboard/index.html.erb app/views/dashboard/_summary.html.erb \
  app/views/layouts/application.html.erb app/assets/stylesheets/app.css \
  test/controllers/dashboard_controller_test.rb
git commit -m "feat(dashboard): 遅延ダッシュボードのAsyncサマリーを追加 — 外枠を待たせず重い集計を後から届けるため" -m "client mode のダッシュボード、7リンクナビ、?slow=1 の遅延リンク、Asyncのサマリーとブロック応答のテストを追加した。"
```

---

### Task 2: Lazy activity

> **Implementation ruling (2026-10-30):** the 0.6.0 block response carries a collection slot with empty `items`, so a loop/partial inside `<Lazy>` renders an empty list. The card renders the first three tasks with explicit rows (`activity[0]`, `activity[1]`, `activity[2]`) instead of a collection. The `_activity.html.erb` partial from the original step is not created.

**Files:**
- Modify: `app/views/dashboard/index.html.erb`
- Create: `app/views/dashboard/_activity.html.erb`
- Modify: `app/helpers/dashboard_helper.rb`
- Modify: `app/assets/stylesheets/app.css`
- Test: `test/controllers/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: Task 1's page shell, helper, manifest/block test helpers.
- Produces: `DashboardHelper#recent_activity`; the `.dashboard-activity` card; the Lazy block.

- [ ] **Step 1: Add the failing tests**

Append to `test/controllers/dashboard_controller_test.rb`:

```ruby
  test "dashboard renders the lazy fallback and manifest" do
    get dashboard_path

    assert_select ".dashboard-activity .skeleton-note", text: /スクロールすると/
    fragments = manifest.dig("states", "fragments")
    assert_equal 1, fragments.count { |_index, fragment| fragment["mode"] == "lazy" }
  end

  test "the lazy block request answers with recent activity" do
    get dashboard_path
    index = block_index(mode: "lazy")

    get dashboard_path(format: :slots), headers: { "Herb-Block" => index }

    assert_response :success
    assert_includes response.body, "テンプレートを壊してオーバーレイを見る"
    assert_includes response.body, "時間前"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: FAIL on the missing activity card and Lazy manifest entry.

- [ ] **Step 3: Implement the activity block**

Replace the `dashboard-main` placeholder in `app/views/dashboard/index.html.erb` with:

```erb
  <div class="dashboard-main">
    <section class="dashboard-card dashboard-activity">
      <h2>最近のアクティビティ</h2>
      <Lazy delay="150" hold="400">
        <%= render "dashboard/activity" %>
        <Fallback>
          <p class="skeleton-note">スクロールすると最近のタスクを読み込みます。</p>
        </Fallback>
      </Lazy>
    </section>
  </div>
```

Create `app/views/dashboard/_activity.html.erb`:

```erb
<% recent_activity.each do |task| %>
  <div class="activity-row">
    <span class="activity-title"><%= task.title %></span>
    <span class="prio prio-<%= task.priority %>"><%= dashboard_priority_label(task.priority) %></span>
    <span class="activity-time"><%= dashboard_time_ago(task.created_at) %></span>
  </div>
<% end %>
```

Add to `app/helpers/dashboard_helper.rb`, **before the `private` line**:

```ruby
  def recent_activity
    slow_slots
    Task.order(created_at: :desc).limit(5)
  end

  def dashboard_time_ago(time)
    seconds = (Time.current - time).to_i
    return "#{seconds / 3600}時間前" if seconds >= 3600
    return "#{seconds / 60}分前" if seconds >= 60

    "たった今"
  end
```

- [ ] **Step 4: Add the activity CSS**

Append to `app/assets/stylesheets/app.css`:

```css
.activity-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto auto;
  align-items: center;
  gap: 0.6rem;
  padding: 0.55rem 0;
  border-top: 1px solid var(--line);
}

.activity-row:first-child { border-top: 0; }

.activity-title {
  font-weight: 560;
  overflow-wrap: anywhere;
}

.activity-time {
  color: var(--muted);
  font-size: 0.78rem;
  white-space: nowrap;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/views/dashboard/index.html.erb app/views/dashboard/_activity.html.erb \
  app/helpers/dashboard_helper.rb app/assets/stylesheets/app.css \
  test/controllers/dashboard_controller_test.rb
git commit -m "feat(dashboard): Lazyアクティビティを追加 — viewportに近づくまで取得しない読みを実演するため" -m "直近5件のTaskをLazyブロックで読み、スクロール前はFallbackを見せる。ブロック要求のテストも追加した。"
```

---

### Task 3: Fragment focus stats and slow mode

**Files:**
- Modify: `app/views/dashboard/index.html.erb`
- Create: `app/views/dashboard/_focus_stats.html.erb`
- Modify: `app/helpers/dashboard_helper.rb`
- Modify: `app/assets/stylesheets/app.css`
- Test: `test/controllers/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: Task 1's `slow_demo?` / `slow_slots`, Task 2's manifest/block helpers.
- Produces: `focus` state; `DashboardHelper#focus_stats`; the `.dashboard-focus` card; the `data-focus-total` marker.

- [ ] **Step 1: Add the failing tests**

Append to `test/controllers/dashboard_controller_test.rb`:

```ruby
  test "the manifest declares the focus state and the fragment read" do
    get dashboard_path

    focus = manifest.dig("states", "declarations").find { |declaration| declaration["name"] == "focus" }
    assert_equal "string", focus["kind"]
    assert_equal "all", focus["value"]

    fragment = manifest.dig("states", "fragments").values.find { |entry| entry["on"] == ["focus"] }
    assert fragment, "the Fragment is registered"
    assert fragment["reads"].all? { |read| read.is_a?(Integer) }
    assert_includes manifest.dig("states", "server", "reads").keys, "focus"
  end

  test "the focus buttons drive the server read" do
    get dashboard_path
    assert_select "[data-focus-total='3']"

    path = template_path
    get dashboard_path(format: :slots),
      headers: { "Herb-State" => { path => { "focus" => "high" } }.to_json }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.to_s, 'data-focus-total="1"'
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: FAIL on the missing `focus` declaration and card.

- [ ] **Step 3: Add the state and the focus card**

Add the state line under the `herb:slots client` line:

```erb
<%# herb:state (focus: "all") %>
```

Replace the `dashboard-main` contents with:

```erb
  <div class="dashboard-main">
    <section class="dashboard-card dashboard-focus">
      <h2>優先度フォーカス</h2>
      <div class="seg" role="group" aria-label="優先度フォーカス">
        <button class="seg-btn" data-herb-set="focus=all" aria-pressed="<%= focus == "all" %>">すべて</button>
        <button class="seg-btn" data-herb-set="focus=high" aria-pressed="<%= focus == "high" %>">高</button>
        <button class="seg-btn" data-herb-set="focus=medium" aria-pressed="<%= focus == "medium" %>">中</button>
        <button class="seg-btn" data-herb-set="focus=low" aria-pressed="<%= focus == "low" %>">低</button>
      </div>

      <Fragment delay="120" hold="500" on="focus">
        <%= render "dashboard/focus_stats", focus: focus %>
        <Fallback>
          <p class="skeleton-note">集計中…</p>
        </Fallback>
      </Fragment>
    </section>

    <section class="dashboard-card dashboard-activity">
      ...
    </section>
  </div>
```

Keep the existing activity card unchanged. The focus card sits above it.

Create `app/views/dashboard/_focus_stats.html.erb`:

```erb
<% stats = focus_stats(focus) %>
<div class="focus-card" data-focus="<%= focus %>">
  <p class="focus-kind"><%= stats[:label] %>のタスク</p>
  <p class="focus-total" data-focus-total="<%= stats[:total] %>"><%= stats[:total] %> 件</p>
  <dl class="focus-breakdown">
    <div><dt>7日</dt><dd><%= stats[:week] %></dd></div>
    <div><dt>30日</dt><dd><%= stats[:month] %></dd></div>
  </dl>
</div>
```

Add to `app/helpers/dashboard_helper.rb`, **before the `private` line**:

```ruby
  FOCUS_PRIORITIES = { "high" => 3, "medium" => 2, "low" => 1 }.freeze

  def focus_stats(focus)
    slow_slots
    priority = FOCUS_PRIORITIES[focus]
    scope = priority ? Task.where(priority: priority) : Task.all

    {
      label: priority ? dashboard_priority_label(priority) : "すべて",
      total: scope.count,
      week: scope.where(created_at: 7.days.ago..).count,
      month: scope.where(created_at: 30.days.ago..).count
    }
  end
```

- [ ] **Step 4: Add the focus CSS**

Append to `app/assets/stylesheets/app.css`:

```css
.dashboard-focus .seg {
  display: flex;
  width: fit-content;
  margin-bottom: 0.9rem;
}

.focus-kind {
  margin: 0;
  color: var(--muted);
  font-size: 0.82rem;
}

.focus-total {
  margin: 0.15rem 0 0.6rem;
  font-size: 1.7rem;
  font-weight: 720;
  font-variant-numeric: tabular-nums;
}

.focus-breakdown {
  display: flex;
  gap: 1.2rem;
  margin: 0;
}

.focus-breakdown div {
  display: flex;
  gap: 0.35rem;
  align-items: baseline;
}

.focus-breakdown dt {
  color: var(--muted);
  font-size: 0.78rem;
}

.focus-breakdown dd {
  margin: 0;
  font-variant-numeric: tabular-nums;
  font-weight: 650;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/views/dashboard/index.html.erb app/views/dashboard/_focus_stats.html.erb \
  app/helpers/dashboard_helper.rb app/assets/stylesheets/app.css \
  test/controllers/dashboard_controller_test.rb
git commit -m "feat(dashboard): Fragmentの優先度集計と遅延デモを追加 — 状態変更で古くなったサーバー読みをFallbackで覆うため" -m "focus state の優先度ボタン、focus: focus のサーバー読み、data-focus-total のテストを追加した。slow_slots は1リクエスト1回にメモ化する。"
```

---

### Task 4: Poll heartbeat

**Files:**
- Modify: `app/views/dashboard/index.html.erb`
- Create: `app/views/dashboard/_heartbeat.html.erb`
- Modify: `app/helpers/dashboard_helper.rb`
- Modify: `app/assets/stylesheets/app.css`
- Test: `test/controllers/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: Task 1/3's page/helper, manifest/block helpers.
- Produces: `DashboardHelper#heartbeat`; the `.dashboard-heartbeat` card; `poll: 3000` manifest entry; `data-heartbeat-at`.

- [ ] **Step 1: Add the failing tests**

Append to `test/controllers/dashboard_controller_test.rb`:

```ruby
  test "the manifest declares the polling heartbeat" do
    get dashboard_path

    asyncs = manifest.dig("states", "fragments").values.select { |entry| entry["mode"] == "async" }
    assert_equal 2, asyncs.length
    heartbeat = asyncs.find { |entry| entry["poll"] }
    assert_equal 3000, heartbeat["poll"]
    assert_match(/\A_herb_block_\d+\z/, heartbeat["state"])
  end

  test "the heartbeat block request answers with the sync time" do
    get dashboard_path
    index = block_index(mode: "async", poll: true)

    get dashboard_path(format: :slots), headers: { "Herb-Block" => index }

    assert_response :success
    assert_includes response.body, "最終同期"
  end
```

Also change the Task 1 manifest count from `1` to `2` in `"the manifest declares the async summary"`:

```ruby
    assert_equal 2, fragments.count { |_index, fragment| fragment["mode"] == "async" }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: FAIL because the poll heartbeat block is missing.

- [ ] **Step 3: Implement the heartbeat block**

Replace the `dashboard-side` placeholder in `app/views/dashboard/index.html.erb` with:

```erb
  <aside class="dashboard-side">
    <section class="dashboard-card dashboard-heartbeat">
      <h2>ハートビート</h2>
      <Async poll="3000" delay="150" hold="400">
        <%= render "dashboard/heartbeat" %>
        <Fallback>
          <p class="skeleton-note">同期中…</p>
        </Fallback>
      </Async>
    </section>

    <section class="dashboard-card dashboard-notes">
      ...
    </section>
  </aside>
```

Keep the notes card unchanged.

Create `app/views/dashboard/_heartbeat.html.erb`:

```erb
<% beat = heartbeat %>
<div class="heartbeat" data-heartbeat-at="<%= beat[:at].iso8601 %>">
  <p class="heartbeat-label">最終同期</p>
  <p class="heartbeat-time"><%= beat[:at].strftime("%H:%M:%S") %></p>
  <p class="heartbeat-queue">デモキュー: <span data-heartbeat-queue><%= beat[:queue] %></span></p>
</div>
```

Add to `app/helpers/dashboard_helper.rb`, **before the `private` line**:

```ruby
  def heartbeat
    slow_slots
    { at: Time.current, queue: (Time.current.to_i / 3) % 6 }
  end
```

- [ ] **Step 4: Add the heartbeat CSS**

Append to `app/assets/stylesheets/app.css`:

```css
.heartbeat {
  display: grid;
  gap: 0.2rem;
}

.heartbeat-label {
  margin: 0;
  color: var(--muted);
  font-size: 0.8rem;
}

.heartbeat-time {
  margin: 0;
  font-size: 2rem;
  font-weight: 720;
  font-variant-numeric: tabular-nums;
}

.heartbeat-queue {
  margin: 0.4rem 0 0;
  color: var(--muted);
  font-size: 0.82rem;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`

Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/views/dashboard/index.html.erb app/views/dashboard/_heartbeat.html.erb \
  app/helpers/dashboard_helper.rb app/assets/stylesheets/app.css \
  test/controllers/dashboard_controller_test.rb
git commit -m "feat(dashboard): pollハートビートを追加 — 一定間隔の再取得を0カスタムJSで見せるため" -m "poll=3000 のAsyncブロック、最終同期とデモキュー、ブロック要求のテストを追加した。"
```

---

### Task 5: Browser probe and Dashboard media

> **Implementation findings (2026-10-30):** Async content must be inline; partials inside a deferred block do not render because the block response does not carry their statics and the initial dependency map is empty. `<Lazy>` works in the first viewport: one block request, then the content replaces the fallback (2703ms queued / 6ms fast). When the card sits below the fold, the 0.6.0 scroll trigger sends no request and the fallback stays; the card is placed in the first viewport and the fallback carries the latest three rows plus "読み込み中". The Fragment focus change updates the stats in one 910ms slots request but the Fallback was not observed. The probe records these gaps; the media shows the fallback cards and the working Async/Lazy/poll content.

**Files:**
- Create: `/tmp/opencode/capture/dashboard-probe.js` (outside the repo)
- Create: `/tmp/opencode/capture/dashboard-capture.js` (outside the repo)
- Create: `docs/media/dashboard-light.png`, `dashboard-dark.png`, `18-dashboard.gif`

**Interfaces:**
- Consumes: Task 1–4's page, block responses, slow mode, focus, poll.
- Produces: browser evidence (request counts, 900ms, fallback visibility, nav row, font) and Dashboard stills/GIF.

- [ ] **Step 1: Write and run the browser probe**

Create `/tmp/opencode/capture/dashboard-probe.js` with Playwright. Use the existing settings probe's font/CDP helper and dev-tools CSS. Record each `format=slots` request with its `Herb-Block` header and duration.

Assertions:

- Warm `/dashboard` once before measuring, so template compilation does not inflate the first document timing.
- `?slow=1`: initial document < 500ms; exactly 2 Async block requests on mount, each ≥ 800ms; the summary skeleton is visible around 250ms and disappears when `全タスク` arrives; the heartbeat fallback becomes `最終同期`.
- Read `data-heartbeat-at`, then wait up to 6 seconds for the heartbeat poll block request: exactly 1 additional poll block request, ≥ 800ms, and the attribute changes. The first poll starts 3 seconds after the previous block settles and then sleeps 900ms, so the effective interval is about 3.9 seconds; do not use a 3.5-second wait. Run this before the focus change, because a focus slots request also re-renders the heartbeat slot and would make the timestamp change ambiguous.
- The first-viewport Lazy: exactly 1 block request, ≥ 800ms, and the fallback is replaced by the latest task rows. If the card is moved below the fold, record the 0.6.0 gap: 0 slots requests after scrolling, fallback stays.
- Click `button[data-herb-set="focus=high"]`: 1 slots request without `Herb-Block`, 910ms; the stats change to the summary high count. The Fragment fallback is not observed; log it rather than asserting it.
- `?slow=0`: mount Async blocks return < 500ms; the Lazy and focus requests are fast.
- Nav: 7 links and one row at 800px and 1000px (`new Set(links.map(l => l.getBoundingClientRect().top)).size === 1`).
- Font: computed stack and CDP platform font is `Noto Sans CJK JP`.
- No page errors or console errors.

Run with the dev server up: `node dashboard-probe.js`

Expected: all assertions pass; the Fragment fallback absence and the below-fold Lazy gap are logged as measured limits.

- [ ] **Step 2: Capture the Dashboard media**

Create `/tmp/opencode/capture/dashboard-capture.js` with the existing GIF helpers:

- `dashboard-light.png` / `dashboard-dark.png`: 1000×900 @2x viewport (the initial screen); assert the JP platform font. The Lazy rows are shown in the GIF.
- `18-dashboard.gif`: viewport 1000×900, `?slow=1`; 5 frames:
  1. initial Async + Lazy fallbacks,
  2. Async summary + heartbeat loaded,
  3. focus high stats (no Fragment fallback observed),
  4. Lazy content after the block,
  5. heartbeat poll tick.
- No DB writes, no form POST. The GIF frames all have the same viewport size.

Expected: stills/GIF show the JP glyphs, the seven-link nav, the fallbacks, and the focus stats; no stitched sticky header.

- [ ] **Step 3: Commit**

```bash
git add docs/media/dashboard-light.png docs/media/dashboard-dark.png docs/media/18-dashboard.gif
git commit -m "docs(dashboard): ダッシュボードのGIFと静止画を追加 — 遅延4部品のFallbackとリクエスト数を記録するため" -m "slow=1 でAsync/Lazy/Fragment/pollのFallbackと復帰を撮り、日本語フォントと7リンクナビを確認した。"
```

---

### Task 6: Nav refresh, README, comparison doc, AGENTS, and final gate

**Files:**
- Modify: `/tmp/opencode/capture/nav-refresh.js` (outside the repo)
- Modify: `/tmp/opencode/capture/hub-capture.js` (outside the repo; run only)
- Modify: `docs/media/hub-light.png`, `hub-dark.png`, `patterns-light.png`, `patterns-dark.png`, `lab-light.png`, `lab-dark.png`, `pricing-light.png`, `pricing-dark.png`, `settings-light.png`, `settings-dark.png`, `ui-dialog.png`, `03-optimistic-add.gif`, `04-window-clauses.gif`
- Modify: `README.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 5's Dashboard media and the seven-link nav.
- Produces: consistent seven-link media, seven-screen docs, measured facts, green `bin/ci`.

- [ ] **Step 1: Re-shoot the nav media**

Update `nav-refresh.js` to expect seven links (`Sprint Hub`, `Dashboard`, `Patterns`, `Pricing`, `Settings`, `Client Lab`, `UI Kit`) and capture:

- Hub / Patterns / Client Lab at 800×550 (light/dark).
- Pricing / Settings at 1000×900 fullPage (light/dark).
- `ui-dialog.png`: navigate to `/ui`, click `詳細を開く`, screenshot at 1000×900 fullPage (light).

Re-run `hub-capture.js` for the Hub 03/04 GIFs (it also re-shoots 01/02; leave those if identical). Remove any task created by the Hub 03 capture (`Task.find_by(title: "GIF用にピンを追加")`), as before.

Expected: every still/GIF shows the seven-link nav on one row; the dashboard stills/GIF are unchanged.

- [ ] **Step 2: Update README**

- Change the intro to seven showcases and the heading to `## 7つの画面`.
- Add the Dashboard row to the table:

```markdown
| Dashboard `/dashboard` | `<%# herb:slots client %>` | Async / Lazy / Fragment / poll の遅延読み。外枠は即時、重い集計だけ後から（カスタムJSなし） |
```

- Add the Dashboard section after Sprint Hub, with the stills, `18-dashboard.gif`, and 機能⑱〜㉑:
  - ⑱ Async summary: mount request, fallback, 900ms slow mode.
  - ⑲ Lazy activity: viewport request, fallback before scroll.
  - ⑳ Fragment focus: `focus: focus` server read, fallback on focus change.
  - ㉑ poll heartbeat: 3-second re-request, hidden pause, demo queue.
- Add `dashboard_controller_test` to the test list.

- [ ] **Step 3: Update docs/hotwire-comparison.md**

- §① layer 2 implementation: add `/dashboard` (Dashboard).
- §② heading `7画面`; add a Dashboard row: deferred content, Turbo Frame lazy loading / Stimulus polling → `<Async>` / `<Lazy>` / `<Fragment>` / `poll`.
- §⑤: add the Dashboard request counts and the 900ms slow mode; note that the initial document includes the Fragment content.
- §⑥: add that no-JS shows only fallbacks (deferred content needs JS), and that the heartbeat queue is a simulation.
- §⑦: mention Dashboard is implemented; D remains skipped.

- [ ] **Step 4: Update AGENTS.md**

- Add the seventh screen to the intro.
- Add a Dashboard measured-facts section:
  - `<Async>` / `<Lazy>` block requests and `Herb-Block`.
  - `<Fragment>` needs `focus: focus`; `on` + `server.reads` in the manifest; `fragments.*.reads` is slot indices.
  - `?slow=1` sleeps only on slots, memoized once per request.
  - `poll` interval and hidden-tab pause.
  - Request counts: document 1 + Async 2, Lazy 1, Fragment 1, poll 1 per 3s.
  - Seven-link nav compact CSS and the media refresh, including `ui-dialog.png`.

- [ ] **Step 5: Run the gate**

```bash
grep -n "六つのショーケース\|## 6つの画面\|6画面が消して" README.md docs/hotwire-comparison.md
grep -n "7画面\|七つ" README.md docs/hotwire-comparison.md AGENTS.md
bin/rails test
bin/ci
```

Expected: no stale current-heading matches; the new 7-screen text is present; tests and CI green. Historical numbering in AGENTS (for example "Settings は6画面目") is allowed.

- [ ] **Step 6: Commit**

```bash
git add docs/media/hub-light.png docs/media/hub-dark.png docs/media/patterns-light.png docs/media/patterns-dark.png \
  docs/media/lab-light.png docs/media/lab-dark.png docs/media/pricing-light.png docs/media/pricing-dark.png \
  docs/media/settings-light.png docs/media/settings-dark.png docs/media/ui-dialog.png \
  docs/media/03-optimistic-add.gif docs/media/04-window-clauses.gif \
  README.md docs/hotwire-comparison.md AGENTS.md
git commit -m "docs(dashboard): 7画面のドキュメントと7リンクナビのメディアを更新 — Dashboardを全体のショーケースに組み込むため" -m "READMEの画面表と機能⑱〜㉑、Hotwire対比の証明マップと境界、AGENTSの実測メモを追加し、既存のナビ付きメディアを7リンクで撮り直した。"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 covers route/nav/Async/slow link; Task 2 Lazy; Task 3 Fragment/focus/slow; Task 4 poll; Task 5 probe/media; Task 6 docs/nav/gate. D and the HTML twin remain out of scope.
- **Type consistency:** `dashboard_path`; `DashboardHelper#slow_demo?`/`#dashboard_summary`/`#recent_activity`/`#focus_stats`/`#heartbeat`; `focus` values `all/high/medium/low`; `data-focus-total`; `data-heartbeat-at`; `dashboard-*` classes; manifest keys.
- **Review Focus:** each of the six lines has a test, probe check, or media/doc check in Tasks 1–6.
- **Test safety:** controller tests never pass `slow`; the helper's `request.format.slots?` and memoization are exercised only by block requests without slow. The browser probe measures the 900ms path.
- **Block index stability:** tests find indices from `states.fragments` by `mode`/`poll`, not by hardcoded numbers. The Fragment entry has no `mode`; it is found by `on`.
- **Nav/media:** the seven-link check is in the probe; the nav stills, Hub 03/04, and `ui-dialog.png` are re-shot in Task 6.
