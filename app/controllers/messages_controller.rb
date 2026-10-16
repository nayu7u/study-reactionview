class MessagesController < ApplicationController
  def index
    direction = herb_state("order", "oldest") == "newest" ? :desc : :asc

    @messages = Message.order(created_at: direction)

    term = herb_state("query", "")
    @messages = @messages.where("body LIKE ?", "%#{term}%") if term.present?
  end

  def create
    message = Message.create!(params.require(:message).permit(:body).merge(author: "You"))

    # The slots branch answers the client's optimistic add (data-herb-into),
    # which reads the new row back through this very template. Why not render
    # a partial: the row markup must be identical to the one already on screen
    # or the keyed diff has nothing to match.
    respond_to do |format|
      format.slots do
        @messages = Message.where(id: message.id)
        render :index, status: :created
      end

      # The no-JavaScript fallback stays a plain redirect so the form keeps
      # working with the client unloaded.
      format.html { redirect_to messages_path }
    end
  end
end
