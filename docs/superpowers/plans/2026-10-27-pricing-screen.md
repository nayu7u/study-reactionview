# Pricing Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/pricing` as the fifth showcase: a SaaS quote calculator where Ruby keeps the money math and the browser updates only the breakdown.

**Architecture:** A server-mode template declares four browser states (`plan`, `seats`, `annual`, `support`). The controller reads them with `herb_state`, computes the quote with integer arithmetic, and the view renders the money lines as `data-herb-name` READ slots. Each state is read by at least one conditional so it rides the steering header; the seats stepper adds `$refresh` because its `seats >= 10` branch does not flip on every click.

**Tech Stack:** Rails 8.1, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest integration tests, plain CSS.

**Spec:** `docs/superpowers/specs/2026-10-27-pricing-screen-design.md`

## Global Constraints

- `.html.erb` templates only. No custom JavaScript, Stimulus, Turbo, Node, yarn, Tailwind, or build step.
- Server mode (`<%# herb:slots server %>`). No DB model, migration, persistence, checkout, or authentication.
- Plan prices: Starter ¥1,200/seat/month, Team ¥2,400/seat/month, Business ¥4,000/seat/month.
- Volume discount: 10% off the seat fee at 10 or more seats. Annual discount: 15% off the 12-month subtotal. Priority support: +¥10,000/month flat. Consumption tax: 10%.
- Seat range: 1..50. Defaults: `plan: "team"`, `seats: 5`, `annual: false`, `support: false`.
- Money is Integer yen throughout. Use integer division; floor every discount and tax. No Float money.
- State kinds: `plan` String, `seats` Integer, `annual` Boolean, `support` Boolean.
- State comparisons are literals only. Never compare a state to a loop variable or a helper result.
- `seats` is the only control that composes `data-herb-action="$refresh"`; plan, annual, and support rely on a branch flip.
- READ slot names: `base_fee`, `volume_discount`, `support_fee`, `subtotal`, `annual_discount`, `discounted`, `tax`, `total`.
- No-JS recalculation is out of scope. The initial page must still render. Say so in the screen note.
- No `<Async>`, `<Lazy>`, `<Fragment>`, or polling. Those are a later theme.
- Japanese prose in README, docs, and commit messages goes through the yomiyasu skill. Commit messages record Why.

## Review Focus

These are the inputs and boundaries most likely to bite, with the task that pins each one.

1. **Crafted `Herb-State` outside the UI**: seats 0, negative, or over 50; unknown plan; `annual`/`support` as strings. Expected: no 500, clamp to 1..50, fall back to Team, accept only `true`/`"true"` as true. Pinned by Task 1's "unknown plan…" and "string boolean states" tests.
2. **Fractional tax**: a quote whose 10% tax has a fraction must floor, not round half-up. Expected: Starter / 11 seats / annual / support gives tax ¥22,317 and total ¥245,493. Pinned by Task 1's "tax rounds down" test.
3. **Volume threshold boundary**: exactly 10 seats gets the discount; 9 does not. Expected: 10 shows the discount line and ¥2,400 for Team 10; 9 shows the hint instead. Pinned by Task 2's "volume discount branch flips at ten seats" test.
4. **Combined discounts and add-on**: annual + volume + support must compose in the documented order. Expected: Business / 12 seats / annual / support gives ¥4,800 volume, ¥95,760 annual, ¥10,000 support, ¥54,264 tax, ¥596,904 total. Pinned by Task 2's "breakdown carries every money line" test.
5. **Seats steering**: if `seats` is not read by a conditional, the `$refresh` request omits it and the total stays stale. Expected: the manifest's conditionals include `seats`, and the browser request header includes `seats`. Pinned by Task 2's manifest test and the browser check.

---

## File Structure

- `config/routes.rb` — add the `/pricing` GET route.
- `app/controllers/application_controller.rb` — shared `integer_state` and `boolean_state` casts.
- `app/controllers/patterns_controller.rb` — remove the now-shared private `integer_state`.
- `app/controllers/pricing_controller.rb` — pricing constants, state reads, quote calculation.
- `app/views/pricing/index.html.erb` — server-mode template, controls, branches, READ slots.
- `app/views/layouts/application.html.erb` — add the Pricing nav link.
- `app/assets/stylesheets/app.css` — pricing layout, plan cards, price lines, nav wrap.
- `test/controllers/pricing_controller_test.rb` — calculation, UI contract, manifest, branch responses.
- `README.md`, `docs/hotwire-comparison.md`, `AGENTS.md` — five-screen documentation and measured facts.

---

### Task 1: Server-side quote calculation and route

**Files:**
- Create: `app/controllers/pricing_controller.rb`
- Create: `app/views/pricing/index.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/patterns_controller.rb`
- Test: `test/controllers/pricing_controller_test.rb`

**Interfaces:**
- Consumes: `herb_state` (ReActionView) and the existing `ApplicationController`.
- Produces: `pricing_path`; `PricingController::PLANS`; `PricingController#index` setting `@plan`, `@plans`, `@seats`, `@annual`, `@support`, `@seat_fee`, `@volume_discount`, `@support_fee`, `@months`, `@subtotal`, `@annual_discount`, `@discounted`, `@tax`, `@total`; `ApplicationController#integer_state(name, default) -> Integer`; `ApplicationController#boolean_state(name, default) -> Boolean`; a `.price-total` element with `data-herb-name="total"` and a tax element with `data-herb-name="tax"`.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/pricing_controller_test.rb`:

```ruby
require "test_helper"

# What is covered here: the Pricing screen contract — server-side quote
# calculation for plans, volume discount, annual discount, support and tax.
# The interactive controls and steering are added in Task 2.
class PricingControllerTest < ActionDispatch::IntegrationTest
  TEMPLATE = "app/views/pricing/index.html.erb"

  def slots(state)
    get pricing_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { TEMPLATE => state }.to_json
    }
  end

  test "index renders the default quote" do
    get pricing_path

    assert_response :success
    assert_select "h1", "Pricing"
    assert_select ".price-total", text: /¥13,200/
  end

  test "the default slots answer carries the server-calculated total" do
    slots({ "plan" => "team", "seats" => 5, "annual" => false, "support" => false })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥13,200"
  end

  test "business, 12 seats, annual and support total is calculated server-side" do
    slots({ "plan" => "business", "seats" => 12, "annual" => true, "support" => true })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥596,904"
  end

  test "annual without support total is calculated server-side" do
    slots({ "plan" => "team", "seats" => 5, "annual" => true, "support" => false })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥134,640"
  end

  test "unknown plan falls back to team and seats clamp to the range" do
    slots({ "plan" => "nope", "seats" => 999, "annual" => false, "support" => false })

    assert_response :success
    # Team 50 seats monthly: 120,000 - 12,000 = 108,000; tax 10,800; total 118,800.
    assert_includes JSON.parse(response.body)["slots"].values, "¥118,800"

    slots({ "plan" => "starter", "seats" => 0, "annual" => false, "support" => false })

    assert_response :success
    # Starter 1 seat monthly: 1,200; tax 120; total 1,320.
    assert_includes JSON.parse(response.body)["slots"].values, "¥1,320"
  end

  test "string boolean states are read defensively" do
    slots({ "plan" => "team", "seats" => 5, "annual" => "true", "support" => "false" })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥134,640"
  end

  test "tax rounds down at the yen boundary" do
    slots({ "plan" => "starter", "seats" => 11, "annual" => true, "support" => true })

    assert_response :success
    # 21,880 monthly × 12 = 262,560; -15% = 223,176; tax 22,317.6 floors to 22,317.
    assert_includes JSON.parse(response.body)["slots"].values, "¥22,317"
    assert_includes JSON.parse(response.body)["slots"].values, "¥245,493"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/pricing_controller_test.rb`

Expected: FAIL because `pricing_path` and `PricingController` do not exist.

- [ ] **Step 3: Add the route and the shared state casts**

In `config/routes.rb`, after `get "/patterns", to: "patterns#index"`, add:

```ruby
  get "/pricing", to: "pricing#index"
```

In `app/controllers/application_controller.rb`, add before the final `end`:

```ruby
  private

  # herb_state returns the raw JSON value from the header untyped (the real
  # client type-checks literals against the declaration kind, but a crafted
  # header may send "12" as a string), so browser-supplied numbers are cast
  # defensively instead of calling Integer-only methods on them.
  def integer_state(name, default)
    Integer(herb_state(name, default))
  rescue TypeError, ArgumentError
    default
  end

  # A crafted header can send "true"/"false" as strings; only the Boolean
  # literal and its string form mean true.
  def boolean_state(name, default)
    value = herb_state(name, default)
    value == true || value == "true"
  end
```

In `app/controllers/patterns_controller.rb`, delete the private `integer_state` method (including its comment) and the now-empty `private` line. The controller keeps `priority_label` and `index`.

- [ ] **Step 4: Implement `PricingController#index`**

Create `app/controllers/pricing_controller.rb`:

```ruby
class PricingController < ApplicationController
  PLANS = {
    "starter" => { label: "Starter", price: 1_200, blurb: "小さく始める" },
    "team" => { label: "Team", price: 2_400, blurb: "チームで使う" },
    "business" => { label: "Business", price: 4_000, blurb: "統制と安心" }
  }.freeze

  SEAT_MIN = 1
  SEAT_MAX = 50
  VOLUME_THRESHOLD = 10
  VOLUME_PERCENT = 10
  ANNUAL_PERCENT = 15
  TAX_PERCENT = 10
  SUPPORT_FEE = 10_000

  def index
    requested_plan = herb_state("plan", "team")
    plan_key = PLANS.key?(requested_plan) ? requested_plan : "team"
    @plan = PLANS.fetch(plan_key)
    @plans = PLANS

    @seats = integer_state("seats", 5).clamp(SEAT_MIN, SEAT_MAX)
    @annual = boolean_state("annual", false)
    @support = boolean_state("support", false)

    @seat_fee = @plan[:price] * @seats
    @volume_discount = @seats >= VOLUME_THRESHOLD ? @seat_fee * VOLUME_PERCENT / 100 : 0
    @support_fee = @support ? SUPPORT_FEE : 0
    monthly_subtotal = @seat_fee - @volume_discount + @support_fee
    @months = @annual ? 12 : 1
    @subtotal = monthly_subtotal * @months
    @annual_discount = @annual ? @subtotal * ANNUAL_PERCENT / 100 : 0
    @discounted = @subtotal - @annual_discount
    @tax = @discounted * TAX_PERCENT / 100
    @total = @discounted + @tax
  end
end
```

- [ ] **Step 5: Add the minimal server-mode view**

Create `app/views/pricing/index.html.erb`:

```erb
<%# herb:slots server %>
<%# herb:state (plan: "team", seats: 5, annual: false, support: false) %>

<section class="hero">
  <div class="hero-badge">Server mode — 金額はサーバーが計算</div>
  <h1>Pricing</h1>
  <p class="hero-sub">プランと席数を選ぶと、見積もりをサーバーが計算し直します。</p>
</section>

<section class="feature" data-feature="pricing">
  <span class="feature-tag">機能⑮ サーバー計算の見積もり</span>
  <h2>見積もり</h2>
  <p class="toolbar-note">
    初期値: <%= plan %> / <%= seats %>席 /
    <% if annual %>年払い<% else %>月払い<% end %> /
    サポート<% if support %>あり<% else %>なし<% end %>
  </p>
  <p class="price-total" aria-live="polite" data-herb-name="total"><%= number_to_currency(@total, unit: "¥", precision: 0) %></p>
  <p class="toolbar-note">消費税: <span data-herb-name="tax"><%= number_to_currency(@tax, unit: "¥", precision: 0) %></span></p>
</section>
```

The temporary summary line reads all four states so the compiler does not treat them as unused; Task 2 replaces it with the actual controls.

- [ ] **Step 6: Run the new test to verify it passes**

Run: `bin/rails test test/controllers/pricing_controller_test.rb`

Expected: PASS, 7 runs.

- [ ] **Step 7: Run the existing Patterns test to verify the helper move**

Run: `bin/rails test test/controllers/patterns_controller_test.rb`

Expected: PASS. The shared `integer_state` behaves exactly as before.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/application_controller.rb app/controllers/patterns_controller.rb app/controllers/pricing_controller.rb app/views/pricing/index.html.erb test/controllers/pricing_controller_test.rb
git commit -m "5画面目 Pricing の計算を追加 — 金額計算をサーバーに残す土台にするため" -m "料金表・席数・年払い・サポートの計算をコントローラに置き、slots 応答では合計を READ slot で返す。integer_state/boolean_state は ApplicationController に移した。"
```

---

### Task 2: Interactive pricing UI, steering, styles, and navigation

**Files:**
- Modify: `app/views/pricing/index.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Modify: `app/views/layouts/application.html.erb`
- Test: `test/controllers/pricing_controller_test.rb`

**Interfaces:**
- Consumes: Task 1's `PricingController#index` ivars, `pricing_path`, and READ slot names.
- Produces: plan cards with `data-herb-set="plan=starter|team|business"`; seats stepper with `data-herb-decrement="seats"` / `data-herb-increment="seats"` plus `data-herb-action="$refresh"`; annual buttons with `data-herb-set="annual=false|true"`; support checkbox with `checked="<%= support %>"`; money lines named `base_fee`, `volume_discount`, `support_fee`, `subtotal`, `annual_discount`, `discounted`, `tax`, `total`; a `.site-nav` link to `pricing_path`.

- [ ] **Step 1: Add the failing UI and manifest tests**

Append to `test/controllers/pricing_controller_test.rb`:

```ruby
  test "index renders the plan controls, the seat stepper and the billing toggle" do
    get pricing_path

    assert_response :success
    assert_select ".plan-card", count: 3
    assert_select 'button.plan-card[data-herb-set="plan=starter"]'
    assert_select 'button.plan-card[data-herb-set="plan=team"]'
    assert_select 'button.plan-card[data-herb-set="plan=business"]'
    assert_select '.plan-card[aria-pressed="true"]', count: 1
    assert_select 'button[data-herb-decrement="seats"][data-herb-action="$refresh"]'
    assert_select 'button[data-herb-increment="seats"][data-herb-action="$refresh"]'
    assert_select 'button[data-herb-set="annual=false"]'
    assert_select 'button[data-herb-set="annual=true"]'
    assert_select 'input[type="checkbox"]', count: 1
    assert_select ".price-total", text: /¥13,200/
  end

  test "the site navigation links to pricing" do
    get pricing_path

    assert_select ".site-nav a[href=?]", pricing_path, text: "Pricing"
  end

  test "the manifest carries the four states and their steering conditionals" do
    get pricing_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    manifest = JSON.parse(json).values.first

    names = manifest.dig("states", "declarations").map { |d| d["name"] }
    %w[plan seats annual support].each { |name| assert_includes names, name }

    conditions = manifest.dig("states", "conditionals").values
      .flat_map { |c| Array(c["arms"]) }
      .map { |a| a["condition"]&.first }
      .compact
    %w[plan seats annual support].each { |name| assert_includes conditions, name }

    presence_states = manifest.dig("states", "presence").values
      .select { |p| p.is_a?(Array) }
      .map(&:first)
    assert_includes presence_states, "seats"
    assert_includes presence_states, "support"
  end

  test "the plan branch answers the selected plan" do
    slots({ "plan" => "business", "seats" => 5, "annual" => false, "support" => false })

    assert_response :success
    arm = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("統制と安心")
    end
    assert arm, "the selected plan's description arm is served"
  end

  test "the volume discount branch flips at ten seats" do
    slots({ "plan" => "team", "seats" => 9, "annual" => false, "support" => false })

    under_ten = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("10席以上")
    end
    assert under_ten, "the under-ten arm is served"
    refute_includes under_ten["slots"].values, "¥2,400"

    slots({ "plan" => "team", "seats" => 10, "annual" => false, "support" => false })

    at_ten = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("ボリューム割引")
    end
    assert at_ten, "the ten-seat arm is served"
    assert_includes at_ten["slots"].values, "¥2,400"
  end

  test "the annual branch carries the discount line" do
    slots({ "plan" => "team", "seats" => 5, "annual" => true, "support" => false })

    assert_response :success
    arm = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("年払い割引")
    end
    assert arm, "the annual discount arm is served"
    assert_includes arm["slots"].values, "¥21,600"
  end

  test "the support branch carries the add-on fee" do
    slots({ "plan" => "team", "seats" => 5, "annual" => false, "support" => true })

    assert_response :success
    arm = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("優先サポート")
    end
    assert arm, "the support arm is served"
    assert_includes arm["slots"].values, "¥10,000"
  end

  test "the breakdown carries every money line for the combined quote" do
    slots({ "plan" => "business", "seats" => 12, "annual" => true, "support" => true })

    assert_response :success
    values = JSON.parse(response.body)["slots"].values
    %w[¥4,800 ¥95,760 ¥10,000 ¥54,264 ¥596,904].each do |amount|
      assert values.any? { |value| value == amount || (value.is_a?(Hash) && value["slots"]&.values&.include?(amount)) },
        "expected #{amount} in the top-level slots or a branch's slots"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/pricing_controller_test.rb`

Expected: FAIL on the missing plan cards, seat stepper, billing toggle, nav link, manifest conditionals, and branch arms.

- [ ] **Step 3: Build the view controls and branches**

Replace the `<section class="feature" data-feature="pricing">` block in `app/views/pricing/index.html.erb` with a `.split.pricing-layout` containing the controls and the summary. Use these exact attributes and branch shapes:

```erb
<div class="split pricing-layout">
  <section class="feature" data-feature="pricing">
    <span class="feature-tag">機能⑮ サーバー計算の見積もり</span>
    <h2>プランと席数</h2>

    <div class="plan-grid" role="group" aria-label="プラン">
      <button class="plan-card" data-herb-set="plan=starter" aria-pressed="<%= plan == "starter" %>">
        <span class="plan-name"><%= @plans["starter"][:label] %></span>
        <span class="plan-price"><%= number_to_currency(@plans["starter"][:price], unit: "¥", precision: 0) %><small>/席/月</small></span>
        <span class="plan-blurb"><%= @plans["starter"][:blurb] %></span>
      </button>
      <button class="plan-card" data-herb-set="plan=team" aria-pressed="<%= plan == "team" %>">
        <span class="plan-name"><%= @plans["team"][:label] %></span>
        <span class="plan-price"><%= number_to_currency(@plans["team"][:price], unit: "¥", precision: 0) %><small>/席/月</small></span>
        <span class="plan-blurb"><%= @plans["team"][:blurb] %></span>
      </button>
      <button class="plan-card" data-herb-set="plan=business" aria-pressed="<%= plan == "business" %>">
        <span class="plan-name"><%= @plans["business"][:label] %></span>
        <span class="plan-price"><%= number_to_currency(@plans["business"][:price], unit: "¥", precision: 0) %><small>/席/月</small></span>
        <span class="plan-blurb"><%= @plans["business"][:blurb] %></span>
      </button>
    </div>

    <div class="seat-row">
      <span class="field-label">席数</span>
      <div class="qty-group">
        <button data-herb-decrement="seats" data-herb-action="$refresh" aria-label="席数を減らす" disabled="<%= seats <= 1 %>">−</button>
        <span class="qty-value"><%= seats %></span>
        <button data-herb-increment="seats" data-herb-action="$refresh" aria-label="席数を増やす" disabled="<%= seats >= 50 %>">＋</button>
      </div>
      <span class="toolbar-note">1〜50席</span>
    </div>

    <nav class="seg" aria-label="請求サイクル">
      <button class="seg-btn" data-herb-set="annual=false" aria-pressed="<%= !annual %>">月払い</button>
      <button class="seg-btn" data-herb-set="annual=true" aria-pressed="<%= annual %>">年払い</button>
    </nav>

    <label class="addon-row">
      <input type="checkbox" checked="<%= support %>">
      <span>優先サポート <strong>+¥10,000/月</strong></span>
    </label>

    <p class="task-note">
      席数の増減は <code>seats &gt;= 10</code> の分岐が反転しないことがあるため、<code>$refresh</code> を合成しています。
      プラン・年払い・サポートは分岐の反転が往復を起こします。
    </p>
  </section>

  <aside class="feature pricing-summary" data-feature="pricing-summary">
    <span class="feature-tag">見積もり</span>
    <h2>お見積もり</h2>
    <p class="price-total" aria-live="polite" data-herb-name="total"><%= number_to_currency(@total, unit: "¥", precision: 0) %></p>

    <dl class="price-lines">
      <div><dt>基本料金（<%= @plan[:label] %> × <%= @seats %>席）</dt><dd data-herb-name="base_fee"><%= number_to_currency(@seat_fee, unit: "¥", precision: 0) %></dd></div>
      <% if seats >= 10 %>
        <div class="price-line-discount"><dt>ボリューム割引（10%）</dt><dd>-<span data-herb-name="volume_discount"><%= number_to_currency(@volume_discount, unit: "¥", precision: 0) %></span></dd></div>
      <% else %>
        <div class="price-line-note"><dt>ボリューム割引</dt><dd>10席以上で10%OFF</dd></div>
      <% end %>
      <% if support %>
        <div><dt>優先サポート</dt><dd data-herb-name="support_fee"><%= number_to_currency(@support_fee, unit: "¥", precision: 0) %></dd></div>
      <% end %>
      <div><dt><% if annual %>小計（<%= @months %>か月）<% else %>小計<% end %></dt><dd data-herb-name="subtotal"><%= number_to_currency(@subtotal, unit: "¥", precision: 0) %></dd></div>
      <% if annual %>
        <div class="price-line-discount"><dt>年払い割引（15%）</dt><dd>-<span data-herb-name="annual_discount"><%= number_to_currency(@annual_discount, unit: "¥", precision: 0) %></span></dd></div>
      <% end %>
      <div><dt>税抜合計</dt><dd data-herb-name="discounted"><%= number_to_currency(@discounted, unit: "¥", precision: 0) %></dd></div>
      <div><dt>消費税（10%）</dt><dd data-herb-name="tax"><%= number_to_currency(@tax, unit: "¥", precision: 0) %></dd></div>
    </dl>

    <p class="task-note">金額はすべてサーバーで計算しています。内訳は READ slot なので、同じ <code>?format=slots</code> 応答で値だけが差し替わります。JavaScript を切ると初期表示のみで、再計算はできません。</p>
  </aside>
</div>

<% if plan == "starter" %>
  <p class="toolbar-note">Starter: 小さく始めるプランです。</p>
<% elsif plan == "team" %>
  <p class="toolbar-note">Team: チームで使うプランです。</p>
<% else %>
  <p class="toolbar-note">Business: 統制と安心のプランです。</p>
<% end %>
```

Keep the hero from Task 1. Remove the temporary state summary line. The plan branch at the bottom is the conditional that puts `plan` on the steering header; the `seats >= 10`, `annual`, and `support` branches do the same for the other three states.

- [ ] **Step 4: Add the nav link**

In `app/views/layouts/application.html.erb`, add between Patterns and Client Lab:

```erb
        <%= link_to "Pricing", pricing_path %>
```

- [ ] **Step 5: Add the pricing styles**

In `app/assets/stylesheets/app.css`, add the following. Keep the existing design tokens and plain CSS.

```css
/* ---------- pricing: quote builder ---------- */

.site-nav { flex-wrap: wrap; }

.pricing-layout { align-items: start; }

.plan-grid {
  display: grid;
  gap: 0.6rem;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  margin-bottom: 1rem;
}

@media (max-width: 42rem) {
  .plan-grid { grid-template-columns: 1fr; }
}

.plan-card {
  appearance: none;
  font: inherit;
  text-align: left;
  display: grid;
  gap: 0.2rem;
  background: var(--surface-2);
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  padding: 0.8rem 0.9rem;
  cursor: pointer;
  transition: border-color 140ms ease, background 140ms ease, box-shadow 140ms ease;
}

.plan-card:hover { border-color: color-mix(in srgb, var(--accent) 45%, var(--line)); }

.plan-card[aria-pressed="true"] {
  border-color: var(--accent);
  background: var(--accent-soft);
  box-shadow: var(--ring);
}

.plan-card:focus-visible { outline: none; box-shadow: var(--ring); }

.plan-name { font-weight: 750; }
.plan-price { font-size: 1.15rem; font-weight: 700; font-variant-numeric: tabular-nums; }
.plan-price small { font-size: 0.72rem; font-weight: 500; color: var(--muted); }
.plan-blurb { font-size: 0.78rem; color: var(--muted); }

.seat-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  flex-wrap: wrap;
  margin-bottom: 1rem;
}

.addon-row {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.9rem;
  cursor: pointer;
  margin-top: 0.9rem;
}

.pricing-summary { position: sticky; top: 5.5rem; }

@media (max-width: 52rem) {
  .pricing-summary { position: static; }
}

.price-total {
  font-size: clamp(1.8rem, 5vw, 2.6rem);
  font-weight: 760;
  letter-spacing: -0.03em;
  font-variant-numeric: tabular-nums;
  margin: 0.2rem 0 0.9rem;
}

.price-lines {
  display: grid;
  gap: 0.45rem;
  margin: 0 0 0.9rem;
}

.price-lines > div {
  display: flex;
  justify-content: space-between;
  gap: 0.75rem;
  font-size: 0.88rem;
  border-bottom: 1px dashed var(--line);
  padding-bottom: 0.4rem;
}

.price-lines dt { color: var(--muted); }
.price-lines dd { margin: 0; font-variant-numeric: tabular-nums; white-space: nowrap; }
.price-line-discount dd { color: var(--ok); }
.price-line-note dd { color: var(--muted); font-weight: 500; }

.feature[data-feature="pricing"] .feature-tag { --tag: #0f766e; }
.feature[data-feature="pricing-summary"] .feature-tag { --tag: #b45309; }
```

The global bare-button selector is `button:not(.btn):not(.switch):not(.seg-btn)`. Add `.plan-card` to both exclusions so the card's padding, border, and background are not overwritten:

```css
button:not(.btn):not(.switch):not(.seg-btn):not(.plan-card) { ... }
button:not(.btn):not(.switch):not(.seg-btn):not(.plan-card):hover { ... }
```

- [ ] **Step 6: Run the pricing tests to verify they pass**

Run: `bin/rails test test/controllers/pricing_controller_test.rb`

Expected: PASS, 15 runs.

- [ ] **Step 7: Run the full test suite**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 8: Verify the browser behavior**

Start the server with `bin/rails server` and open `/pricing`. Use the browser Network panel or the existing headless Chromium setup. Check:

- Initial: Team / 5 seats / monthly / no support → ¥13,200.
- Click Business → one `GET /pricing?format=slots`; total ¥22,000.
- Click `＋` seven times (5 → 12) → one request per click; the volume line appears at 10 seats; final Business / 12 seats / monthly → ¥47,520.
- Click 年払い → ¥484,704.
- Check 優先サポート → ¥596,904.
- The last request's `Herb-State` header contains `plan`, `seats`, `annual`, and `support`.
- The page does not reload; the URL stays `/pricing`.

If the header misses `seats` or a branch value stays stale, stop and fix it before committing.

- [ ] **Step 9: Commit**

```bash
git add app/views/pricing/index.html.erb app/views/layouts/application.html.erb app/assets/stylesheets/app.css test/controllers/pricing_controller_test.rb
git commit -m "5画面目 Pricing の UI を追加 — 料金計算をサーバーに残したまま操作できるようにするため" -m "プランカード・席数ステッパー・年払い・優先サポートを state に結び、各 state を条件分岐に読ませて steering に載せる。金額は READ slot で差し替える。"
```

---

### Task 3: Five-screen documentation and final verification

**Files:**
- Modify: `README.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: the `/pricing` route, the four states, and the measured behavior from Task 2.
- Produces: README table and section, Hotwire comparison row and code comparison, AGENTS.md screen summary and measured facts.

- [ ] **Step 1: Update README.md**

Make these changes:

- Change the intro from "四つのショーケース" to "五つのショーケース".
- Change `## 4つの画面` to `## 5つの画面`.
- Add this table row after Patterns:

```markdown
| Pricing `/pricing` | `<%# herb:slots server %>` | サーバーが計算する見積もり、steering、READ slot |
```

- Add a `## Pricing（server モード、`/pricing`）` section after the Patterns section. Explain in Japanese:
  - Plan / seats / annual / support are browser states.
  - Ruby computes the quote; the response carries only the breakdown values.
  - `seats` composes `$refresh` because `seats >= 10` does not flip on every click; the other controls rely on branch flips.
  - The money lines are READ slots; no pricing formula is written in JavaScript.
  - No-JS recalculation is out of scope; the initial page still renders.
  - Include a short code snippet with the state declaration and the total slot.
- In "検証の進め方", add `pricing_controller_test` to the list of test files.
- Do not add a GIF or screenshot; note that media capture is a follow-up if needed.

- [ ] **Step 2: Update docs/hotwire-comparison.md**

- Replace the "4画面" / "四つ" screen-count references with five where they describe the current app. Leave historical notes alone.
- Add a Pricing row to the §② proof map:

```markdown
| **Pricing** (`/pricing`) | server | プラン・席数・年払い・サポートの見積もり | Stimulus に価格式を写す／フォーム再送で全体を再描画 | `herb_state` + READ slot + 席数だけ `$refresh` |
```

- Add a §③ code comparison "対比 5 — 料金計算（サーバーに残す）". The Hotwire side is a representative Stimulus/pricing placeholder; the ReActionView side is the actual `herb_state` + `boolean_state` + `number_to_currency` snippet from the screen. Explain that the server keeps the formula and the client receives values.
- In §⑤, add one bullet: Pricing's plan/annual/support changes ride a branch flip; seats adds `$refresh`; each interaction is one slots request.
- In §⑦, remove the implemented "送信前計算フォーム（送料・合計）" candidate and renumber the remaining pin and compare candidates.
- Update the generation date to 2026-10-27 or label it as an update date.

- [ ] **Step 3: Update AGENTS.md**

- Add the fifth screen to the opening summary: `Pricing` (`/pricing`), server mode, server-calculated quote, four states, READ slots.
- Add a "Pricing 画面で実測した事実" subsection with:
  - All four states must be read by conditionals for steering; `seats` alone composes `$refresh` because its branch does not flip on every click.
  - `boolean_state` accepts only `true` / `"true"`; `integer_state` casts defensively, and `PricingController` clamps seats to 1..50.
  - Money lines are READ slots, including values inside server-mode branches; the branch statics switch and the slots update on the same response.
  - No-JS recalculation is out of scope because state defaults are literal; URL-param seeding would be a separate design.
- Add to "やらないこと": do not move money math to the client. Why not: folds only add integer literals; tax and multiplication are outside the client-evaluable shapes, and duplicating the formula creates two sources of truth. The server READ slot is the honest place.
- Apply the yomiyasu skill to the Japanese prose.

- [ ] **Step 4: Verify the docs and the full gate**

Run:

```bash
grep -n "4画面\|四つ" README.md docs/hotwire-comparison.md
bin/rails test
bin/ci
```

Expected: the grep only finds intentional historical references (none for the current screen count); `bin/rails test` passes; `bin/ci` passes every gate.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/hotwire-comparison.md AGENTS.md
git commit -m "5画面目 Pricing をドキュメントに追加 — サーバー計算の境界を読み手が追えるようにするため" -m "README と Hotwire 対比ノートに Pricing を追加し、AGENTS.md に steering と READ slot の実測を記録した。"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 covers the route, controller, shared casts, calculation, initial render, and server-side edge cases. Task 2 covers all controls, steering, READ slots, styles, navigation, and browser verification. Task 3 covers README, Hotwire comparison, AGENTS.md, and the final gate. Non-goals (persistence, no-JS recalculation, Async/Hotwire, media) are not implemented.
- **Type consistency:** `PricingController#index` sets the ivars consumed by the view; the READ slot names in the view match the names in the tests; `integer_state` returns Integer, `boolean_state` returns Boolean; the plan keys are the literal strings in the cards.
- **Review Focus:** the five lines above each name a test in Task 1 or Task 2. The client-runtime rapid-click risk is covered by the browser check, not an integration test.
- **Proportion:** the plan gives the calculation body and the delicate view/branch markup; it does not restate the hero copy or the full CSS.
