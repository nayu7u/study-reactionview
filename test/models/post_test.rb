require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "a fixture post is valid" do
    assert posts(:one).valid?
  end

  test "requires a title" do
    post = posts(:one)
    post.title = ""
    assert_not post.valid?
    assert post.errors[:title].any?
  end

  test "destroys its replies" do
    post = posts(:one)
    assert_difference -> { Reply.count }, -post.replies.count do
      post.destroy
    end
  end
end

class ReplyTest < ActiveSupport::TestCase
  test "a fixture reply is valid" do
    assert replies(:one).valid?
  end

  test "requires a body" do
    reply = replies(:one)
    reply.body = ""
    assert_not reply.valid?
    assert reply.errors[:body].any?
  end
end
