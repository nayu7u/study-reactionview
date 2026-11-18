class TriageController < ApplicationController
  def index
    @tasks = Task.order(:id)
  end

  def update
    ids = params[:ids].is_a?(Array) ? params[:ids].map(&:to_i).select(&:positive?) : []

    if ids.empty?
      redirect_to triage_path, alert: "タスクを選択してください"
      return
    end

    priority = Integer(params[:priority])
    unless (1..3).cover?(priority)
      redirect_to triage_path, alert: "優先度を選んでください"
      return
    end

    count = Task.where(id: ids).update_all(priority: priority, updated_at: Time.current)
    redirect_to triage_path, notice: "#{count}件の優先度を更新しました"
  rescue ArgumentError, TypeError
    redirect_to triage_path, alert: "優先度を選んでください"
  end
end
