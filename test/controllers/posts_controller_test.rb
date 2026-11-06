require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  test "thread renders posts and nested replies" do
    get thread_path

    assert_response :success
    assert_select "h1", "Thread"
    assert_select ".thread-post", count: Post.count
    assert_select ".thread-reply", count: Reply.count
    assert_select "[data-herb-action='$refresh']"
    assert_select "form[action='#{post_replies_path(posts(:one))}']"
    assert_select ".thread-post", text: /2 件の返信/
  end

  test "the slots response carries the posts and replies" do
    get thread_path(format: :slots), headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["slots"].values.any? { |slot| slot.is_a?(Hash) && slot["items"] }
    assert_includes response.body, "最初の返信"
  end
end
