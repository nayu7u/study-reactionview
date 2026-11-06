class ApplicationsController < ApplicationController
  def show
    @step = normalized_step
    @application = current_application
    @application.step = @step
  end

  def update
    @step = normalized_step
    @application = current_application
    @application.assign_attributes(application_params) if params[:application_draft].present?
    @application.step = @step

    if @application.valid?
      @application.save!

      if @step < 3
        redirect_to apply_path(step: @step + 1)
      else
        submit
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def normalized_step
    step = params[:step].to_i
    step = 1 if step < 1
    step = 3 if step > 3
    step
  end

  def current_application
    @current_application ||= ApplicationDraft.find_by(id: session[:application_draft_id]) || begin
      draft = ApplicationDraft.create!(step: 0)
      session[:application_draft_id] = draft.id
      draft
    end
  end

  def application_params
    params.require(:application_draft).permit(:speaker_name, :email, :title, :abstract, :category)
  end

  def submit
    # Why a transaction: the proposal must not exist without consuming the
    # draft, and the draft must not vanish without the proposal.
    ApplicationDraft.transaction do
      Proposal.create!(@application.proposal_attributes)
      @application.destroy!
    end
    session.delete(:application_draft_id)
    redirect_to forms_path, notice: "プロポーザルを送信しました"
  end
end
