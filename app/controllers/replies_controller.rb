class RepliesController < ApplicationController
  def create
    @post = Post.find(params[:post_id])
    reply = @post.replies.build(reply_params)

    if reply.save
      redirect_to thread_path, notice: "返信しました"
    else
      redirect_to thread_path, alert: reply.errors.full_messages.to_sentence
    end
  end

  private

  def reply_params
    params.require(:reply).permit(:body)
  end
end
