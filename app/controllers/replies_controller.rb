class RepliesController < ApplicationController
  def create
    @post = Post.find(params[:post_id])
    @post.replies.create!(reply_params)
    redirect_to thread_path, notice: "返信しました"
  end

  private

  def reply_params
    params.require(:reply).permit(:body)
  end
end
