require "test_helper"

class SubmissionsControllerTest < ActionDispatch::IntegrationTest
  test "outbox renders the form and the submissions" do
    get outbox_path

    assert_response :success
    assert_select "h1", "Submission Queue"
    assert_select "form[action='#{outbox_path}'][data-herb-into='submissions']"
    assert_select "ul[data-herb-name='submissions']"
    assert_select ".outbox-row", count: Submission.count
  end

  test "a normal slots post answers 201 with the new row" do
    assert_difference -> { Submission.count }, 1 do
      post outbox_path(format: :slots), params: { submission: { title: "スロット送信" } },
        headers: { "Accept" => "application/vnd.herb.slots+json" }
    end

    assert_response :created
    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot.is_a?(Hash) && slot["items"] }
    assert_includes collection["items"].values.first.values, "スロット送信"
  end

  test "a normal HTML post redirects with a notice" do
    post outbox_path, params: { submission: { title: "HTML送信" } }

    assert_redirected_to outbox_path
    follow_redirect!
    assert_select ".flash", text: /送信しました/
  end

  test "a fail_once slots post answers 500 and keeps the session flag" do
    assert_no_difference -> { Submission.count } do
      post outbox_path(format: :slots), params: { submission: { title: "失敗" }, fail_once: "1" },
        headers: { "Accept" => "application/vnd.herb.slots+json" }
    end

    assert_response :internal_server_error
    assert session[:outbox_failed_once]
  end

  test "the retry succeeds on the second attempt" do
    post outbox_path(format: :slots), params: { submission: { title: "再試行" }, fail_once: "1" },
      headers: { "Accept" => "application/vnd.herb.slots+json" }
    assert_response :internal_server_error

    assert_difference -> { Submission.count }, 1 do
      post outbox_path(format: :slots), params: { submission: { title: "再試行" }, fail_once: "1" },
        headers: { "Accept" => "application/vnd.herb.slots+json" }
    end
    assert_response :created
    assert_nil session[:outbox_failed_once]
  end

  test "a fail_once HTML post redirects with an alert" do
    assert_no_difference -> { Submission.count } do
      post outbox_path, params: { submission: { title: "失敗" }, fail_once: "1" }
    end

    assert_redirected_to outbox_path
    follow_redirect!
    assert_select ".flash-alert", text: /送信に失敗しました/
  end

  test "the form still posts without JavaScript" do
    get outbox_path

    assert_select "form[action='#{outbox_path}']"
    assert_select "input[name='submission[title]']"
    assert_select "input[name='fail_once']"
  end
end
