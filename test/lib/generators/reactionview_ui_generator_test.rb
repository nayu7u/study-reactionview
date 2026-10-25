# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/reactionview_ui/component/component_generator"

# What is covered here: the copy-source distribution step itself — the
# generator must land the fragment VERBATIM (copy_file, not template, or
# Thor would evaluate the herb directives and ERB tags in the source).
class ReactionviewUiComponentGeneratorTest < Rails::Generators::TestCase
  tests ReactionviewUi::ComponentGenerator
  destination File.join(Dir.tmpdir, "reactionview_ui_generator_test")
  setup :prepare_destination

  test "copies the fragment verbatim into app/views/components/ui" do
    run_generator ["switch"]

    path = "app/views/components/ui/_switch.html.erb"
    assert_file path
    assert_file path, /herb:state \(on: false\)/
    assert_file path, /checked="<%= on %>"/
  end

  test "unknown component names fail loudly with the catalog" do
    output = capture(:stderr) { run_generator ["nonexistent"] }
    # Thor rescues Thor::Error itself and reports on stderr; the contract we
    # actually care about is that nothing lands in the app
    assert_match(/Unknown component: nonexistent/, output)
    assert_match(/Available: accordion, badge/, output)
    assert_no_file "app/views/components/ui/_nonexistent.html.erb"
  end
end
