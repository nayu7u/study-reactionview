class CreateTalks < ActiveRecord::Migration[8.1]
  def change
    create_table :talks do |t|
      t.string :title
      t.string :speaker
      t.string :category
      t.text :abstract

      t.timestamps
    end
  end
end
