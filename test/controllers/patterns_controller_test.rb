require "test_helper"

# What is covered here: the Patterns screen contract — a realistic inbox on
# the tasks table showing three server-mode patterns: priority filter chips
# (herb_state read by the controller), keyed load-more paging, and a
# selection-driven detail panel answered by the same action.
class PatternsFlowTest < ActionDispatch::IntegrationTest
  SEED = 10 # : Integer

  setup do
    # Fixtures alone fit on one page, so the paging assertions create a full
    # second page. Integration tests roll back, the hub's 3-row fixtures
    # stay untouched for their own count assertions.
    SEED.times do |i|
      Task.create!(title: "paging row #{i}", priority: (i % 3) + 1, created_at: i.minutes.ago)
    end
  end

  test "index renders the split inbox with chips and the empty detail arm" do
    get patterns_path

    assert_response :success
    assert_select "h1", "Patterns"
    assert_select ".chip", count: 4
    assert_select '.chip[aria-pressed="true"]', count: 1
    assert_select ".chip-count", Task.count.to_s
    # page one shows exactly PER_PAGE rows
    assert_select "ul.rows button.row", count: 6
    assert_select 'button.row[data-herb-set^="click->selected_id="]'
    assert_select "button.load-more", "もっと見る（残り7件）"
    assert_select ".detail-empty"
  end

  test "the compiled manifest declares the three states" do
    get patterns_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    manifest = JSON.parse(json).values.first

    names = manifest.dig("states", "declarations").map { |d| d["name"] }
    assert_includes names, "priority"
    assert_includes names, "page"
    assert_includes names, "selected_id"

    # The detail conditional is carried by branch markers in the initial
    # HTML (server mode): the client learns its current arm from these.
    assert_match(/<!--herb-branch:\d+:(?:0|1)-->/, response.body)
  end

  test "a priority chip filters server-side through herb_state" do
    get patterns_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/patterns/index.html.erb" => { "priority" => "3", "page" => 1 } }.to_json
    }

    assert_response :success
    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["order"] }
    # every served row is high priority, fixtures included, newest first
    expected = Task.where(priority: 3).order(created_at: :desc, id: :desc).pluck(:id).map(&:to_s)
    assert_equal expected, collection["order"]
    assert_equal 4, collection["order"].size

    # the note is a conditional on the priority state: only states read by a
    # conditional's arms ride the steering header, so this branch is also
    # what makes the chip's round trip carry priority at all
    note = payload["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("絞り込み中")
    end
    assert note, "the filtered note arm answers the chip click"
    assert_match(/優先度「高」/, note["statics"])
  end

  test "page two answers with more keyed rows, page three with the done arm" do
    get patterns_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/patterns/index.html.erb" => { "page" => 2 } }.to_json
    }

    assert_response :success
    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["order"] }
    assert_equal 12, collection["order"].size, "page two reveals the second page"
    assert_equal collection["order"].size, collection["items"].size
    assert payload["slots"].values.any? { |slot| slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("load-more") },
      "rows still remain, so the button arm is served"

    get patterns_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/patterns/index.html.erb" => { "page" => 3 } }.to_json
    }

    assert_response :success
    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["order"] }
    assert_equal Task.count, collection["order"].size, "page three covers the whole inbox"
    assert payload["slots"].values.any? { |slot| slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("全部読み込みました") },
      "an exhausted inbox answers with the done arm, not the button"
  end

  test "a row click answers with the detail arm and named value slots" do
    selected = Task.order(:id).first
    get patterns_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/patterns/index.html.erb" => { "selected_id" => selected.id } }.to_json
    }

    assert_response :success
    payload = JSON.parse(response.body)
    detail = payload["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("detail-title")
    end
    assert detail, "selecting a row serves the detail arm through the same action"
    assert_equal 0, detail["branch"]
    values = detail["slots"].values
    assert_includes values, selected.title
    assert_includes values, selected.id.to_s
  end

  test "a stale selection answers the detail arm with empty values" do
    # The detail condition must read the state itself (selected_id > 0) or the
    # client would never steer the round trip; a stale id therefore lands in
    # the detail arm with empty slot values rather than the empty arm.
    get patterns_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/patterns/index.html.erb" => { "selected_id" => 999_999 } }.to_json
    }

    assert_response :success
    payload = JSON.parse(response.body)
    detail = payload["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("detail-title")
    end
    assert detail, "the detail arm is still the answered branch"
    assert_equal 0, detail["branch"]
    assert detail["slots"].values.all?(&:empty?), "the values degrade to empty instead of ghost data"
  end

  test "the steering conditionals are compiled from the three states" do
    get patterns_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    manifest = JSON.parse(json).values.first
    conditions = manifest.dig("states", "conditionals").values
      .flat_map { |c| Array(c["arms"]) }.map { |a| a["condition"]&.first }.compact

    assert_includes conditions, "priority", "the note conditional reads priority for the steering header"
    assert_includes conditions, "selected_id", "the detail conditional reads selected_id"
    assert_includes conditions, "page", "the page indicator conditional reads page"
  end
end
