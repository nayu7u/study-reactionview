class AddPriorityToTasks < ActiveRecord::Migration[8.1]
  def change
    # Why an integer 1..3 over a free-form status string: the Patterns
    # screen's filter chips need a small closed set so the per-chip badge
    # counts (Task.group(:priority).count) stay a fixed, orderable trio.
    add_column :tasks, :priority, :integer, null: false, default: 2
  end
end
