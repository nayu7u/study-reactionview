class SubmissionsController < ApplicationController
  def index
    @submissions = Submission.order(created_at: :desc)
    @submission = Submission.new
  end

  def create
    if params[:fail_once] == "1" && !session[:outbox_failed_once]
      session[:outbox_failed_once] = true
      respond_to do |format|
        format.slots { head :internal_server_error }
        format.html { redirect_to outbox_path, alert: "送信に失敗しました（デモ）" }
      end
      return
    end

    session.delete(:outbox_failed_once)
    submission = Submission.new(submission_params)

    unless submission.save
      respond_to do |format|
        format.slots { head :unprocessable_entity }
        format.html { redirect_to outbox_path, alert: submission.errors.full_messages.to_sentence }
      end
      return
    end

    respond_to do |format|
      format.slots do
        @submission = Submission.new
        @submissions = Submission.where(id: submission.id)
        render :index, status: :created
      end
      format.html { redirect_to outbox_path, notice: "送信しました" }
    end
  end

  private

  def submission_params
    params.require(:submission).permit(:title)
  end
end
