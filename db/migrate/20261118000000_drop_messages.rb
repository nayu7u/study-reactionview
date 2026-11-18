class DropMessages < ActiveRecord::Migration[8.1]
  def change
    drop_table :messages, if_exists: true
  end
end
