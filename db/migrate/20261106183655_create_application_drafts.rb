class CreateApplicationDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :application_drafts do |t|
      t.string :speaker_name
      t.string :email
      t.string :title
      t.text :abstract
      t.string :category
      t.timestamps
    end
  end
end
