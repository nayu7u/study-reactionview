# Deep Tree (`/tree`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a nav-less `/tree` client-mode page that renders a DB-backed 4-level file tree, toggles every folder with 0 slots requests, and probes deep nested keyed diff plus state survival through `$refresh`.

**Architecture:** `TreeNode` is a self-referential model. `TreesController#index` loads all nodes once into `@children_by_parent` and renders a recursive `_folder` partial. Each loop declares `herb:key` and `herb:state (open: true)` together; the state is passed to the child partial as `open:`. Children are never wrapped in a conditional, so the slots response stays items/order. A `$refresh` button updates `loaded_at` and reveals whether the client keeps the open states.

**Tech Stack:** Rails 8.1.4, Ruby 4.0.9, ReActionView 0.6.0, Herb 0.11.1, Minitest, SQLite, plain CSS, Playwright outside the repo.

**Spec:** `docs/superpowers/specs/2026-11-07-tree-screen-design.md`

> **Implementation ruling (2026-11-07):** the recursive partial in Task 2 was rejected at the probe. Partial-level `open` is shared across instances, passing a per-item state to a partial raises `ActionView::SyntaxErrorInTemplate`, and same-name states collide across templates. The shipped code is the design's 案5: explicit `index` / `_level2` / `_level3` / `_file` templates with `open_root` / `open_l2` / `open_l3`. See `docs/tree.md` and the ledger rulings.

## Global Constraints

- `/tree` is nav-less. Link it from the Patterns footer, README, and docs; do not add an eighth nav link.
- Client mode (`<%# herb:slots client %>`). Folder open/close sends **0 slots requests**.
- `herb:key` and `herb:state (open: true)` live in the same loop. Pass the state to the child partial as `open:`.
- Never wrap the children collection in `if children.any?` or any state conditional. The `<ul class="tree-children">` always renders for a folder; CSS hides empty lists.
- Initial `open: true` for every folder. no-JS must read the whole tree; toggles may do nothing without JS.
- `aria-expanded` is a client-evaluated string interpolation. Do not assert it in the integration test (test-env collection attributes are slotized); assert it in the browser probe.
- Use the existing plain-CSS tokens in `app/assets/stylesheets/app.css`. No Tailwind, PostCSS, Node, or build step.
- Keep `/`, `/patterns`, `/pricing`, `/settings`, `/lab`, `/ui`, `/dashboard`, `/forms`, `/catalog`, `/apply`, `/outbox`, and `/thread` unchanged.
- `bin/rails test` and `bin/ci` green.
- Japanese prose in README, docs, and commit messages goes through the yomiyasu skill.
- Playwright and capture scripts live in `/tmp/opencode/capture`, not in the repo.

## Review Focus

1. **Level-3 independence**: opening or closing the `trees` folder must not change `tasks`, `views`, or `models`. Pinned by the browser probe at levels 1/2/3.
2. **Children stay a collection**: the slots response must carry `items`/`order`, not branch statics. Pinned by the slots test and by the absence of a guard around the `<ul>`.
3. **`$refresh` state survival**: the refresh must update `loaded_at`; whether the closed folders stay closed is a measured fact, recorded in `docs/tree.md`.
4. **Empty folder shell**: a folder with no children must not show a phantom list. Pinned by the empty-folder test and `.tree-children:empty { display: none; }`.
5. **No-JS / test-env attributes**: the initial tree must be fully readable without JS; `aria-expanded` is checked only in the browser. Pinned by the no-hidden test and the no-JS probe.

---

## File Structure

- `db/migrate/20261107120000_create_tree_nodes.rb` — self-referential table.
- `app/models/tree_node.rb` — validations, `ordered`, `parent`/`children`.
- `test/fixtures/tree_nodes.yml` — 10 nodes, 4 levels.
- `test/models/tree_node_test.rb` — model contract.
- `db/seeds.rb` — 15–20 node demo tree.
- `config/routes.rb` — `GET /tree`.
- `app/controllers/trees_controller.rb` — loads the flat list into `@children_by_parent`.
- `app/views/trees/index.html.erb` — client-mode page, root loop, refresh button.
- `app/views/trees/_folder.html.erb` — recursive folder partial, per-item `open`.
- `app/views/trees/_file.html.erb` — file row.
- `app/assets/stylesheets/app.css` — `.tree-*` styles.
- `test/controllers/trees_controller_test.rb` — HTML, manifest, slots, empty folder.
- `/tmp/opencode/capture/tree-probe.js` — zero-request and depth probe.
- `/tmp/opencode/capture/tree-capture.js` — stills and GIF.
- `docs/media/tree-light.png`, `tree-dark.png`, `25-tree.gif` — new media.
- `docs/tree.md`, `README.md`, `docs/hotwire-comparison.md/html`, `AGENTS.md`, `app/views/patterns/index.html.erb` — docs.

---

### Task 1: TreeNode model, migration, fixtures, seeds

**Files:**
- Create: `db/migrate/20261107120000_create_tree_nodes.rb`
- Create: `app/models/tree_node.rb`
- Create: `test/fixtures/tree_nodes.yml`
- Create: `test/models/tree_node_test.rb`
- Modify: `db/seeds.rb`

**Interfaces:**
- Consumes: `ApplicationRecord`, the existing migration/fixture conventions.
- Produces: `TreeNode` with `name:string`, `kind:string`, `parent_id:integer`, `position:integer`; `TreeNode::KINDS = %w[folder file]`; `TreeNode.ordered`; `#parent`; `#children`; fixture labels `app`, `app_views`, `app_models`, `views_trees`, `views_tasks`, `trees_index`, `tasks_index`, `models_task`, `config`, `config_routes`.

- [ ] **Step 1: Write the failing model test**

Create `test/models/tree_node_test.rb`:

```ruby
require "test_helper"

class TreeNodeTest < ActiveSupport::TestCase
  test "a fixture folder is valid" do
    assert tree_nodes(:app).valid?
  end

  test "requires a name and a known kind" do
    node = tree_nodes(:app)
    node.name = ""
    node.kind = "symlink"

    assert_not node.valid?
    assert node.errors[:name].any?
    assert node.errors[:kind].any?
  end

  test "a node points at its parent and lists ordered children" do
    assert_equal tree_nodes(:app), tree_nodes(:app_views).parent
    assert_equal %w[views models], tree_nodes(:app).children.map(&:name)
  end

  test "destroying a folder destroys its descendants" do
    app = tree_nodes(:app)
    views = tree_nodes(:app_views)
    index = tree_nodes(:trees_index)

    app.destroy

    assert_not TreeNode.exists?(views.id)
    assert_not TreeNode.exists?(index.id)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/tree_node_test.rb`

Expected: FAIL with `uninitialized constant TreeNode` or a missing `tree_nodes` table.

- [ ] **Step 3: Add the migration and model**

Create `db/migrate/20261107120000_create_tree_nodes.rb`:

```ruby
class CreateTreeNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :tree_nodes do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.integer :parent_id
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :tree_nodes, :parent_id
    add_foreign_key :tree_nodes, :tree_nodes, column: :parent_id
  end
end
```

Create `app/models/tree_node.rb`:

```ruby
class TreeNode < ApplicationRecord
  KINDS = %w[folder file].freeze

  belongs_to :parent, class_name: "TreeNode", optional: true, inverse_of: :children
  has_many :children, -> { order(:position, :id) },
    class_name: "TreeNode", foreign_key: :parent_id,
    dependent: :destroy, inverse_of: :parent

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :ordered, -> { order(:position, :id) }
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Add the fixtures**

Create `test/fixtures/tree_nodes.yml` with exactly this tree:

```yaml
app:
  name: app
  kind: folder
  parent_id:
  position: 1

app_views:
  name: views
  kind: folder
  parent_id: <%= ActiveRecord::FixtureSet.identify(:app) %>
  position: 1

app_models:
  name: models
  kind: folder
  parent_id: <%= ActiveRecord::FixtureSet.identify(:app) %>
  position: 2

views_trees:
  name: trees
  kind: folder
  parent_id: <%= ActiveRecord::FixtureSet.identify(:app_views) %>
  position: 1

views_tasks:
  name: tasks
  kind: folder
  parent_id: <%= ActiveRecord::FixtureSet.identify(:app_views) %>
  position: 2

trees_index:
  name: index.html.erb
  kind: file
  parent_id: <%= ActiveRecord::FixtureSet.identify(:views_trees) %>
  position: 1

tasks_index:
  name: index.html.erb
  kind: file
  parent_id: <%= ActiveRecord::FixtureSet.identify(:views_tasks) %>
  position: 1

models_task:
  name: task.rb
  kind: file
  parent_id: <%= ActiveRecord::FixtureSet.identify(:app_models) %>
  position: 1

config:
  name: config
  kind: folder
  parent_id:
  position: 2

config_routes:
  name: routes.rb
  kind: file
  parent_id: <%= ActiveRecord::FixtureSet.identify(:config) %>
  position: 1
```

- [ ] **Step 5: Add the seed tree**

In `db/seeds.rb`, add after the Post/Reply block:

```ruby
# The tree screen needs real depth. The roots are destroyed so dependent:
# :destroy removes the whole tree without deleting a parent before its
# children (a flat delete_all would violate the self-referential FK).
TreeNode.where(parent_id: nil).destroy_all

tree = lambda do |name, kind, parent: nil, position: 0|
  TreeNode.create!(name: name, kind: kind, parent: parent, position: position)
end

app = tree.call("app", "folder", position: 1)
app_controllers = tree.call("controllers", "folder", parent: app, position: 1)
tree.call("trees_controller.rb", "file", parent: app_controllers, position: 1)
tree.call("tasks_controller.rb", "file", parent: app_controllers, position: 2)
app_models = tree.call("models", "folder", parent: app, position: 2)
tree.call("tree_node.rb", "file", parent: app_models, position: 1)
tree.call("task.rb", "file", parent: app_models, position: 2)
app_views = tree.call("views", "folder", parent: app, position: 3)
views_trees = tree.call("trees", "folder", parent: app_views, position: 1)
tree.call("index.html.erb", "file", parent: views_trees, position: 1)
tree.call("_folder.html.erb", "file", parent: views_trees, position: 2)
tree.call("_file.html.erb", "file", parent: views_trees, position: 3)
views_tasks = tree.call("tasks", "folder", parent: app_views, position: 2)
tree.call("index.html.erb", "file", parent: views_tasks, position: 1)
config = tree.call("config", "folder", position: 2)
tree.call("routes.rb", "file", parent: config, position: 1)
tree.call("importmap.rb", "file", parent: config, position: 2)
test = tree.call("test", "folder", position: 3)
tree.call("trees_controller_test.rb", "file", parent: test, position: 1)
```

- [ ] **Step 6: Run the model tests**

Run: `bin/rails test test/models/tree_node_test.rb`

Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20261107120000_create_tree_nodes.rb db/schema.rb \
  app/models/tree_node.rb test/fixtures/tree_nodes.yml \
  test/models/tree_node_test.rb db/seeds.rb
git commit -m "feat(tree): add the self-referential node model — the tree needs real depth, not a flat array"
```

---

### Task 2: Tree route, controller, recursive views, CSS, integration tests

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/trees_controller.rb`
- Create: `app/views/trees/index.html.erb`
- Create: `app/views/trees/_folder.html.erb`
- Create: `app/views/trees/_file.html.erb`
- Modify: `app/assets/stylesheets/app.css`
- Create: `test/controllers/trees_controller_test.rb`

**Interfaces:**
- Consumes: `TreeNode`, `TreeNode.ordered`, `TreeNode::KINDS`.
- Produces: `tree_path`; `TreesController#index` with `@children_by_parent`, `@roots`, `@node_count`, `@folder_count`, `@loaded_at`; the `open` state; CSS classes `.tree-page`, `.tree-toolbar`, `.tree-root`, `.tree-children`, `.tree-node`, `.tree-folder`, `.tree-file`, `.tree-toggle`, `.tree-row`, `.tree-chevron`, `.tree-chevron-empty`, `.tree-icon`, `.tree-name`.

- [ ] **Step 1: Write the failing integration test**

Create `test/controllers/trees_controller_test.rb`:

```ruby
require "test_helper"

# What is covered here: the tree contract — a DB-backed 4-level tree,
# per-folder toggle buttons, no initial hidden list, the per-item open
# state, and a slots response that keeps the children as items/order.
class TreesControllerTest < ActionDispatch::IntegrationTest
  def manifests
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    JSON.parse(json)
  end

  def folder_manifest
    manifests.find { |key, _| key.split(":").first&.end_with?("_folder.html.erb") }&.last
  end

  test "tree renders every node with nested levels and no hidden lists" do
    get tree_path

    assert_response :success
    assert_select "h1", "Tree"
    assert_select ".tree-node", count: TreeNode.count
    assert_select ".tree-folder", count: TreeNode.where(kind: "folder").count
    assert_select ".tree-file", count: TreeNode.where(kind: "file").count
    assert_select "ul.tree-children ul.tree-children ul.tree-children"
    assert_select "button[data-herb-toggle='open']",
      count: TreeNode.where(kind: "folder").count
    assert_select "button[data-herb-action='$refresh']"
    assert_select "[data-herb-name='loaded_at']"
    assert_select "ul.tree-children[hidden]", count: 0
  end

  test "the folder partial declares the per-item open state and hidden presence" do
    get tree_path

    assert_response :success
    manifest = folder_manifest
    assert manifest, "the folder partial has its own manifest entry"

    declarations = manifest.dig("states", "declarations")
    assert declarations.any? { |d| d["name"] == "open" }, "open is a per-item state"

    presence = manifest.dig("states", "presence")
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "open" },
      "the children list binds hidden as a presence read on open"
  end

  test "an empty folder renders an empty list shell" do
    TreeNode.create!(name: "empty", kind: "folder", position: 99)
    get tree_path

    assert_select "li.tree-folder" do |folders|
      empty = folders.find { |folder| folder.text.include?("empty") }
      assert empty, "the empty folder is rendered"
      assert_select empty, "ul.tree-children li", count: 0
    end
  end

  test "the slots response carries the tree and the refresh marker" do
    get tree_path(format: :slots),
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :success
    assert_equal "application/vnd.herb.slots+json", response.media_type

    payload = JSON.parse(response.body)
    assert payload["slots"].values.any? { |slot| slot.is_a?(Hash) && slot["items"] },
      "the keyed tree collections arrive as items"
    assert_match(/\d{2}:\d{2}:\d{2}/, response.body, "loaded_at rides the slots response")
    assert_includes response.body, "index.html.erb"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/trees_controller_test.rb`

Expected: FAIL because `tree_path` and the tree views do not exist.

- [ ] **Step 3: Add the route and controller**

In `config/routes.rb`, after the thread routes:

```ruby
  get "/tree", to: "trees#index", as: :tree
```

Create `app/controllers/trees_controller.rb`:

```ruby
class TreesController < ApplicationController
  def index
    nodes = TreeNode.ordered.to_a
    @children_by_parent = nodes.group_by(&:parent_id)
    @roots = @children_by_parent[nil] || []
    @node_count = nodes.size
    @folder_count = nodes.count { |node| node.kind == "folder" }
    @loaded_at = Time.current
  end
end
```

- [ ] **Step 4: Build the page and the recursive folder partial**

Create `app/views/trees/index.html.erb`:

```erb
<%# herb:slots client %>

<section class="hero">
  <div class="hero-badge">Client mode — 深さ2+の per-node state</div>
  <h1>Tree</h1>
  <p class="hero-sub">フォルダの開閉は 0 往復。深さ2以上の入れ子で、ノードごとの state が独立するかを見ます。</p>
</section>

<section class="tree-page">
  <div class="tree-toolbar">
    <p>
      <%= @node_count %> nodes / <%= @folder_count %> folders ・
      最終取得 <span data-herb-name="loaded_at"><%= @loaded_at.strftime("%H:%M:%S") %></span>
    </p>
    <button class="btn btn-ghost" data-herb-action="$refresh">最新を取得</button>
  </div>

  <ul class="tree-root">
    <% @roots.each do |root| %>
      <%# herb:key root.id %>
      <%# herb:state (open: true) %>
      <% if root.kind == "folder" %>
        <%= render "folder", node: root, open: open, children_by_parent: @children_by_parent %>
      <% else %>
        <%= render "file", node: root %>
      <% end %>
    <% end %>
  </ul>

  <p class="task-note">
    子のコレクションを分岐で包まないので、slots 応答は items/order のまま。
    <code>open</code> は <code>herb:key</code> と同じループで宣言しています。
  </p>
</section>
```

Create `app/views/trees/_folder.html.erb`:

```erb
<% children = children_by_parent[node.id] || [] %>

<li class="tree-node tree-folder">
  <button class="tree-toggle" data-herb-toggle="open" aria-expanded="<%= open %>">
    <span class="tree-chevron" aria-hidden="true"></span>
    <span class="tree-icon" aria-hidden="true">📁</span>
    <span class="tree-name"><%= node.name %></span>
  </button>

  <ul class="tree-children" hidden="<%= !open %>">
    <% children.each do |child| %>
      <%# herb:key child.id %>
      <%# herb:state (open: true) %>
      <% if child.kind == "folder" %>
        <%= render "folder", node: child, open: open, children_by_parent: children_by_parent %>
      <% else %>
        <%= render "file", node: child %>
      <% end %>
    <% end %>
  </ul>
</li>
```

Create `app/views/trees/_file.html.erb`:

```erb
<li class="tree-node tree-file">
  <span class="tree-row">
    <span class="tree-chevron tree-chevron-empty" aria-hidden="true"></span>
    <span class="tree-icon" aria-hidden="true">📄</span>
    <span class="tree-name"><%= node.name %></span>
  </span>
</li>
```

- [ ] **Step 5: Add the tree CSS**

In `app/assets/stylesheets/app.css`, add a `/* ---------- tree ---------- */` block using the existing tokens:

```css
.tree-page {
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  padding: 1rem 1.2rem 1.2rem;
}

.tree-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  flex-wrap: wrap;
}

.tree-toolbar p { margin: 0; }

.tree-root, .tree-children {
  list-style: none;
  margin: 0;
  padding-left: 1.15rem;
}

.tree-root { padding-left: 0; margin-top: 0.8rem; }
.tree-children:empty { display: none; }

.tree-node { margin: 0.15rem 0; }

.tree-toggle, .tree-row {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  width: 100%;
  padding: 0.28rem 0.45rem;
  border-radius: var(--radius-sm);
}

.tree-toggle {
  border: 0;
  background: transparent;
  color: var(--ink);
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.tree-toggle:hover { background: var(--accent-soft); }
.tree-toggle:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

.tree-chevron {
  width: 0.8rem;
  color: var(--muted);
  transition: transform 120ms ease;
}

.tree-chevron::before { content: "▸"; }

.tree-toggle[aria-expanded="true"] .tree-chevron { transform: rotate(90deg); }
.tree-chevron-empty::before { content: ""; }

.tree-icon { width: 1.2rem; text-align: center; }
.tree-name { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.92rem; }
.tree-file .tree-name { color: var(--muted); }
```

- [ ] **Step 6: Run the integration test and the full suite**

Run: `bin/rails test test/controllers/trees_controller_test.rb`

Expected: PASS (4 tests).

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/trees_controller.rb \
  app/views/trees app/assets/stylesheets/app.css \
  test/controllers/trees_controller_test.rb
git commit -m "feat(tree): add the client-mode tree screen — per-node open state needs the loop, not the partial"
```

---

### Task 3: Browser probe (depth, zero requests, refresh, no-JS)

**Files:**
- Create: `/tmp/opencode/capture/tree-probe.js` (outside the repo)
- Output: `/tmp/opencode/capture/tree-probe.out` (outside the repo)
- Modify if the probe exposes a bug: the tree views/CSS from Task 2.

**Interfaces:**
- Consumes: the `/tree` page from Task 2; the seeded tree from Task 1.
- Produces: the measured facts `docs/tree.md` and `AGENTS.md` will record: slots counts, level independence, refresh state survival, no-JS behavior.

- [ ] **Step 1: Seed and start the server**

Run:

```bash
bin/rails db:seed
bin/rails server
```

Expected: the server prints its address (the ReActionView dev slot server may print its own). Keep it running for the probe.

- [ ] **Step 2: Write the probe**

Create `/tmp/opencode/capture/tree-probe.js` with Playwright. It must:

- Track every request whose URL contains `format=slots`.
- Open `http://localhost:3000/tree` and wait for `networkidle`.
- Assert `initial.slots === 0`, `initial.nodes === .tree-node count`, and all `.tree-children` lack `hidden`.
- Use accessible names for the three folders on the seeded `app > views > trees` path. The seed puts `controllers` and `models` before `views`, so a structural `.first()` would pick the wrong node:
  - level 1: `page.getByRole("button", { name: "app" })`
  - level 2: `page.getByRole("button", { name: "views" })`
  - level 3: `page.getByRole("button", { name: "trees" })`
- Click `app` closed, assert `slots` is still 0, its direct `.tree-children` has `hidden`, and `aria-expanded` is `"false"`. Reopen `app`.
- Click `views` closed, assert `slots` is still 0 and its children are hidden. Reopen `views`.
- Click `trees` closed, assert `slots` is still 0 and its children are hidden. Reopen `trees`.
- Independence: close `trees` and assert `tasks` still has `aria-expanded="true"`; close `views` and assert `models` still has `aria-expanded="true"`.
- Open `views` again, close `trees` again, click `最新を取得`, wait for the slots request(s), assert the `loaded_at` text changed, and record the request delta (`refreshSlots`) and whether `trees` is still closed (`refreshKeptState`). The target is 1; if the `child.kind` branch adds a branch refetch, record the actual count and the extra request instead of hiding it.
- Reload and assert all folders are open again (`reloadOpensAll`).
- Open a JS-disabled context (`javaScriptEnabled: false`), load `/tree`, and assert every `.tree-file` and `.tree-folder` is visible and no `.tree-children` is hidden (`noJsReadsAll`).
- Read the `<template data-herb-manifests>` content and record the `_folder` entry's `open` declaration and `hidden` presence.
- Print one JSON summary with these keys: `initialSlots`, `nodes`, `level1Slots`, `level2Slots`, `level3Slots`, `independent`, `refreshSlots`, `refreshKeptState`, `reloadOpensAll`, `noJsReadsAll`, `manifest`.

- [ ] **Step 3: Run the probe**

Run:

```bash
cd /tmp/opencode/capture
node tree-probe.js | tee tree-probe.out
```

Expected: `initialSlots: 0`, `level1Slots: 0`, `level2Slots: 0`, `level3Slots: 0`, `independent: true`, `refreshSlots: 1`, `reloadOpensAll: true`, `noJsReadsAll: true`. If `refreshSlots` is 2, record the branch-refetch boundary in `docs/tree.md`; the open/close measurements stay authoritative.

- [ ] **Step 4: Apply the fallback only if needed**

If the recursive partial breaks keying or per-item state at level 2+, replace it with explicit level partials as specified in the design's 案5. Keep the same markup, class names, and state semantics; use `open_l1` / `open_l2` / `open_l3` if same-name states collide across levels. Re-run the probe. Record which implementation shipped.

If `refreshKeptState` is `false`, keep the screen as is and record the boundary; do not make `$refresh` the primary interaction.

- [ ] **Step 5: Commit any code fix**

If Task 2 code changed:

```bash
git add app/views/trees app/assets/stylesheets/app.css
git commit -m "fix(tree): keep per-node state independent at depth — the probe found the failing level"
```

If no code changed, no commit in this task.

---

### Task 4: Media (stills and GIF)

**Files:**
- Create: `/tmp/opencode/capture/tree-capture.js` (outside the repo)
- Create: `docs/media/tree-light.png`
- Create: `docs/media/tree-dark.png`
- Create: `docs/media/25-tree.gif`

**Interfaces:**
- Consumes: the working `/tree` page and the seeded tree.
- Produces: the stills and GIF referenced by README and `docs/tree.md`.

- [ ] **Step 1: Write the capture script**

Create `/tmp/opencode/capture/tree-capture.js` by following the existing `settings-capture.js` / `thread-capture.js` pattern:

- Viewport `1000x1200` so the `.tree-page` clip fits without stitching.
- Light and dark full-page stills at `deviceScaleFactor: 2`: `docs/media/tree-light.png`, `docs/media/tree-dark.png`.
- GIF frames at the fixed `.tree-page` bounding box:
  1. initial (all open)
  2. `app` (level 1) closed
  3. `app` reopened, `views` (level 2) closed
  4. `views` reopened, `trees` (level 3) closed
  5. `trees` reopened
  6. `最新を取得` clicked and the slots response applied
- Assert every frame has the same width/height before writing the GIF.
- Use the Japanese font stack; run `CSS.getPlatformFontsForNode` on a tree name and assert the family contains `Noto Sans CJK JP`.
- Write `docs/media/25-tree.gif`.

- [ ] **Step 2: Run the capture**

Run:

```bash
cd /tmp/opencode/capture
node tree-capture.js
```

Expected: the three files exist; the GIF frames are uniform; the font check passes.

- [ ] **Step 3: Inspect and commit**

Open the stills/GIF and check: no sticky header inside the GIF, the level-3 folder is visible, the refresh frame shows a changed timestamp, and dark mode uses the dark tokens.

```bash
git add docs/media/tree-light.png docs/media/tree-dark.png docs/media/25-tree.gif
git commit -m "docs(tree): add the stills and depth demo — the level-3 toggle is the evidence"
```

---

### Task 5: Docs, footer link, and final verification

**Files:**
- Create: `docs/tree.md`
- Modify: `README.md`
- Modify: `docs/hotwire-comparison.md`
- Modify: `docs/hotwire-comparison.html`
- Modify: `AGENTS.md`
- Modify: `app/views/patterns/index.html.erb`
- Test: full suite and CI.

**Interfaces:**
- Consumes: the probe output from Task 3 and the media from Task 4.
- Produces: the user-facing record of the measured depth behavior.

- [ ] **Step 1: Add the Patterns footer link**

In `app/views/patterns/index.html.erb`, extend the existing 実務検証 line:

```erb
<a href="<%= tree_path %>">深いツリー</a>
```

Keep the line's existing links and punctuation.

- [ ] **Step 2: Write `docs/tree.md`**

Use the structure of `docs/thread.md`:

- What was measured: 4 levels, per-node open state, 0 roundtrip, `$refresh`, no-JS.
- The data model and the flat-list-to-tree load.
- The recursive partial: `herb:key` + `herb:state (open: true)` in the same loop; `open:` passed to the child; no `if children.any?`.
- The browser measurements: copy the exact `tree-probe.out` numbers for levels 1/2/3, independence, `refreshSlots`, `refreshKeptState`, `noJsReadsAll`.
- The `$refresh` wire: `loaded_at` and the nested items/order; whether the open states survived.
- The test-env `aria-expanded` slotization note.
- Constraints: no persistence, no add/delete/reorder/select, arbitrary depth not guaranteed, UI Kit extraction deferred, DnD out of scope.
- The shipped implementation: recursive partial or the explicit level fallback.

- [ ] **Step 3: Update README, hotwire-comparison, and AGENTS.md**

- README: add a section titled `実務検証: 深いツリー（/tree、ナビ外）` after Thread, with the stills and `25-tree.gif`, and a link to `docs/tree.md`.
- `docs/hotwire-comparison.md`: add a proof-map row and 対比11「深い入れ子の per-node 状態」. Hotwire side: recursive partial + a Stimulus tree controller with an open-set. ReActionView side: the same recursive partial + `herb:state (open: true)` in each loop + `hidden` presence; 0 slots. Update §⑦ to say the tree is implemented at `/tree`.
- `docs/hotwire-comparison.html`: mirror the same row and section in the existing styled markup.
- `AGENTS.md`: add a `## Tree 画面で実測した事実` section with the probe facts: levels 1/2/3 0 slots, state independence, `$refresh` result, no-JS, `aria-expanded` test-env slotization, media/font.

- [ ] **Step 4: Run the full verification**

Run:

```bash
bin/rails test
bin/ci
```

Expected: both green. If `bin/ci` runs RuboCop/audit and flags the new files, fix them before committing.

- [ ] **Step 5: Commit**

```bash
git add docs/tree.md README.md docs/hotwire-comparison.md docs/hotwire-comparison.html \
  AGENTS.md app/views/patterns/index.html.erb
git commit -m "docs(tree): record the measured depth — per-node state and the refresh boundary belong in the notes"
```

---

## Self-Review

- **Spec coverage:** The model/data, client-mode page, per-node state, 0-roundtrip probe, `$refresh`, no-JS, tests, media, README/docs/AGENTS, and footer link each have a task. The nav is untouched.
- **Type consistency:** `TreeNode` attributes, `KINDS`, `ordered`, `children`, `parent`, `tree_path`, `@children_by_parent`, and the `open` state name match across tasks.
- **Review Focus:** The five lines each have a pinning test or probe step: level independence (Task 3), items/order (Task 2 slots test + view), refresh survival (Task 3 + docs), empty folder (Task 2), no-JS/aria (Task 2 + Task 3).
- **Proportion:** The plan carries the exact tests and the view skeleton; CSS, probe, capture, and docs are described by their required outcomes, not transcribed.
