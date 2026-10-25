require "test_helper"

# What is covered here: the reactionview-ui kit contract. Nine copy-source
# fragments render self-contained; each partial carries its own herb:state
# manifest entry (component-owned state, the shadcn useState equivalent);
# presence bindings come out in bare-attribute shape; interaction arms are
# parked in the client-mode region.
class UiKitFlowTest < ActionDispatch::IntegrationTest
  test "the showcase renders all nine components" do
    get ui_path
    assert_response :success
    assert_select "h1", "UI Kit"
    assert_select ".ui-btn", minimum: 5
    assert_select ".ui-badge", minimum: 3
    assert_select ".ui-card", minimum: 1
    assert_select ".ui-switch input[type=checkbox]", count: 2
    assert_select ".ui-tab", count: 2
    assert_select ".ui-acc-head", count: 3
    assert_select ".ui-stepper-row", count: 3
    assert_select ".ui-field", count: 1
  end

  test "each component partial owns its manifest declarations" do
    get ui_path
    assert_response :success

    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    manifest = JSON.parse(json)

    decls = manifest.transform_values { |m| (m.dig("states", "declarations") || []).map { |d| d["name"] } }
    # keys carry a version hash suffix (:fcbe4413) that changes with every
    # template edit — match on the path, never the whole key
    names_for = ->(fragment) { decls.find { |key, _| key.split(":").first&.end_with?("_#{fragment}.html.erb") }&.last }

    assert_includes names_for.call("switch"), "on"
    assert_includes names_for.call("tabs"), "tab"
    assert_includes names_for.call("dialog"), "shown"
    assert_equal %w[draft ready over], names_for.call("field")
    # one partial holds BOTH the top-level counted state and the per-item qty
    stepper = names_for.call("stepper")
    assert_includes stepper, "in_cart"
    assert_includes stepper, "qty"
    assert_includes names_for.call("accordion"), "open"
  end

  test "presence bindings render in bare-attribute shape" do
    get ui_path
    assert_response :success

    # switch: on=false at init → checked absent, never a value string
    assert_select ".ui-switch input[type=checkbox][checked]", count: 0
    # stepper: qty=0 at init → minus buttons disabled, as bare attribute
    assert_select ".ui-stepper-row button[data-herb-decrement][disabled]", count: 3
    # field: ready=false at init → submit gate disabled
    assert_select ".feature[data-feature=field] button[disabled]", count: 1
    # accordion: hidden = !open = true at init → bare hidden attribute
    assert_select ".ui-acc-body[hidden]", count: 3
    assert_select ".ui-acc-body[hidden='false']", count: 0
  end

  test "interaction regions are occurrence-indexed per partial" do
    get ui_path
    assert_response :success

    # test env emits regions as comment markers (the <template
    # data-herb-region> form only appears in dev — same env gating as the
    # debug spans). The :0/:1 suffixes are occurrence indices: the two pasted
    # switches live in separate regions, which is what keeps their states
    # independent at the wire level.
    assert_match(/<!--herb-region:app\/views\/components\/ui\/_switch\.html\.erb:[0-9a-f]+:0-->/, response.body)
    assert_match(/<!--herb-region:app\/views\/components\/ui\/_switch\.html\.erb:[0-9a-f]+:1-->/, response.body)
    assert_match(/<!--herb-region:app\/views\/components\/ui\/_dialog\.html\.erb:[0-9a-f]+:0-->/, response.body)
  end
end
