class TreesController < ApplicationController
  def index
    nodes = TreeNode.ordered.to_a
    @children_by_parent = nodes.group_by(&:parent_id)
    @roots = @children_by_parent[nil] || []
    @node_count = nodes.size
    @folder_count = nodes.count { |node| node.kind == "folder" }
    @loaded_at = Time.current
  end
end
