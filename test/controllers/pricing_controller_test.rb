require "test_helper"

# What is covered here: the Pricing screen contract — server-side quote
# calculation for plans, volume discount, annual discount, support and tax.
# The interactive controls and steering are added in Task 2.
class PricingControllerTest < ActionDispatch::IntegrationTest
  TEMPLATE = "app/views/pricing/index.html.erb"

  def slots(state)
    get pricing_path(format: "slots"), headers: {
      "Accept" => "application/vnd.herb.slots+json",
      "Herb-State" => { TEMPLATE => state }.to_json
    }
  end

  test "index renders the default quote" do
    get pricing_path

    assert_response :success
    assert_select "h1", "Pricing"
    assert_select ".price-total", text: /¥13,200/
  end

  test "the default slots answer carries the server-calculated total" do
    slots({ "plan" => "team", "seats" => 5, "annual" => false, "support" => false })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥13,200"
  end

  test "business, 12 seats, annual and support total is calculated server-side" do
    slots({ "plan" => "business", "seats" => 12, "annual" => true, "support" => true })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥596,904"
  end

  test "annual without support total is calculated server-side" do
    slots({ "plan" => "team", "seats" => 5, "annual" => true, "support" => false })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥134,640"
  end

  test "unknown plan falls back to team and seats clamp to the range" do
    slots({ "plan" => "nope", "seats" => 999, "annual" => false, "support" => false })

    assert_response :success
    # Team 50 seats monthly: 120,000 - 12,000 = 108,000; tax 10,800; total 118,800.
    assert_includes JSON.parse(response.body)["slots"].values, "¥118,800"

    slots({ "plan" => "starter", "seats" => 0, "annual" => false, "support" => false })

    assert_response :success
    # Starter 1 seat monthly: 1,200; tax 120; total 1,320.
    assert_includes JSON.parse(response.body)["slots"].values, "¥1,320"
  end

  test "string boolean states are read defensively" do
    slots({ "plan" => "team", "seats" => 5, "annual" => "true", "support" => "false" })

    assert_response :success
    assert_includes JSON.parse(response.body)["slots"].values, "¥134,640"
  end

  test "tax rounds down at the yen boundary" do
    slots({ "plan" => "starter", "seats" => 11, "annual" => true, "support" => true })

    assert_response :success
    # 21,880 monthly × 12 = 262,560; -15% = 223,176; tax 22,317.6 floors to 22,317.
    assert_includes JSON.parse(response.body)["slots"].values, "¥22,317"
    assert_includes JSON.parse(response.body)["slots"].values, "¥245,493"
  end
end
