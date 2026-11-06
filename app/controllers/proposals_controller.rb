class ProposalsController < ApplicationController
  before_action :set_proposal, only: %i[edit update confirm_destroy destroy]

  def index
    @proposal = Proposal.new
    @proposals = Proposal.order(created_at: :desc).group_by(&:category)
  end

  def create
    @proposal = Proposal.new(proposal_params)

    if @proposal.save
      redirect_to forms_path, notice: "プロポーザルを送信しました"
    else
      # Why not status: :ok or a slots envelope: the form is a normal HTML
      # form. Rails' 422 is the honest contract, and the browser re-renders
      # the whole document with the invalid values still attached.
      @proposals = Proposal.order(created_at: :desc).group_by(&:category)
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @proposal.assign_attributes(proposal_params)

    if @proposal.save
      redirect_to forms_path, notice: "プロポーザルを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def confirm_destroy; end

  def destroy
    @proposal.destroy
    redirect_to forms_path, notice: "プロポーザルを削除しました"
  end

  private

  def set_proposal
    @proposal = Proposal.find(params[:id])
  end

  def proposal_params
    params.require(:proposal).permit(:speaker_name, :email, :title, :abstract, :category)
  end
end
