require "test_helper"

# What is covered here: the client-mode lab — parked branches, the compiled
# derived state, presence-bound switch, and the zero-server-read claim.
class ShowcaseFlowTest < ActionDispatch::IntegrationTest
  test "lab renders with its branches parked for the client" do
    get lab_path

    assert_response :success
    assert_select "h1", "Client Lab"
    assert_select 'button[data-herb-set="tab=all"]'
    assert_select 'button[data-herb-set="tab=mentions"]'
    assert_select 'button[data-herb-increment="unread"][data-herb-by="2"]'
    assert_select 'button[data-herb-decrement="unread"]'
    assert_select 'button[data-herb-reset="unread"]'
    assert_select 'button[data-herb-reset="draft"]'
    assert_select 'button[data-herb-set*="keydown.meta+k@window->palette_open=true"]'
    assert_select 'button[data-herb-set*="keydown.ctrl+k@window->palette_open=true"]'
    # the boolean interpolation lands as "true"/"false" strings: exactly one
    # active tab per render, the client re-evaluates it on tab set
    assert_select 'button.seg-btn[aria-pressed="true"]', count: 1
    assert_select 'button.seg-btn[aria-pressed="false"]', count: 1
    assert_select "input.switch", count: 1
    assert_select 'div[data-herb-set*="mouseenter->preview=true"]'
    assert_select '[data-herb-action="$refresh"]'

    # wizard: three step arms with gated next buttons
    assert_select 'span.dot[aria-current="true"]', count: 1
    assert_select 'span.dot[aria-current="false"]', count: 2
    # presence bindings render as a bare attribute + a boolean_attribute slot:
    # the empty name gates the first next button
    assert_select 'button[data-herb-increment="step"][disabled]'
    assert_select 'button[data-herb-decrement="step"]'
    assert_select 'button[data-herb-reset="step name email"]'

    # validation: combo derived gates the save button
    assert_select "button.btn-primary[disabled]"

    # qty stepper: one decrement per row, zero-clamped by presence
    assert_select 'button[data-herb-decrement="qty"][disabled]', count: 3
    assert_select 'button[data-herb-increment="qty"]', count: 3

    # accordion: toggle headers with the closed marker arm
    assert_select 'button.acc-head[data-herb-toggle="open"]', count: 3
    assert_select ".acc-marker", "＋"
  end

  test "the manifest compiles the derived state and parking" do
    get lab_path

    assert_response :success

    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json
    manifest = JSON.parse(json).values.first

    declarations = manifest.dig("states", "declarations")
    ready = declarations.find { |d| d["name"] == "ready" }
    assert_equal "draft", ready["derived"].first, "a derived state names its source for the client"

    assert_match(/<template data-herb-region=/, response.body, "client mode parks unrendered branches")

    server = manifest.dig("states", "server")
    assert server["branches"].present?,
      "the mentions arm holds server-read rows, so parked rebuilds know which slots the server fills"

    presence = manifest.dig("states", "presence")
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "mute" }, "the switch binds a boolean state"
    assert manifest.dig("states", "computed").values.any? { |c| c[3] == "length" }, "the char count is a computed read"

    declarations = manifest.dig("states", "declarations")
    over = declarations.find { |d| d["name"] == "over" }
    assert_equal "length", over["derived"][3], "the over-limit gate is a length-transform comparison"
    assert_equal ">", over["derived"][2], "the comparison is an ordered operator the client evaluates"
    ready_bio = declarations.find { |d| d["name"] == "ready_bio" }
    assert ready_bio["derived"].is_a?(Hash) && ready_bio["derived"]["all"],
      "the save gate is a combo derivation (empty AND under the limit)"

    in_cart = declarations.find { |d| d["name"] == "in_cart" }
    assert_equal "qty", in_cart.dig("count", "when", 0), "the fold counts rows whose qty passes"
    assert_equal ">", in_cart.dig("count", "when", 2), "the fold condition is an ordered comparison"

    open_decl = declarations.find { |d| d["name"] == "open" }
    assert open_decl, "the accordion rows declare a per-item open state"

    # the parked FAQ answer arms are listed for the server to fill
    branches = manifest.dig("states", "server", "branches") || {}
    assert branches.values.flatten.any?, "parked arms with server reads are inventoried for refetch"
  end
end
