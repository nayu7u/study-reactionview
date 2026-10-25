class TasksController < ApplicationController
  def index
    direction = herb_state("order", "oldest") == "newest" ? :desc : :asc

    # A raw % or _ in the query would widen the match beyond what the
    # toolbar showed, so escape them and declare the escape char as a bind
    # param (keeps one backslash literal without double-escaping mazes).
    esc = "\\"
    term = herb_state("query", "").gsub(/[%_\\]/) { "#{esc}#{$&}" }
    where = term.blank? ? nil : [ "title LIKE ? ESCAPE ?", "%#{term}%", esc ]

    @tasks = Task.order(created_at: direction)
    @tasks = @tasks.where(*where) if where
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
      format.html do
        flash[:notice] = "タスクを追加しました"
        redirect_to root_path
      end
    end
  end
end
