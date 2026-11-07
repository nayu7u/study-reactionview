require "test_helper"

# What is covered here: the tree contract — a DB-backed 4-level tree,
# per-folder toggle buttons, no initial hidden list, the per-item open
# state, and a slots response that keeps the children as items/order.
class TreesControllerTest < ActionDispatch::IntegrationTest
  def manifests
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    JSON.parse(json)
  end

  def folder_manifest
    manifests.find { |key, _| key.split(":").first&.end_with?("_folder.html.erb") }&.last
  end

  test "tree renders every node with nested levels and no hidden lists" do
    get tree_path

    assert_response :success
    assert_select "h1", "Tree"
    assert_select ".tree-node", count: TreeNode.count
    assert_select ".tree-folder", count: TreeNode.where(kind: "folder").count
    assert_select ".tree-file", count: TreeNode.where(kind: "file").count
    assert_select "ul.tree-children ul.tree-children ul.tree-children"
    assert_select "button[data-herb-toggle='open']",
      count: TreeNode.where(kind: "folder").count
    assert_select "button[data-herb-action='$refresh']"
    assert_select "[data-herb-name='loaded_at']"
    assert_select "ul.tree-children[hidden]", count: 0
  end

  test "the folder partial declares the per-item open state and hidden presence" do
    get tree_path

    assert_response :success
    manifest = folder_manifest
    assert manifest, "the folder partial has its own manifest entry"

    declarations = manifest.dig("states", "declarations")
    assert declarations.any? { |d| d["name"] == "open" }, "open is a per-item state"

    presence = manifest.dig("states", "presence")
    assert presence.values.any? { |p| p.is_a?(Array) && p[0] == "open" },
      "the children list binds hidden as a presence read on open"
  end

  test "an empty folder renders an empty list shell" do
    TreeNode.create!(name: "empty", kind: "folder", position: 99)
    get tree_path

    assert_select "li.tree-folder" do |folders|
      empty = folders.find { |folder| folder.text.include?("empty") }
      assert empty, "the empty folder is rendered"
      assert_select empty, "ul.tree-children li", count: 0
    end
  end

  test "the slots response carries the tree and the refresh marker" do
    get tree_path(format: :slots),
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :success
    assert_equal "application/vnd.herb.slots+json", response.media_type

    payload = JSON.parse(response.body)
    assert payload["slots"].values.any? { |slot| slot.is_a?(Hash) && slot["items"] },
      "the keyed tree collections arrive as items"
    assert_match(/\d{2}:\d{2}:\d{2}/, response.body, "loaded_at rides the slots response")
    assert_includes response.body, "index.html.erb"
  end
end
