module DashboardHelper
  SLOW_SECONDS = 0.9
  PRIORITY_LABELS = { 1 => "低", 2 => "中", 3 => "高" }.freeze

  def slow_demo? = params[:slow] == "1"

  def dashboard_summary
    slow_slots
    {
      total: Task.count,
      high: Task.where(priority: 3).count,
      recent: Task.where(created_at: 24.hours.ago..).count
    }
  end

  def dashboard_priority_label(priority)
    PRIORITY_LABELS.fetch(priority, "?")
  end

  private

  # Why memoize: a slots refetch renders the whole template, so every block
  # helper runs. One 900ms sleep per request keeps the documented latency
  # at 900ms instead of 900ms times the number of blocks.
  def slow_slots
    return unless slow_demo? && request.format.slots?
    return if @slow_slots_slept

    @slow_slots_slept = true
    sleep SLOW_SECONDS
  end
end
