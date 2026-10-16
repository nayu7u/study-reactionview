require "test_helper"

# What is covered here: the reactive contract of MessagesController —
# the plain HTML render, the state read back from Herb-State, and the
# slots response that an optimistic form add consumes.
class MessagesFlowTest < ActionDispatch::IntegrationTest
  test "index renders the keyed message list" do
    get messages_path

    assert_response :success
    assert_select "h1", "Messages"
    assert_select 'button[data-herb-toggle="composing"]'
    assert_select 'ul[data-herb-name="messages"]' do
      assert_select "li", Message.count
    end
  end

  test "index orders by the herb_state the browser sent" do
    get messages_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { "app/views/messages/index.html.erb" => { "order" => "newest" } }.to_json
    }

    assert_response :success
    assert_equal "application/vnd.herb.slots+json", response.media_type
    assert response.headers["Cache-Control"].include?("no-store")

    payload = JSON.parse(response.body)
    order = payload.dig("slots", "1", "order")
    assert_equal Message.order(created_at: :desc).ids.map(&:to_s), order
  end

  test "create answers a slots add with the new keyed row" do
    post messages_path(format: "slots"),
      params: { message: { body: "Posted by the integration test." } },
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :created

    payload = JSON.parse(response.body)
    items = payload.dig("slots", "1", "items")
    assert_equal 1, items.size
    body = items.values.first["3"]
    assert_equal "Posted by the integration test.", body
  end

  test "create redirects without JavaScript" do
    post messages_path, params: { message: { body: "Plain form post." } }

    assert_redirected_to messages_path
  end
end
