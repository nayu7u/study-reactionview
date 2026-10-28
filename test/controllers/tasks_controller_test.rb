require "test_helper"

# What is covered here: the Sprint Hub contract — the feature-organized
# dashboard that shows off ReActionView's abilities: server reads through
# herb_state (debounced input, sort select, $refresh), keyed optimistic
# rows, the drawer branch answered by the server, and the compiled
# manifest marking this template as server mode.
class TasksFlowTest < ActionDispatch::IntegrationTest
  # HTTP header values must stay ASCII, so multi-byte state values travel
  # as JSON \uXXXX escapes — exactly how a browser client must send them.
  def herb_state_header(template:, state:)
    JSON.generate({ template => state }).gsub(/[^ -~]/) { |c| "\\u#{c.ord.to_s(16).rjust(4, "0")}" }
  end

  test "index renders the feature-organized dashboard" do
    get root_path

    assert_response :success
    assert_select "h1", "Sprint Hub"
    assert_select "section.feature", count: 3
    assert_select 'input[data-herb-set="query=$value"][data-herb-debounce="220"]'
    assert_select 'select[data-herb-set="order=$value"]'
    assert_select '[data-herb-action="$refresh"]'
    assert_select 'button[data-herb-toggle="drawer_open"]'

    # The drawer's closers and the window shortcut compile as bindings
    assert_select 'div[data-herb-set*="keydown.meta+b@window->drawer_open=true"]'
    assert_select 'div[data-herb-set*="keydown.ctrl+b@window->drawer_open=true"]'
    assert_select 'input[data-herb-debounce="220"][aria-label="タスクを検索"]'

    # Keyed rows with row-scoped state and named parts for the splice
    assert_select 'ul[data-herb-name="tasks"]' do
      assert_select "li", 3
      assert_select 'span[data-herb-name="title"]'
    end
    assert_select '.task-check input[type="checkbox"]', count: 3
  end

  test "each task row has a pin checkbox and the pinned count summary" do
    get root_path

    assert_response :success
    assert_select ".task-pin input[type='checkbox']", count: 3
    assert_select ".pin-stat", text: "0 件ピン留め"

    titles = css_select(".task-title").map { |node| node.text.strip }
    labels = css_select(".task-pin input").map { |node| node["aria-label"] }
    assert_equal titles.map { |title| "#{title} をピン留め" }, labels
    assert_equal labels.uniq.size, labels.size, "each star names its task"
  end

  test "a typed query filters server-side through herb_state" do
    get root_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => herb_state_header(
        template: "app/views/tasks/index.html.erb",
        state: { "query" => "スロット", "order" => "oldest" }
      )
    }

    assert_response :success
    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["order"] }
    assert_equal [ tasks(:one).id.to_s ], collection["order"], "only the matching row is served"
    assert_includes collection["items"].values.first.values, "ReActionViewのスロットを読む"

    note = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("サーバーで絞り込み済み") }
    assert note, "the toolbar note reports the server-side filter"
    assert_includes note["slots"].values, "スロット"
  end

  test "the drawer branch is answered by the server with the full form" do
    get root_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/tasks/index.html.erb" => { "drawer_open" => true } }.to_json
    }

    assert_response :success
    payload = JSON.parse(response.body)
    drawer = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("drawer-backdrop") }
    assert drawer, "opening renders the drawer through the same action"
    assert_match(%r{name="task\[title\]"}, drawer["statics"])
    assert drawer["statics"].include?("char-hint"), "the live character count rides along"
    assert drawer["statics"].include?("click@outside->drawer_open=false"), "the backdrop close compiles"
    assert drawer["statics"].include?("keydown.esc@window->drawer_open=false"), "the Esc close compiles"
    assert drawer["statics"].include?("submit->drawer_open=false"), "a successful submit closes the drawer"
    assert drawer["statics"].include?("role=\"dialog\""), "the drawer announces itself as a dialog"
  end

  test "create answers a slots add with the new keyed row" do
    post tasks_path(format: "slots"),
      params: { task: { title: "GIF用にボードを撮る" } },
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :created
    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["items"] }
    assert_equal 1, collection["items"].size
    assert_includes collection["items"].values.first.values, "GIF用にボードを撮る"

    # The hero badge is a scalar slot whose value is the fresh total, found
    # by content rather than slot index (indexes shift on template changes)
    assert_includes payload["slots"].values, Task.count.to_s, "the hero count recomputes on add"
  end

  test "create redirects without JavaScript" do
    post tasks_path, params: { task: { title: "Plain form post." } }

    assert_redirected_to root_path
  end

  test "the compiled manifest marks server mode and row state" do
    get root_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json
    manifest = JSON.parse(json).values.first

    names = manifest.dig("states", "declarations").map { |d| d["name"] }
    assert_includes names, "drawer_open"
    assert_includes names, "done_count"
    assert_includes names, "pinned"
    assert_includes names, "pinned_count"

    # The drawer branch is registered as a conditional read, not parked (server mode)
    conditionals = manifest.dig("states", "conditionals")
    assert conditionals.values.any? { |c| Array(c["arms"]).any? { |a| a["condition"]&.first == "drawer_open" } },
      "the drawer conditional is compiled into the manifest"

    presence = manifest.dig("states", "presence")
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "done" }, "checkbox binds the row state"
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "title" && p[2] == "blank" },
      "the submit button's disabled binding compiles as a presence read"
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "order" },
      "select option selected= is a presence read on the order state"
    assert manifest.dig("states", "computed").values.any? { |c| c[3] == "length" },
      "the character count is a computed read on title"

    fold = manifest.dig("states", "declarations").find { |d| d["name"] == "done_count" }
    assert_equal 1, fold.dig("count", "by"), "the fold counts one step per row"
    assert_equal "done", fold.dig("count", "when", 0), "the fold is conditioned on the row state"

    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "pinned" },
      "the star checkbox binds the row state"
    pin_fold = manifest.dig("states", "declarations").find { |d| d["name"] == "pinned_count" }
    assert_equal 1, pin_fold.dig("count", "by"), "the pin fold counts one step per row"
    assert_equal "pinned", pin_fold.dig("count", "when", 0), "the pin fold is conditioned on the row state"
  end
end
