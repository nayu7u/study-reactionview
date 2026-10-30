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

  def block_headers(index)
    fragment = manifest.dig("states", "fragments").fetch(index)
    {
      "Herb-Block" => index,
      "Herb-State" => { template_path => { fragment["state"] => true } }.to_json
    }
  end

  def block_partial(payload, template)
    payload["slots"].values.each do |slot|
      next unless slot["slots"].is_a?(Hash)

      found = slot["slots"].values.find do |part|
        part.is_a?(Hash) && part["template"] == template
      end
      return found if found
    end
    nil
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

    assert_equal 2, fragments.count { |_index, fragment| fragment["mode"] == "async" }
    assert_equal 150, async["delay"]
    assert_equal 400, async["hold"]
  end

  test "the async block request answers with the summary" do
    get dashboard_path
    index = block_index(mode: "async", poll: false)

    get dashboard_path(format: :slots), headers: block_headers(index)

    assert_response :success
    # The test environment labels the block JSON as text/html; the client
    # parses the body. The block carries the partial's dynamic values; its
    # static labels arrive through the dependency map.
    payload = JSON.parse(response.body)
    assert_equal "app/views/dashboard/index.html.erb", payload["template"]
    summary = block_partial(payload, "app/views/dashboard/_summary.html.erb")
    assert summary, "the block answers with the summary partial"
    assert_equal %w[3 1 3], summary["slots"].values
  end

  test "dashboard renders the lazy fallback and manifest" do
    get dashboard_path

    assert_select ".dashboard-activity .skeleton-note", text: /スクロールすると/
    fragments = manifest.dig("states", "fragments")
    assert_equal 1, fragments.count { |_index, fragment| fragment["mode"] == "lazy" }
  end

  test "the lazy block request answers with recent activity" do
    get dashboard_path
    index = block_index(mode: "lazy")

    get dashboard_path(format: :slots), headers: block_headers(index)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.to_s, "テンプレートを壊してオーバーレイを見る"
    assert_includes payload.to_s, "時間前"
  end

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
    stats = block_partial(payload, "app/views/dashboard/_focus_stats.html.erb")
    assert stats, "the slots response carries the focus stats"
    assert_includes stats["slots"].values, "1"
  end

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

    get dashboard_path(format: :slots), headers: block_headers(index)

    assert_response :success
    payload = JSON.parse(response.body)
    beat = block_partial(payload, "app/views/dashboard/_heartbeat.html.erb")
    assert beat, "the block answers with the heartbeat partial"
    assert_match(/\d{2}:\d{2}:\d{2}/, beat["slots"].values.join)
  end
end
