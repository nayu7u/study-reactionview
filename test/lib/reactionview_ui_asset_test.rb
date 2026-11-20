require "test_helper"

# What is covered here: the two ways the source-distributed UI kit can drift
# from the app that ships it — a stale aggregate stylesheet, and a token name
# that the host page also reads inside the .ui-root subtree.
class ReactionviewUiAssetTest < ActiveSupport::TestCase
  KIT_ROOT = Rails.root.join("lib/reactionview_ui")
  AGGREGATE = Rails.root.join("app/assets/stylesheets/reactionview_ui.css")

  test "the committed aggregate matches the kit sources" do
    components = Dir[KIT_ROOT.join("components/*.css")].sort.map do |path|
      "/* ---- #{File.basename(path)} ---- */\n" + File.read(path)
    end.join("\n")

    expected = File.read(KIT_ROOT.join("tokens.css")) + "\n" + components

    assert_equal expected, AGGREGATE.read,
      "regenerate reactionview_ui.css with reactionview_ui:install after editing lib/reactionview_ui"
  end

  test "kit tokens do not shadow host tokens inside the ui-root subtree" do
    host_tokens = File.read(Rails.root.join("app/assets/stylesheets/app.css"))
                      .scan(/^\s*:root\s*\{(.*?)^\s*\}/m).flatten
                      .flat_map { |block| block.scan(/(--[\w-]+)\s*:/).flatten }
    kit_tokens = File.read(KIT_ROOT.join("tokens.css")).scan(/(--[\w-]+)\s*:/).flatten

    assert_empty host_tokens & kit_tokens,
      "a host rule inside .ui-root would read the kit value instead of the app value"
  end
end
