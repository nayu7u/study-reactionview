class TasksController < ApplicationController
  def index
    direction = herb_state("order", "oldest") == "newest" ? :desc : :asc

    @tasks = Task.order(created_at: direction)

    term = herb_state("query", "")
    @tasks = @tasks.where("title LIKE ?", "%#{term}%") if term.present?
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
      format.html { redirect_to root_path }
    end
  end
end
