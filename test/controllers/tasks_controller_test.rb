require "test_helper"

# What is covered here: the board's React-style staples — the modal branch,
# the optimistic add contract, keyed task rows with row-scoped state, the
# counting fold, and the CSS-anchored presence binding.
class TasksFlowTest < ActionDispatch::IntegrationTest
  test "index renders the keyed task list" do
    get board_path

    assert_response :success
    assert_select "h1", "Task Board"
    assert_select 'button[data-herb-toggle="open"]'
    assert_select 'ul[data-herb-name="tasks"]' do
      assert_select "li", 2
    end
  end

  test "the modal branch answers a state change through the server" do
    get board_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/tasks/index.html.erb" => { "open" => true } }.to_json
    }

    assert_response :success

    payload = JSON.parse(response.body)
    modal = payload["slots"].values.find { |slot| slot["statics"]&.include?("modal-backdrop") }
    assert modal, "opening parks the modal until open flips, then the server renders it"
    assert_match(%r{name="task\[title\]"}, modal["statics"])
  end

  test "create answers a slots add with the new keyed task row" do
    post tasks_path(format: "slots"),
      params: { task: { title: "Optimistically appended task." } },
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :created

    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot["items"] }
    assert_equal 1, collection["items"].size
    assert_includes collection["items"].values.first.values, "Optimistically appended task."

    # The counter's statics ride along with the row so the "N tasks waiting"
    # sentence can follow the insert.
    stats = payload["slots"].values.find { |slot| slot["statics"]&.include?("tasks waiting") }
    assert stats, "the stats sentence is part of the payload"
  end

  test "create redirects without JavaScript" do
    post tasks_path, params: { task: { title: "Plain form post." } }

    assert_redirected_to board_path
  end

  test "row state and counting fold compile into the manifest" do
    get board_path

    assert_response :success

    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json, "the board carries its client manifest"
    manifest = JSON.parse(json).values.first

    declarations = manifest.dig("states", "declarations")
    assert_includes declarations.map { |d| d["name"] }, "open"
    done = declarations.find { |d| d["name"] == "done" }
    assert done, "each keyed row declares its own done state"
    assert_kind_of Integer, done["scope"]
    assert_equal "integer", declarations.find { |d| d["name"] == "done_count" }["kind"]

    keys = manifest.dig("states", "keys") || manifest.dig("states", "collections")
    # Presence: the checkbox binds the row state; :has(input:checked) styles off it.
    assert manifest.dig("states", "presence").values.any? { |p| p.is_a?(Array) && p[0] == "done" }
  end
end
