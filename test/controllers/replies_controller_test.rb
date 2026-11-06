require "test_helper"

class RepliesControllerTest < ActionDispatch::IntegrationTest
  test "creating a reply redirects with a flash and adds the reply" do
    assert_difference -> { Reply.count }, 1 do
      post post_replies_path(posts(:one)), params: { reply: { body: "返信です" } }
    end

    assert_redirected_to thread_path
    follow_redirect!
    assert_select ".flash", text: /返信しました/
    assert_select ".thread-reply", text: "返信です"
  end

  test "the reply form is a standard POST" do
    get thread_path

    assert_select "form[action='#{post_replies_path(posts(:one))}'][method='post']"
    assert_select "form[data-herb-into]", count: 0
  end
end
