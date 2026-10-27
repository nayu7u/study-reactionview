class PricingController < ApplicationController
  PLANS = {
    "starter" => { label: "Starter", price: 1_200, blurb: "小さく始める" },
    "team" => { label: "Team", price: 2_400, blurb: "チームで使う" },
    "business" => { label: "Business", price: 4_000, blurb: "統制と安心" }
  }.freeze

  SEAT_MIN = 1
  SEAT_MAX = 50
  VOLUME_THRESHOLD = 10
  VOLUME_PERCENT = 10
  ANNUAL_PERCENT = 15
  TAX_PERCENT = 10
  SUPPORT_FEE = 10_000

  def index
    requested_plan = herb_state("plan", "team")
    plan_key = PLANS.key?(requested_plan) ? requested_plan : "team"
    @plan_key = plan_key
    @plan = PLANS.fetch(plan_key)
    @plans = PLANS

    @seats = integer_state("seats", 5).clamp(SEAT_MIN, SEAT_MAX)
    @annual = boolean_state("annual", false)
    @support = boolean_state("support", false)

    @seat_fee = @plan[:price] * @seats
    @volume_discount = @seats >= VOLUME_THRESHOLD ? @seat_fee * VOLUME_PERCENT / 100 : 0
    @support_fee = @support ? SUPPORT_FEE : 0
    monthly_subtotal = @seat_fee - @volume_discount + @support_fee
    @months = @annual ? 12 : 1
    @subtotal = monthly_subtotal * @months
    @annual_discount = @annual ? @subtotal * ANNUAL_PERCENT / 100 : 0
    @discounted = @subtotal - @annual_discount
    @tax = @discounted * TAX_PERCENT / 100
    @total = @discounted + @tax
  end
end
