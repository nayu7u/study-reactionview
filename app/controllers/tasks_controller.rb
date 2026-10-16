class TasksController < ApplicationController
  def index
    @tasks = Task.order(:id)
  end

  def create
    task = Task.create!(params.require(:task).permit(:title))

    # The slots answer hands the keyed single row back for the optimistic
    # splice (data-herb-into). Why not a partial: the row markup must be the
    # exact statics the keyed diff matches, i.e. render the same template.
    respond_to do |format|
      format.slots do
        @tasks = Task.where(id: task.id)
        render :index, status: :created
      end

      # No-JavaScript fallback: the modal form posts like any other form.
      format.html { redirect_to board_path }
    end
  end
end
