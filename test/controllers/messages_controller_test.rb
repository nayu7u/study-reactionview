require "test_helper"

# What is covered here: the reactive contract of MessagesController —
# the plain HTML render, the state read back from Herb-State, and the
# slots response that an optimistic form add consumes. Data comes from
# the fixtures, so every parsed slots payload is deterministic.
class MessagesFlowTest < ActionDispatch::IntegrationTest
  test "index renders the keyed message list" do
    get messages_path

    assert_response :success
    assert_select "h1", "Messages"
    assert_select 'button[data-herb-toggle="composing"]'
    assert_select 'input[data-herb-set="query=$value"][data-herb-debounce="250"]'
    assert_select 'ul[data-herb-name="messages"]' do
      assert_select "li", 3
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
    collection = payload["slots"].values.find { |slot| slot["items"] }
    # newest fixture first, oldest last
    assert_equal [messages(:review).id.to_s, messages(:green).id.to_s, messages(:deploy).id.to_s], collection["order"]
  end

  test "a typed query filters the rows through herb_state" do
    get messages_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => {
        "app/views/messages/index.html.erb" => { "order" => "oldest", "query" => "deploy" }
      }.to_json
    }

    assert_response :success

    payload = JSON.parse(response.body)
    sentence = payload["slots"].values.find { |slot| slot["statics"]&.include?("Showing messages matching") }
    assert sentence, "the query sentence answered with its matching branch"
    assert_includes sentence["slots"].values, "deploy"
    collection = payload["slots"].values.find { |slot| slot["items"] }
    assert_equal [messages(:deploy).id.to_s], collection["order"], "only the matching row is returned"
    assert_includes collection["items"].values.first.values, "Deploying after lunch."
  end

  test "create answers a slots add with the new keyed row" do
    post messages_path(format: "slots"),
      params: { message: { body: "Posted by the integration test." } },
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :created

    payload = JSON.parse(response.body)
    collection = payload["slots"].values.find { |slot| slot["items"] }
    items = collection["items"]
    assert_equal 1, items.size
    # Part indexes renumber as the template evolves, so match by value
    assert_includes items.values.first.values, "Posted by the integration test."
  end

  test "create redirects without JavaScript" do
    post messages_path, params: { message: { body: "Plain form post." } }

    assert_redirected_to messages_path
  end
end
