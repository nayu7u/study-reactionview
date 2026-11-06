# Shared-URL Search (`/catalog`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nav-less `/catalog` Talk Catalog where search, category, and page live in the URL (standard GET) while the "close abstracts" toggle is a client-mode state with zero slots requests.

**Architecture:** A read-only `Talk` model (12 seeds: rails 6 / frontend 3 / infra 3) feeds a standard GET search page. `CatalogController#index` filters, paginates 5 per page, and normalizes invalid category/page params with 302s. The search form and pagination links are normal HTML; the page's only client state is `compact`, bound to a checkbox and a `hidden` presence on the abstracts.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest integration tests, Playwright outside the repo for the probe and media, plain CSS.

**Spec:** `docs/superpowers/specs/2026-11-06-shared-url-search-design.md`

## Global Constraints

- `.html.erb` templates only. No custom app JavaScript, Stimulus, Turbo, Node, yarn, Tailwind, or build step.
- `/catalog` stays out of the global nav. No existing stills or GIFs are re-shot. Patterns gets a footer link.
- Search, category, and page use standard GET navigation. They must not send slots requests.
- The only client state is `compact: false`; it must be 0 slots and must not change the URL.
- URL params: `q`, `category`, `page`. `category` is `all` / `rails` / `frontend` / `infra`. `page` starts at 1.
- Defaults (`category=all`, `page=1`) are accepted and do not redirect. Unknown category, non-integer page, page < 1, and page > last page redirect to the canonical URL with 302.
- Seeds: 12 talks (rails 6 / frontend 3 / infra 3). Five per page, so all = 3 pages and rails = 2 pages.
- `q` searches title OR speaker with `%`, `_`, and `\` escaped via `ESCAPE`.
- The share-URL line is `<%= request.fullpath %>`; the page links omit default params.
- no-JS: the search form, pagination links, and abstracts must all work.
- Japanese prose in docs and commit messages goes through the yomiyasu skill. Commit messages record Why.
- Run `bin/rails test` and `bin/ci` before the final commit.

## Review Focus

These are the inputs and failure modes most likely to bite, with the task that pins each one.

1. **Literal `%` or `_` in the query**: `q=%` must match only literal percent signs (none in the fixtures), not every talk. Pinned by Task 2's "q escapes LIKE wildcards" test.
2. **Canonical redirects without loops**: invalid category/page redirects; `category=all` and `page=1` stay 200; a filtered page 999 redirects to that filter's last page. Pinned by Task 2's normalization tests.
3. **Category + page 2**: rails has 6 talks, so page 2 has 1; the URL and links preserve the category. Pinned by Task 2's "category rails page 2" test and Task 4's probe.
4. **No slots on search/page**: the search form is a GET document, the pagination is links, and the compact toggle is 0 slots. Pinned by Task 4's probe counting `format=slots`.
5. **No-JS**: without JavaScript the search and links still work and the abstracts are visible by default. Pinned by Task 2's no-JS test and Task 4's no-JS browser context.

---

## File Structure

- `db/migrate/<timestamp>_create_talks.rb` — `talks` table.
- `db/seeds.rb` — 12 talks after the existing Proposal seeds.
- `app/models/talk.rb` — categories, labels, validations.
- `test/fixtures/talks.yml` — 12 talks (rails 6 / frontend 3 / infra 3).
- `test/models/talk_test.rb` — model contract.
- `config/routes.rb` — `GET /catalog`.
- `app/controllers/catalog_controller.rb` — search, pagination, normalization.
- `app/helpers/application_helper.rb` — `catalog_params(page:)`.
- `app/views/catalog/index.html.erb` — search form, share URL, list, compact toggle, pagination.
- `app/assets/stylesheets/app.css` — catalog layout, rows, pagination.
- `test/controllers/catalog_controller_test.rb` — search, category, pagination, redirects, manifest, no-JS.
- `/tmp/opencode/capture/catalog-probe.js` — browser probe (outside the repo).
- `/tmp/opencode/capture/catalog-capture.js` — stills and GIF (outside the repo).
- `docs/media/catalog-light.png`, `catalog-dark.png`, `20-catalog.gif`.
- `docs/url-state.md` — the evidence write-up.
- `README.md`, `docs/hotwire-comparison.md`, `docs/hotwire-comparison.html`, `AGENTS.md` — docs.
- `app/views/patterns/index.html.erb` — footer link.

---

### Task 1: Talk model, migration, fixtures, seeds

**Files:**
- Create: `db/migrate/<timestamp>_create_talks.rb`
- Create: `app/models/talk.rb`
- Create: `test/fixtures/talks.yml`
- Create: `test/models/talk_test.rb`
- Modify: `db/seeds.rb`

**Interfaces:**
- Consumes: `ApplicationRecord`.
- Produces: `Talk` with `title:String`, `speaker:String`, `category:String`, `abstract:Text`; `Talk::CATEGORIES -> Array<String>`; `Talk::CATEGORY_LABELS -> Hash<String,String>`; 12 fixtures/seeds with rails 6 / frontend 3 / infra 3.

- [ ] **Step 1: Write the failing model test**

Create `test/models/talk_test.rb`:

```ruby
require "test_helper"

# What is covered here: the read-only catalog's data contract.
class TalkTest < ActiveSupport::TestCase
  test "a fixture talk is valid" do
    assert talks(:rails_one).valid?
  end

  test "requires a title, speaker and abstract" do
    talk = talks(:rails_one)

    talk.title = ""
    talk.speaker = ""
    talk.abstract = ""
    assert_not talk.valid?
    assert talk.errors[:title].any?
    assert talk.errors[:speaker].any?
    assert talk.errors[:abstract].any?
  end

  test "requires a known category" do
    talk = talks(:rails_one)

    talk.category = "unknown"
    assert_not talk.valid?
    assert talk.errors[:category].any?
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/talk_test.rb`
Expected: FAIL with `NameError: uninitialized constant Talk` (or a missing fixture).

- [ ] **Step 3: Create the migration, model, fixtures, and seeds**

Generate the migration:

```bash
bin/rails generate migration CreateTalks
```

Migration body:

```ruby
class CreateTalks < ActiveRecord::Migration[8.1]
  def change
    create_table :talks do |t|
      t.string :title
      t.string :speaker
      t.string :category
      t.text :abstract

      t.timestamps
    end
  end
end
```

Create `app/models/talk.rb`:

```ruby
class Talk < ApplicationRecord
  CATEGORIES = %w[rails frontend infra].freeze
  CATEGORY_LABELS = {
    "rails" => "Rails",
    "frontend" => "フロントエンド",
    "infra" => "インフラ"
  }.freeze

  # Why not uniqueness or a write path: the catalog is a read-only search
  # demo. The models that own writes stay on /forms (Proposal).
  validates :title, :speaker, :abstract, presence: true
  validates :category, inclusion: { in: CATEGORIES }
end
```

Create `test/fixtures/talks.yml` with 12 talks. Use these titles/speakers; keep the distribution rails 6 / frontend 3 / infra 3:

```yaml
rails_one:
  title: ReActionViewのスロットを読む
  speaker: 山田 太郎
  category: rails
  abstract: スロットのwire形式を実際の応答から読み、キー付き差分がどこで起きるかを追います。

rails_two:
  title: Hotwireなしでどこまで行けるか
  speaker: 山田 太郎
  category: rails
  abstract: TurboとStimulusを外したときに、どのUIが残り、どこに標準のRailsが必要かを整理します。

rails_three:
  title: フォームのバリデーションをサーバーに残す
  speaker: 高橋 美咲
  category: rails
  abstract: 422の全画面再描画と入力値保持を、実際のフォームで確かめた結果を共有します。

rails_four:
  title: スロットのペイロードを小さく保つ
  speaker: 小林 悠
  category: rails
  abstract: 何をREAD slotにし、何を分岐のstaticsに置くかで、往復の大きさがどう変わるかを測ります。

rails_five:
  title: Rails 8の認証を最小で組む
  speaker: 加藤 誠
  category: rails
  abstract: 認証を足すときに増えるstateと、サーバーに残すべき判断を最小構成で整理します。

rails_six:
  title: リリースを小さく保つ
  speaker: 松本 彩
  category: rails
  abstract: 変更を小さく出し続けるためのブランチ運用と、検証の自動化について話します。

frontend_one:
  title: Stimulusを捨てた先のフォーム
  speaker: 佐藤 花子
  category: frontend
  abstract: 入力の派生状態と表示の切替を、宣言とpresenceだけでどこまで組めるかを紹介します。

frontend_two:
  title: ゼロビルドのCSS設計
  speaker: 渡辺 さくら
  category: frontend
  abstract: デザイントークンと素のCSSで、ビルドなしの画面を破綻させない方法を整理します。

frontend_three:
  title: フロントエンドの負債を減らす
  speaker: 吉田 葵
  category: frontend
  abstract: 依存とビルドを増やさずに、画面の変更を追いやすくするための判断を共有します。

infra_one:
  title: 小さなRailsアプリの運用
  speaker: 鈴木 一郎
  category: infra
  abstract: 依存を増やさずに運用するための構成と、障害時の切り分けを紹介します。

infra_two:
  title: SQLiteで始める小さなSaaS
  speaker: 中村 大地
  category: infra
  abstract: SQLiteを前提にしたときのバックアップ、移行、監視の最小構成を話します。

infra_three:
  title: 監視のない運用から始める
  speaker: 山本 修
  category: infra
  abstract: 最初から監視を揃えない代わりに、どこを先に見るかを決めておく運用を紹介します。
```

Add to `db/seeds.rb` after the Proposal seeds:

```ruby
Talk.destroy_all

[
  [ "ReActionViewのスロットを読む", "山田 太郎", "rails",
    "スロットのwire形式を実際の応答から読み、キー付き差分がどこで起きるかを追います。" ],
  [ "Hotwireなしでどこまで行けるか", "山田 太郎", "rails",
    "TurboとStimulusを外したときに、どのUIが残り、どこに標準のRailsが必要かを整理します。" ],
  [ "フォームのバリデーションをサーバーに残す", "高橋 美咲", "rails",
    "422の全画面再描画と入力値保持を、実際のフォームで確かめた結果を共有します。" ],
  [ "スロットのペイロードを小さく保つ", "小林 悠", "rails",
    "何をREAD slotにし、何を分岐のstaticsに置くかで、往復の大きさがどう変わるかを測ります。" ],
  [ "Rails 8の認証を最小で組む", "加藤 誠", "rails",
    "認証を足すときに増えるstateと、サーバーに残すべき判断を最小構成で整理します。" ],
  [ "リリースを小さく保つ", "松本 彩", "rails",
    "変更を小さく出し続けるためのブランチ運用と、検証の自動化について話します。" ],
  [ "Stimulusを捨てた先のフォーム", "佐藤 花子", "frontend",
    "入力の派生状態と表示の切替を、宣言とpresenceだけでどこまで組めるかを紹介します。" ],
  [ "ゼロビルドのCSS設計", "渡辺 さくら", "frontend",
    "デザイントークンと素のCSSで、ビルドなしの画面を破綻させない方法を整理します。" ],
  [ "フロントエンドの負債を減らす", "吉田 葵", "frontend",
    "依存とビルドを増やさずに、画面の変更を追いやすくするための判断を共有します。" ],
  [ "小さなRailsアプリの運用", "鈴木 一郎", "infra",
    "依存を増やさずに運用するための構成と、障害時の切り分けを紹介します。" ],
  [ "SQLiteで始める小さなSaaS", "中村 大地", "infra",
    "SQLiteを前提にしたときのバックアップ、移行、監視の最小構成を話します。" ],
  [ "監視のない運用から始める", "山本 修", "infra",
    "最初から監視を揃えない代わりに、どこを先に見るかを決めておく運用を紹介します。" ]
].each do |title, speaker, category, abstract|
  Talk.create!(title: title, speaker: speaker, category: category, abstract: abstract)
end
```

- [ ] **Step 4: Run the migration and the model test**

Run: `bin/rails db:migrate`
Then: `bin/rails test test/models/talk_test.rb`
Expected: PASS, 3 runs.

- [ ] **Step 5: Run the seeds and confirm the count**

Run: `bin/rails db:seed`
Then: `bin/rails runner 'puts Talk.group(:category).count.inspect'`
Expected: `{"frontend"=>3, "infra"=>3, "rails"=>6}`.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb db/seeds.rb app/models/talk.rb test/fixtures/talks.yml test/models/talk_test.rb
git commit -m "feat(catalog): add the Talk catalog data — the URL-state experiment needs a read-only list with enough rows to paginate"
```

---

### Task 2: Route, controller, search view, pagination

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/catalog_controller.rb`
- Modify: `app/helpers/application_helper.rb`
- Create: `app/views/catalog/index.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Create: `test/controllers/catalog_controller_test.rb`

**Interfaces:**
- Consumes: `Talk` and its fixtures from Task 1.
- Produces: `catalog_path` (`/catalog`); `CatalogController#index` setting `@query`, `@category`, `@page`, `@total`, `@pages`, `@talks`; `ApplicationHelper#catalog_params(page:) -> Hash`; `.catalog-search`, `.share-url`, `.catalog-row`, `.catalog-meta`, `.catalog-abstract`, `.catalog-empty`, `.pagination`.

- [ ] **Step 1: Write the failing integration test**

Create `test/controllers/catalog_controller_test.rb`:

```ruby
require "test_helper"

# What is covered here: the URL is the source of truth for the search.
# The form and links are standard GET; the compact switch is added in Task 3.
class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "index renders the search form, the first page and the share URL" do
    get catalog_path

    assert_response :success
    assert_select "h1", "Talk Catalog"
    assert_select "form[action='#{catalog_path}'][method='get']"
    assert_select "form[data-herb-into]", count: 0
    assert_select ".catalog-row", count: 5
    assert_select ".pagination a", text: "3"
    assert_select ".share-url code", text: "/catalog"
    assert_select "a[href='#{forms_path}']"
  end

  test "q filters by title and by speaker" do
    get catalog_path(q: "ReActionView")
    assert_response :success
    assert_select ".catalog-row", count: 1
    assert_select ".catalog-row h3", text: "ReActionViewのスロットを読む"
    assert_select "input[name='q'][value='ReActionView']"

    get catalog_path(q: "佐藤")
    assert_response :success
    assert_select ".catalog-row", count: 1
    assert_select ".catalog-row h3", text: "Stimulusを捨てた先のフォーム"
  end

  test "q escapes LIKE wildcards" do
    get catalog_path(q: "%")
    assert_response :success
    assert_select ".catalog-row", count: 0
    assert_select ".catalog-empty"

    get catalog_path(q: "_")
    assert_response :success
    assert_select ".catalog-row", count: 0
  end

  test "category rails has two pages and page 2 has one talk" do
    get catalog_path(category: "rails")
    assert_response :success
    assert_select ".catalog-row", count: 5
    assert_select "select[name='category'] option[selected][value='rails']"
    assert_select ".pagination a", text: "2"

    get catalog_path(category: "rails", page: 2)
    assert_response :success
    assert_select ".catalog-row", count: 1
    assert_select ".pagination a", text: "1"
  end

  test "page 3 of all talks has two rows" do
    get catalog_path(page: 3)

    assert_response :success
    assert_select ".catalog-row", count: 2
    assert_select ".pagination a", text: "1"
  end

  test "q, category and page combine" do
    get catalog_path(q: "山田", category: "rails", page: 1)

    assert_response :success
    assert_select ".catalog-row", count: 2
    assert_select "input[name='q'][value='山田']"
    assert_select "select[name='category'] option[selected][value='rails']"
  end

  test "pagination links preserve q and category" do
    get catalog_path(category: "rails")

    assert_response :success
    links = css_select(".pagination a").map { |a| a["href"] }
    assert links.any? { |href| href.include?("category=rails") && href.include?("page=2") }

    get catalog_path(q: "の")

    assert_response :success
    links = css_select(".pagination a").map { |a| a["href"] }
    assert links.any? { |href| href.include?("q=%E3%81%AE") && href.include?("page=2") }
  end

  test "invalid category and page redirect to the canonical URL" do
    get catalog_path(page: "abc")
    assert_redirected_to catalog_path

    get catalog_path(page: 0)
    assert_redirected_to catalog_path

    get catalog_path(page: 999)
    assert_redirected_to catalog_path(page: 3)

    get catalog_path(category: "unknown")
    assert_redirected_to catalog_path

    get catalog_path(q: "ReActionView", page: 999)
    assert_redirected_to catalog_path(q: "ReActionView")
  end

  test "default category and page are accepted without a redirect" do
    get catalog_path(category: "all")
    assert_response :success

    get catalog_path(page: 1)
    assert_response :success
  end

  test "filtered out-of-range page redirects to that filter's last page" do
    get catalog_path(category: "rails", page: 999)

    assert_redirected_to catalog_path(category: "rails", page: 2)
  end

  test "no matches render an empty state with one page" do
    get catalog_path(q: "nonexistent")

    assert_response :success
    assert_select ".catalog-row", count: 0
    assert_select ".catalog-empty"
    assert_select ".pagination", count: 0
  end

  test "the initial HTML shows abstracts without JavaScript" do
    get catalog_path

    assert_response :success
    assert_select ".catalog-abstract", count: 5
    assert_select ".catalog-abstract[hidden]", count: 0
  end

  test "the search form is a standard GET form" do
    get catalog_path

    assert_select "form[method='get'][action='#{catalog_path}']"
    assert_select "form[data-herb-set]", count: 0
    assert_select "form[data-herb-into]", count: 0
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/catalog_controller_test.rb`
Expected: FAIL with a routing error for `/catalog`.

- [ ] **Step 3: Add the route, controller, helper, view, and CSS**

Routes:

```ruby
get "/catalog", to: "catalog#index", as: :catalog
```

Create `app/controllers/catalog_controller.rb`:

```ruby
class CatalogController < ApplicationController
  PER_PAGE = 5

  def index
    @query = params[:q].to_s.strip
    raw_category = params[:category].to_s
    @category = Talk::CATEGORIES.include?(raw_category) ? raw_category : "all"

    scope = filtered_scope
    @total = scope.count
    @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
    @page = normalized_page
    return redirect_to catalog_path(canonical_params(@page)) if redirect_to_canonical?(raw_category)

    @talks = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  private

  def filtered_scope
    scope = Talk.order(:title)
    return scope if @query.blank?

    # Why not interpolate the LIKE pattern raw: a literal % or _ would widen
    # the match beyond the query the user sees. Escape and bind the char.
    esc = "\\"
    term = @query.gsub(/[%_\\]/) { "#{esc}#{$&}" }
    scope.where("title LIKE ? ESCAPE ? OR speaker LIKE ? ESCAPE ?", "%#{term}%", esc, "%#{term}%", esc)
  end

  def normalized_page
    page = params[:page].to_s
    return 1 if page.blank?

    value = page.to_i
    value = 1 if value < 1
    value = @pages if value > @pages
    value
  end

  def redirect_to_canonical?(raw_category)
    return true if raw_category.present? && raw_category != "all" && !Talk::CATEGORIES.include?(raw_category)
    return false if params[:page].blank?

    value = params[:page].to_s
    !value.match?(/\A\d+\z/) || value.to_i < 1 || value.to_i > @pages
  end

  def canonical_params(page)
    result = {}
    result[:q] = @query if @query.present?
    result[:category] = @category unless @category == "all"
    result[:page] = page if page > 1
    result
  end
end
```

In `app/helpers/application_helper.rb`, add:

```ruby
def catalog_params(page: nil)
  result = {}
  result[:q] = @query if @query.present?
  result[:category] = @category unless @category == "all"
  result[:page] = page if page && page > 1
  result
end
```

If `ApplicationHelper` does not exist, create it with `module ApplicationHelper` and the method.

Create `app/views/catalog/index.html.erb` with this structure:

```erb
<section class="hero">
  <div class="hero-badge">共有 URL の検索 — 検索は Rails、ページ内は ReactionView</div>
  <h1>Talk Catalog</h1>
  <p class="hero-sub">検索・カテゴリ・ページは URL に載ります。概要の開閉だけがページ内の状態です。</p>
</section>

<div class="catalog">
  <section class="feature">
    <%= form_with url: catalog_path, method: :get, class: "catalog-search" do |form| %>
      <%= form.search_field :q, value: @query, class: "field",
        placeholder: "タイトルか発表者で検索", aria: { label: "キーワード" } %>
      <%= form.select :category,
        [ [ "すべて", "all" ] ] + Talk::CATEGORIES.map { |category| [ Talk::CATEGORY_LABELS.fetch(category), category ] },
        { selected: @category }, class: "select", aria: { label: "カテゴリ" } %>
      <%= form.submit "検索", class: "btn btn-primary" %>
      <%= link_to "条件をクリア", catalog_path, class: "btn btn-ghost" %>
    <% end %>

    <p class="share-url">共有 URL: <code><%= request.fullpath %></code></p>
    <p class="catalog-meta">
      <%= @total %> 件中
      <%= @total.zero? ? 0 : (@page - 1) * CatalogController::PER_PAGE + 1 %>–
      <%= [ @page * CatalogController::PER_PAGE, @total ].min %> 件 /
      <%= @pages %> ページ
    </p>

    <div class="catalog-list">
      <% if @talks.empty? %>
        <p class="catalog-empty">該当するトークはありません。条件を変えてください。</p>
      <% else %>
        <% @talks.each do |talk| %>
          <article class="catalog-row">
            <h3><%= talk.title %></h3>
            <p class="catalog-meta"><%= talk.speaker %> ・ <%= Talk::CATEGORY_LABELS.fetch(talk.category) %></p>
            <p class="catalog-abstract"><%= talk.abstract %></p>
          </article>
        <% end %>
      <% end %>
    </div>

    <% if @pages > 1 %>
      <nav class="pagination" aria-label="ページ送り">
        <% if @page > 1 %>
          <%= link_to "前へ", catalog_path(catalog_params(page: @page - 1)) %>
        <% end %>
        <% (1..@pages).each do |number| %>
          <%= link_to number, catalog_path(catalog_params(page: number)),
            aria: { current: (number == @page ? "page" : nil) } %>
        <% end %>
        <% if @page < @pages %>
          <%= link_to "次へ", catalog_path(catalog_params(page: @page + 1)) %>
        <% end %>
      </nav>
    <% end %>

    <p class="task-note">プロポーザルを送るなら <%= link_to "サーバー検証フォーム", forms_path %> へ。</p>
  </section>
</div>
```

Add to `app/assets/stylesheets/app.css`:

```css
/* ---------- catalog: URL search + in-page compact toggle ---------- */

.catalog { max-width: 52rem; }
.catalog-search { display: flex; gap: 0.6rem; flex-wrap: wrap; align-items: center; }
.catalog-search .field { max-width: 22rem; }
.share-url { margin: 0.9rem 0 0.35rem; font-size: 0.82rem; color: var(--muted); }
.share-url code { overflow-wrap: anywhere; }
.catalog-meta { color: var(--muted); font-size: 0.84rem; }
.catalog-list { margin-top: 0.8rem; }
.catalog-row {
  padding: 0.75rem 0.9rem;
  margin-bottom: 0.6rem;
  border: 1px solid var(--line);
  border-radius: var(--radius-sm);
  background: var(--surface-2);
}
.catalog-row h3 { margin: 0 0 0.25rem; font-size: 1rem; }
.catalog-row p { margin: 0.2rem 0 0; font-size: 0.88rem; color: var(--muted); }
.catalog-abstract { line-height: 1.6; }
.catalog-empty { color: var(--muted); font-size: 0.9rem; }
.pagination { display: flex; gap: 0.4rem; flex-wrap: wrap; margin: 1rem 0 0.5rem; }
.pagination a {
  min-width: 2rem;
  padding: 0.3rem 0.55rem;
  border: 1px solid var(--line);
  border-radius: 999px;
  text-align: center;
  font-size: 0.84rem;
}
.pagination a[aria-current="page"] { border-color: var(--accent); color: var(--accent); font-weight: 700; }
```

- [ ] **Step 4: Run the integration test**

Run: `bin/rails test test/controllers/catalog_controller_test.rb`
Expected: PASS, 13 runs. If the URL-encoded Japanese in the pagination-link test differs, compare against `catalog_path(q: "の", category: "rails", page: 2)` rather than hardcoding the escape.

- [ ] **Step 5: Run the full test suite**

Run: `bin/rails test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/catalog_controller.rb app/helpers/application_helper.rb app/views/catalog/index.html.erb app/assets/stylesheets/app.css test/controllers/catalog_controller_test.rb
git commit -m "feat(catalog): make the URL the source of truth for search and paging — bookmarks and back need standard GET, not slots"
```

---

### Task 3: Client-mode compact switch

**Files:**
- Modify: `app/views/catalog/index.html.erb`
- Modify: `test/controllers/catalog_controller_test.rb`

**Interfaces:**
- Consumes: the list markup from Task 2.
- Produces: `compact: false` client state; `.catalog-compact` checkbox; `hidden` presence on every `.catalog-abstract`; a manifest declaring `compact`.

- [ ] **Step 1: Write the failing manifest test**

Append to `test/controllers/catalog_controller_test.rb`:

```ruby
  test "the compact switch is one client state with hidden abstracts" do
    get catalog_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json
    manifest = JSON.parse(json).values.first

    assert_equal [ "compact" ], manifest.dig("states", "declarations").map { |d| d["name"] }
    assert_equal "region", manifest.dig("states", "declarations").first["scope"]

    presence = manifest.dig("states", "presence")
    assert_equal 6, presence.size
    assert presence.values.all? { |condition| JSON.generate(condition).include?("compact") }

    assert_select ".catalog-compact input[type='checkbox']", count: 1
    assert_select ".catalog-compact input[checked]", count: 0
    assert_select ".catalog-abstract[hidden]", count: 0
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/catalog_controller_test.rb -n "/compact switch/"`
Expected: FAIL because no manifest or compact checkbox exists.

- [ ] **Step 3: Add the state, switch, and hidden abstracts**

At the top of `app/views/catalog/index.html.erb`, add:

```erb
<%# herb:slots client %>
<%# herb:state (compact: false) %>
```

Next to the result meta, add:

```erb
<label class="task-check catalog-compact">
  <input type="checkbox" checked="<%= compact %>">
  <span>概要を閉じる</span>
</label>
```

On each abstract, add the presence:

```erb
<p class="catalog-abstract" hidden="<%= compact %>"><%= talk.abstract %></p>
```

- [ ] **Step 4: Run the test**

Run: `bin/rails test test/controllers/catalog_controller_test.rb`
Expected: PASS, 14 runs. If the presence count is 6 but the manifest includes a different number of boolean attributes, compare the conditions' content rather than the exact size.

- [ ] **Step 5: Run the full test suite**

Run: `bin/rails test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/catalog/index.html.erb test/controllers/catalog_controller_test.rb
git commit -m "feat(catalog): close abstracts in the browser — the URL search must coexist with a zero-request page state"
```

---

### Task 4: Browser probe

**Files:**
- Create: `/tmp/opencode/capture/catalog-probe.js` (outside the repo; not committed)

**Interfaces:**
- Consumes: `/catalog` running on `http://localhost:3000`.
- Produces: measured counts for `docs/url-state.md` and `AGENTS.md`: 0 slots on load, search, category, page, and compact; URL and back/forward/share behavior; no-JS search.

- [ ] **Step 1: Write the probe**

Create `/tmp/opencode/capture/catalog-probe.js`:

```js
// Browser verification for /catalog — lives OUTSIDE the repo.
// Run: node catalog-probe.js (with bin/rails server up, after bin/rails db:seed)
const { chromium } = require("playwright");

const BASE = "http://localhost:3000";

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1100, height: 1000 } });
  const page = await context.newPage();
  const slots = [];
  const documents = [];

  page.on("request", (request) => {
    if (/format=slots/.test(request.url())) slots.push(request.url());
    if (request.resourceType() === "document" && request.url().startsWith(`${BASE}/catalog`)) {
      documents.push(request.url());
    }
  });

  const assertZero = (label) => {
    if (slots.length !== 0) throw new Error(`${label}: ${slots.length} slots requests`);
  };
  const rowCount = () => page.locator(".catalog-row").count();
  const shareURL = () => page.locator(".share-url code").innerText();

  await page.goto(`${BASE}/catalog`, { waitUntil: "networkidle" });
  await page.waitForTimeout(300);
  if ((await rowCount()) !== 5) throw new Error("the first page must have five rows");
  if ((await shareURL()) !== "/catalog") throw new Error("the initial share URL is wrong");
  assertZero("initial");

  await page.check(".catalog-compact input[type='checkbox']");
  await page.waitForTimeout(250);
  assertZero("compact on");
  if ((await page.locator(".catalog-abstract[hidden]").count()) !== 5) {
    throw new Error("compact did not hide the abstracts");
  }
  if ((await shareURL()) !== "/catalog") throw new Error("compact changed the URL");
  await page.uncheck(".catalog-compact input[type='checkbox']");
  await page.waitForTimeout(250);
  assertZero("compact off");
  if ((await page.locator(".catalog-abstract[hidden]").count()) !== 0) {
    throw new Error("compact did not restore the abstracts");
  }

  await page.fill("input[name='q']", "ReActionView");
  await Promise.all([page.waitForNavigation(), page.click("input[type='submit']")]);
  await page.waitForTimeout(250);
  if ((await rowCount()) !== 1) throw new Error("q did not filter to one row");
  if (!page.url().includes("q=ReActionView")) throw new Error("q is not in the URL");
  assertZero("search");

  await page.selectOption("select[name='category']", "rails");
  await page.fill("input[name='q']", "");
  await Promise.all([page.waitForNavigation(), page.click("input[type='submit']")]);
  await page.waitForTimeout(250);
  if ((await rowCount()) !== 5) throw new Error("rails page 1 must have five rows");
  if (!page.url().includes("category=rails")) throw new Error("category is not in the URL");
  assertZero("category");

  await Promise.all([page.waitForNavigation(), page.getByRole("link", { name: "2", exact: true }).click()]);
  await page.waitForTimeout(250);
  if ((await rowCount()) !== 1) throw new Error("rails page 2 must have one row");
  if (!page.url().includes("category=rails") || !page.url().includes("page=2")) {
    throw new Error("category/page are not in the URL");
  }
  assertZero("page 2");

  await page.goBack();
  await page.waitForTimeout(250);
  if ((await rowCount()) !== 5) throw new Error("back did not restore page 1");
  if (page.url().includes("page=2")) throw new Error("back left page=2 in the URL");
  assertZero("back");

  await page.goForward();
  await page.waitForTimeout(250);
  if ((await rowCount()) !== 1) throw new Error("forward did not restore page 2");
  assertZero("forward");

  const shared = page.url();
  const other = await context.newPage();
  await other.goto(shared, { waitUntil: "networkidle" });
  await other.waitForTimeout(250);
  if ((await other.locator(".catalog-row").count()) !== 1) {
    throw new Error("the shared URL did not reproduce page 2");
  }
  await other.close();

  const noJS = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 1100, height: 1000 } });
  const plain = await noJS.newPage();
  await plain.goto(`${BASE}/catalog`, { waitUntil: "networkidle" });
  await plain.fill("input[name='q']", "ReActionView");
  await Promise.all([plain.waitForNavigation(), plain.click("input[type='submit']")]);
  if ((await plain.locator(".catalog-row").count()) !== 1) {
    throw new Error("no-JS search did not filter");
  }
  if ((await plain.locator(".catalog-abstract[hidden]").count()) !== 0) {
    throw new Error("no-JS abstracts are hidden");
  }
  await noJS.close();

  console.log(JSON.stringify({
    initialSlots: 0,
    compactSlots: 0,
    searchSlots: 0,
    categorySlots: 0,
    pageSlots: 0,
    backForward: true,
    sharedURL: true,
    noJS: true,
    documentRequests: documents.length
  }, null, 2));

  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
```

- [ ] **Step 2: Start the server and run the probe**

Run: `bin/rails server -p 3000 -d`
Then: `node /tmp/opencode/capture/catalog-probe.js`
Expected: the JSON summary prints with 0 slots in every key, `backForward: true`, `sharedURL: true`, `noJS: true`. If the pagination link lookup fails because the page has a "2" elsewhere, scope it to `.pagination`.

- [ ] **Step 3: Stop the server**

Run: `kill "$(cat tmp/pids/server.pid)"`
Expected: the server stops.

- [ ] **Step 4: Record the measured output**

Keep the stdout for Task 5 and Task 6. No repository commit is made in this task.

---

### Task 5: Stills and GIF

**Files:**
- Create: `/tmp/opencode/capture/catalog-capture.js` (outside the repo)
- Create: `docs/media/catalog-light.png`, `docs/media/catalog-dark.png`, `docs/media/20-catalog.gif`

- [ ] **Step 1: Write the capture script**

Use the existing `/tmp/opencode/capture/settings-capture.js` as the template (gifenc + pngjs, `hideDevTools`, `assertJapaneseFont`, `writeGif`, `snapClip`). The catalog-specific flow:

1. Stills: `/catalog` fullPage @2x in light and dark; verify `Noto Sans CJK JP` via CDP.
2. GIF: measure the taller of the initial and compact layouts, fix a clip that includes the search form, the share-URL line, the rows, and the pagination. Frame 1: `/catalog`. Frame 2: category `rails` submitted (`?q=&category=rails`) with five rows. Frame 3: check `.catalog-compact` (abstracts close, URL unchanged). Frame 4: click the `2` pagination link (`?q=&category=rails&page=2`, one row). Frame 5: `page.goBack()` (`?q=&category=rails`, five rows, compact reset). Assert every frame has the same dimensions before writing the GIF.
3. `DELAY = 900`, save `docs/media/20-catalog.gif` and `/tmp/opencode/frames/20-catalog-last.png`.

- [ ] **Step 2: Run the server and the capture**

Run: `bin/rails db:seed`
Then: `bin/rails server -p 3000 -d`
Then: `node /tmp/opencode/capture/catalog-capture.js`
Expected: the stills and GIF are written; the GIF is 5 frames and the last frame shows `?q=&category=rails` with five rows.

- [ ] **Step 3: Inspect the media**

Read `docs/media/catalog-light.png` and `catalog-dark.png`. Read `/tmp/opencode/frames/20-catalog-last.png`. Check that the share-URL line is readable, the search form and pagination are in the clip, and no sticky header is stitched into the middle.

- [ ] **Step 4: Stop the server**

Run: `kill "$(cat tmp/pids/server.pid)"`
Expected: the server stops.

- [ ] **Step 5: Commit**

```bash
git add docs/media/catalog-light.png docs/media/catalog-dark.png docs/media/20-catalog.gif
git commit -m "docs(catalog): add the URL-search media — the GIF shows the URL line, paging and back without browser chrome"
```

---

### Task 6: Docs, Patterns link, final verification

**Files:**
- Create: `docs/url-state.md`
- Modify: `README.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `docs/hotwire-comparison.html`
- Modify: `AGENTS.md`
- Modify: `app/views/patterns/index.html.erb`

**Interfaces:**
- Consumes: the measured output from Task 4 and the media from Task 5.
- Produces: the URL-state evidence document, updated showcase docs, and a discoverable link from Patterns.

- [ ] **Step 1: Add the Patterns footer link**

Extend the existing footer paragraph:

```erb
<p>実務検証: <a href="<%= forms_path %>">サーバー検証フォーム（422）</a> ・ <a href="<%= catalog_path %>">共有 URL の検索</a></p>
```

Run: `bin/rails test test/controllers/patterns_controller_test.rb`
Expected: PASS.

- [ ] **Step 2: Write `docs/url-state.md`**

Use these sections, with the measured numbers from Task 4:

1. **何を確かめたか** — can a ReactionView app have shareable/bookmarkable search URLs?
2. **結論** — yes, by leaving URL state to standard GET; the page's ephemeral compact state is ReactionView's part.
3. **URL は Rails、ページ内は ReactionView** — search/category/page are GET; the compact switch is a client state with 0 slots.
4. **実装の形** — the search form, the share-URL line, the pagination links, the canonical redirects.
5. **実測** — the probe table: 0 slots on load/compact/search/category/page; document GETs; back/forward; shared URL; no-JS.
6. **制約** — full reload per search; compact resets; form may submit `q=&category=all`; no incremental search; no custom JS.
7. **Why not slots + URL glue** — ~30 lines of app JS, state/URL desync, request ordering; the repo keeps the no-custom-JS claim.
8. **使い分け** — URL/navigation → standard GET; ephemeral in-page state → client mode; writes/validation → `/forms` の 422.

- [ ] **Step 3: Update `README.md`**

After the `/forms` section, before `## 検証の進め方`, add:

```markdown
## 実務検証: 共有 URL の検索（`/catalog`、ナビ外）

検索・カテゴリ・ページを URL に載せ、ブックマーク・共有・戻る・進む・リロードが成立する検索画面。検索とページ送りは標準の GET フォームとリンク、概要の開閉だけを client mode の `compact` state（0往復）にした。URL は Rails、ページ内は ReactionView という分担の実測。詳細は [docs/url-state.md](docs/url-state.md)。

<div><img src="docs/media/catalog-light.png" alt="Talk Catalog (light)" width="49%"/> <img src="docs/media/catalog-dark.png" alt="Talk Catalog (dark)" width="49%"/></div>

![カテゴリとページが URL に載り、概要の開閉だけが 0 往復で動く](docs/media/20-catalog.gif)
```

Add `catalog_controller_test` to the test list in `## 検証の進め方`.

- [ ] **Step 4: Update `docs/hotwire-comparison.md`**

- Change `## ③ 実コード対比 — 6つの局面` to `7つの局面`.
- Add `### 対比 7 — 共有 URL とページ内状態（URL は Rails、ページ内は slots）` after 対比 6. Include the GET form/search link snippet, the share-URL line, and the compact switch; explain that URL state is a navigation concern and ReactionView does not rewrite the URL.
- In `## ②`, note `/catalog` as the second nav-less experiment.
- In `## ⑥`, add a bullet: `slots 応答は URL を変えない — 検索/ページ/共有は標準 GET、ページ内の一時状態だけ client mode（/catalog の実測）`.
- In `## ⑦`, mention `/catalog` alongside `/forms`.

- [ ] **Step 5: Sync `docs/hotwire-comparison.html`**

Mirror the Markdown: update the pair count to 7, add a compact 対比 7 card, and add the ② / ⑥ / ⑦ notes. Do not restructure the HTML.

- [ ] **Step 6: Update `AGENTS.md`**

Add a `## Catalog 画面で実測した事実（0.6.0 / herb 0.11.1）` section after the Forms section. Record:

- URL 状態は標準 GET。`q` / `category` / `page` をサーバーが読み、検索・ページ送りは document GET。slots は 0。
- 既定値（`category=all` / `page=1`）は 302 しない。不明カテゴリ・非整数/範囲外ページだけ正規 URL へ 302。
- `compact` は `herb:slots client` の1状態。checkbox の `checked` と概要の `hidden` presence で、0 slots・URL 不変。
- no-JS では検索/リンクが動き、概要は既定で見える。`compact` は動かない。
- 共有 URL 行は `request.fullpath`。フォームは `q=&category=all` を送ることがあるが、ページリンクは既定値を落とす。
- seed は rails 6 / frontend 3 / infra 3。rails は2ページで、`?category=rails&page=2` が実在する。
- メディア: `catalog-light/dark.png` と `20-catalog.gif`（初期 → rails → compact → page 2 → back）。日本語フォントとフレーム寸法を確認。
- `/catalog` はナビ外。Patterns footer と README / docs からリンクする。

- [ ] **Step 7: Run the full verification**

Run: `bin/rails test`
Expected: PASS.

Run: `bin/ci`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add docs/url-state.md README.md docs/hotwire-comparison.md docs/hotwire-comparison.html AGENTS.md app/views/patterns/index.html.erb
git commit -m "docs(catalog): record the URL-state boundary — navigation stays with Rails, in-page state stays with slots"
```

---

## Self-Review

- **Spec coverage**: Talk data (Task 1), GET search/pagination/normalization (Task 2), compact client state (Task 3), browser probe (Task 4), media (Task 5), docs and Patterns link (Task 6). The spec's non-goals stay out: no slots search, no URL glue, no nav link, no /forms changes.
- **Step scan**: each step has one checkable action. The URL-encoded Japanese in the pagination-link test is the only value likely to differ by encoder; the task says to compare against `catalog_path` instead.
- **Type consistency**: `catalog_path`, `Talk`, `Talk::CATEGORIES`, `Talk::CATEGORY_LABELS`, `@query`, `@category`, `@page`, `@total`, `@pages`, `@talks`, `catalog_params(page:)`, `compact`, `.catalog-row`, `.catalog-abstract`, `.catalog-compact`, `.pagination` are consistent.
- **Review Focus**: each of the five risks has a named test or probe assertion.
- **Proportion**: the plan includes test code and the markup contract; it does not transcribe every CSS rule or every seed line.
