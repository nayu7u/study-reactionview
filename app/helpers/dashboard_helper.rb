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

  def recent_activity
    slow_slots
    Task.order(created_at: :desc).limit(5)
  end

  def dashboard_time_ago(time)
    seconds = (Time.current - time).to_i
    return "#{seconds / 3600}時間前" if seconds >= 3600
    return "#{seconds / 60}分前" if seconds >= 60

    "たった今"
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
