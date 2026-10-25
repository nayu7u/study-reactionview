require "test_helper"

# Throwaway spike: do component-side `herb:state` declarations (inside a
# rendered partial, not the page template) reach the client manifest at all?
# This decides the reactionview-ui distribution model: partial-owned state
# (like shadcn's internal useState) vs page-declared state.
class UiSpikeTest < ActionDispatch::IntegrationTest
  test "partial-internal herb:state declarations reach the manifest" do
    get ui_path
    assert_response :success

    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    flunk "no manifest template in HTML" unless json

    manifest = JSON.parse(json)
    manifest.each do |template, m|
      decls = m.dig("states", "declarations") || []
      puts "template=#{template}"
      puts "  decls=#{decls.map { |d| d.slice("name", "kind", "scope") }.inspect}"
    end

    names = manifest.values.flat_map { |m| (m.dig("states", "declarations") || []).map { |d| d["name"] } }
    assert_includes names, "on", "top-level state declared inside the toggle partial"
    assert_includes names, "open", "per-item state declared inside the faq partial loop"

    # dump the rendered presence bindings to learn their test-env shape
    body = response.body
    puts "SWITCH: #{body[/\<label class="ui-switch".*?<\/label>/m]&.inspect}"
    puts "FAQ_LI: #{body[/<li>.*?<\/li>/m]&.inspect}"
    puts "slot_markers=#{body.scan(/data-herb-slot="[^"]*"/).uniq.inspect}"

    # presence bindings survive partial extraction: attribute appears only
    # when truthy (hidden = !open = true at init), never as a "true"/"false"
    # value string
    assert_select "input[type=checkbox]", count: 1
    assert_select "input[type=checkbox][checked]", count: 0
    assert_select "div[hidden]", count: 2
  end
end
