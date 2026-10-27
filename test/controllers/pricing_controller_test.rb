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

  def condition_states(condition)
    case condition
    when Array
      if condition.first.is_a?(String)
        [ condition.first ]
      else
        condition.flat_map { |part| condition_states(part) }
      end
    when Hash
      condition.values.flat_map { |value| condition_states(value) }
    else
      []
    end
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

  test "a crafted header renders the normalized plan and seats" do
    slots({ "plan" => "nope", "seats" => 999, "annual" => "false", "support" => "false" })

    assert_response :success
    values = JSON.parse(response.body)["slots"].values
    assert_includes values, "Team: チームで使う"
    assert_includes values, "50"
    refute_includes values, "999", "the raw out-of-range seat count must not reach the response"

    slots({ "plan" => "starter", "seats" => -3, "annual" => false, "support" => false })

    assert_response :success
    values = JSON.parse(response.body)["slots"].values
    assert_includes values, "Starter: 小さく始める"
    refute_includes values, "-3", "the raw negative seat count must not reach the response"
  end

  test "tax rounds down at the yen boundary" do
    slots({ "plan" => "starter", "seats" => 11, "annual" => true, "support" => true })

    assert_response :success
    # 21,880 monthly × 12 = 262,560; -15% = 223,176; tax 22,317.6 floors to 22,317.
    assert_includes JSON.parse(response.body)["slots"].values, "¥22,317"
    assert_includes JSON.parse(response.body)["slots"].values, "¥245,493"
  end

  test "index renders the plan controls, the seat stepper and the billing toggle" do
    get pricing_path

    assert_response :success
    assert_select ".plan-card", count: 3
    assert_select 'button.plan-card[data-herb-set="plan=starter"]'
    assert_select 'button.plan-card[data-herb-set="plan=team"]'
    assert_select 'button.plan-card[data-herb-set="plan=business"]'
    assert_select '.plan-card[aria-pressed="true"]', count: 1
    assert_select 'button[data-herb-decrement="seats"][data-herb-action="$refresh"]'
    assert_select 'button[data-herb-increment="seats"][data-herb-action="$refresh"]'
    assert_select 'button[data-herb-set="annual=false"]'
    assert_select 'button[data-herb-set="annual=true"]'
    assert_select 'button[data-herb-set="support=false"]'
    assert_select 'button[data-herb-set="support=true"][aria-pressed="false"]'
    assert_select ".price-total", text: /¥13,200/
  end

  test "the site navigation links to pricing" do
    get pricing_path

    assert_select ".site-nav a[href=?]", pricing_path, text: "Pricing"
  end

  test "the manifest carries the four states and their steering conditionals" do
    get pricing_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    manifest = JSON.parse(json).values.first

    names = manifest.dig("states", "declarations").map { |d| d["name"] }
    %w[plan seats annual support].each { |name| assert_includes names, name }

    conditions = manifest.dig("states", "conditionals").values
      .flat_map { |c| Array(c["arms"]) }
      .flat_map { |a| condition_states(a["condition"]) }
    %w[plan seats annual support].each { |name| assert_includes conditions, name }

    presence_states = manifest.dig("states", "presence").values
      .select { |p| p.is_a?(Array) }
      .map(&:first)
    assert_includes presence_states, "seats"
  end

  test "the plan branch answers the selected plan" do
    slots({ "plan" => "business", "seats" => 5, "annual" => false, "support" => false })

    assert_response :success
    arm = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("統制と安心")
    end
    assert arm, "the selected plan's description arm is served"
  end

  test "the volume discount is a presence toggle with a top-level value" do
    slots({ "plan" => "team", "seats" => 9, "annual" => false, "support" => false })

    values = JSON.parse(response.body)["slots"].values
    assert_equal 1, values.count("¥2,400"), "only the Team plan card price is present below ten seats"

    slots({ "plan" => "team", "seats" => 10, "annual" => false, "support" => false })

    values = JSON.parse(response.body)["slots"].values
    assert_equal 2, values.count("¥2,400"), "the plan card price and the volume discount are both present at ten seats"

    get pricing_path

    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    manifest = JSON.parse(json).values.first
    presence = manifest.dig("states", "presence").values.select { |p| p.is_a?(Array) }
    assert presence.any? { |p| p[0] == "seats" && p[1] == { "value" => 10 } && p[2] == "<" },
      "the discount line is hidden below ten seats"
    assert presence.any? { |p| p[0] == "seats" && p[1] == { "value" => 10 } && p[2] == ">=" },
      "the hint line is hidden at ten or more seats"
  end

  test "the annual discount is a presence toggle with a top-level value" do
    slots({ "plan" => "team", "seats" => 5, "annual" => true, "support" => false })

    assert_response :success
    arm = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("年払い割引")
    end
    assert arm, "the annual discount arm is served"
    assert_includes JSON.parse(response.body)["slots"].values, "¥21,600",
      "the discount value stays outside the branch as a top-level READ slot"
  end

  test "the support line is a presence toggle with a top-level fee" do
    slots({ "plan" => "team", "seats" => 5, "annual" => false, "support" => true })

    assert_response :success
    arm = JSON.parse(response.body)["slots"].values.find do |slot|
      slot.is_a?(Hash) && slot["statics"].is_a?(String) && slot["statics"].include?("優先サポート")
    end
    assert arm, "the support arm is served"
    assert_includes JSON.parse(response.body)["slots"].values, "¥10,000",
      "the add-on value stays outside the branch as a top-level READ slot"
  end

  test "the breakdown carries every money line for the combined quote" do
    slots({ "plan" => "business", "seats" => 12, "annual" => true, "support" => true })

    assert_response :success
    values = JSON.parse(response.body)["slots"].values
    %w[¥4,800 ¥95,760 ¥10,000 ¥54,264 ¥596,904].each do |amount|
      assert values.any? { |value| value == amount || (value.is_a?(Hash) && value["slots"]&.values&.include?(amount)) },
        "expected #{amount} in the top-level slots or a branch's slots"
    end
  end
end
