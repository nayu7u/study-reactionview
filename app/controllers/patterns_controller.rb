class PatternsController < ApplicationController
  PER_PAGE = 6 # : Integer
  PRIORITIES = { 1 => "低", 2 => "中", 3 => "高" }.freeze # : Hash[Integer, String]

  helper_method :priority_label

  def index
    # Every state is read here as well as in the view: the first render and
    # each slots round trip must honour the browser's chips/page/selection
    # (the hub learned this the hard way — see AGENTS.md).
    priority = herb_state("priority", "all")
    page = integer_state("page", 1)
    selected_id = integer_state("selected_id", 0)

    scope = Task.order(created_at: :desc, id: :desc)
    scope = scope.where(priority: priority.to_i) unless priority == "all"

    @total = scope.count
    @chip_counts = Task.group(:priority).count
    @tasks = scope.limit(page * PER_PAGE).to_a
    @remaining = [ @total - @tasks.size, 0 ].max
    @selected = selected_id.positive? ? Task.find_by(id: selected_id) : nil
    # Why the view compares task ids against this ivar instead of the
    # `selected_id` state: the compiler only accepts state comparisons
    # against literals (measured: `task.id == selected_id` inside the loop
    # is ErrorInTemplate), so the per-row highlight rides as a plain
    # server-read attribute slot.
    @selected_id = selected_id
  end

  def priority_label(priority)
    PRIORITIES.fetch(priority, "?")
  end

  private

  # herb_state returns the raw JSON value from the header untyped (the real
  # client type-checks literals against the declaration kind, but a crafted
  # header may send "12" as a string), so browser-supplied numbers are cast
  # defensively instead of calling Integer-only methods on them.
  def integer_state(name, default)
    Integer(herb_state(name, default))
  rescue TypeError, ArgumentError
    default
  end
end
