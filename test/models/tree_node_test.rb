require "test_helper"

class TreeNodeTest < ActiveSupport::TestCase
  test "a fixture folder is valid" do
    assert tree_nodes(:app).valid?
  end

  test "requires a name and a known kind" do
    node = tree_nodes(:app)
    node.name = ""
    node.kind = "symlink"

    assert_not node.valid?
    assert node.errors[:name].any?
    assert node.errors[:kind].any?
  end

  test "a node points at its parent and lists ordered children" do
    assert_equal tree_nodes(:app), tree_nodes(:app_views).parent
    assert_equal %w[views models], tree_nodes(:app).children.map(&:name)
  end

  test "destroying a folder destroys its descendants" do
    app = tree_nodes(:app)
    views = tree_nodes(:app_views)
    index = tree_nodes(:trees_index)

    app.destroy

    assert_not TreeNode.exists?(views.id)
    assert_not TreeNode.exists?(index.id)
  end
end
