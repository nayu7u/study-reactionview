class CreateTreeNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :tree_nodes do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.integer :parent_id
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :tree_nodes, :parent_id
    add_foreign_key :tree_nodes, :tree_nodes, column: :parent_id
  end
end
