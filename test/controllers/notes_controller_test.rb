require "test_helper"

# What is covered here: the client-mode surface — the parked unrendered
# branches, the action attributes with event clauses, row-scoped state,
# boolean attribute bindings, the counting fold read, and the compiled
# manifest that tells the client how to run all of it without a request.
class NotesFlowTest < ActionDispatch::IntegrationTest
  test "index renders the inbox with parked client branches" do
    get notes_path

    assert_response :success

    # Client mode parks every unrendered branch in one region template
    assert_match(/<template data-herb-region="app\/views\/notes\/index\.html\.erb/, response.body)
    assert_match(/Your archive/, response.body, "the unrendered else-branch is parked in the page")
    assert_match(/Preview follows the cursor/, response.body, "the hover-only branch is parked in the page")

    assert_select 'button[data-herb-set="tab=inbox"]'
    assert_select 'button[data-herb-set="tab=archive"]'
    assert_select 'button[data-herb-increment="unread"][data-herb-by="2"]'
    assert_select 'button[data-herb-decrement="unread"]'
    assert_select "button[data-herb-reset]"
    assert_select 'button[data-herb-set="keydown.meta+k@window->palette=true"]'
    assert_select '[data-herb-action="$refresh"]'
    assert_select 'div[data-herb-set*="mouseenter->preview=true"]'
    assert_select 'textarea[data-herb-reset="keydown.esc->draft"]'
  end

  test "the compiled manifest carries states, bindings and no server deps" do
    get notes_path

    assert_response :success

    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json, "the page must carry its client manifest"
    manifest = JSON.parse(json).values.first

    declarations = manifest.dig("states", "declarations")
    names = declarations.map { |d| d["name"] }
    assert_includes names, "tab"
    assert_equal "integer", declarations.find { |d| d["name"] == "unread" }["kind"]
    assert_equal "integer", declarations.find { |d| d["name"] == "done_count" }["kind"]
    assert_equal "string", declarations.find { |d| d["name"] == "draft" }["kind"]

    busy = declarations.find { |d| d["name"] == "busy" }
    assert_equal "composing", busy["derived"].first, "a derived state names its source"

    # Row-scoped state: one declaration per keyed row rendering
    assert_includes names, "done"
    assert_kind_of Integer, declarations.find { |d| d["name"] == "done" }["scope"], "the row state's scope is the collection slot, not the region"

    presence = manifest.dig("states", "presence")
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "done" },
      "the checkbox binds the row state through the presence map"
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "draft" && p[2] == "blank" },
      "disabled=<%= draft.blank? %> is compiled as a presence binding"

    computed = manifest.dig("states", "computed")
    assert computed.values.any? { |c| c[3] == "length" }, "draft.length is a computed read"

    server = manifest.dig("states", "server")
    assert_empty server["branches"]
    assert_empty server["reads"]
  end

  test "counting fold reads the integer default after the loop" do
    get notes_path

    assert_response :success
    assert_match(/<!--herb-slot:\d+-->0<!--\/herb-slot:\d+--> done/, response.body, "the counted total renders as a live slot")
  end

  test "$refresh reaches the server with the browser's tab state" do
    get notes_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/notes/index.html.erb" => { "tab" => "archive" } }.to_json
    }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal "app/views/notes/index.html.erb", payload["template"]
    # The archive list is what herb_state("tab", "inbox") loaded server-side
    assert_match(/Archive note|counting folds/, response.body)
  end
end
