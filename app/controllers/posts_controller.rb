class PostsController < ApplicationController
  def index
    @posts = Post.includes(:replies).order(:created_at)
  end
end
