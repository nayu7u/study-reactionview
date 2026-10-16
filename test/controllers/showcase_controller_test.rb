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
    assert_select 'button[data-herb-reset]'
    assert_select 'button[data-herb-set="keydown.meta+k@window->palette_open=true"]'
    assert_select 'input.switch', count: 1
    assert_select 'div[data-herb-set*="mouseenter->preview=true"]'
    assert_select '[data-herb-action="$refresh"]'
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
    assert_empty server["branches"], "nothing on the lab needs the server to build a branch"

    presence = manifest.dig("states", "presence")
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "mute" }, "the switch binds a boolean state"
    assert manifest.dig("states", "computed").values.any? { |c| c[3] == "length" }, "the char count is a computed read"
  end
end
