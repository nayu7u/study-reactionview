require "test_helper"

# What is covered here: the Settings screen contract — a client-mode form with
# three parked tabs, a dirty state, a derived save gate, and a demo save.
class SettingsFlowTest < ActionDispatch::IntegrationTest
  TEMPLATE = "app/views/settings/index.html.erb"

  def manifest
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    JSON.parse(json).values.first
  end

  test "settings renders the profile tab, tabs, and save bar" do
    get settings_path

    assert_response :success
    assert_select "h1", "Settings"
    assert_select ".settings-nav button", count: 3
    assert_select '.settings-nav button[aria-pressed="true"]', count: 1
    assert_select "#settings_name"
    assert_select "#settings_email"
    assert_select "#settings_bio"
    assert_select ".settings-save"
    assert_select ".settings-save button[disabled]"
    assert_match(/<template data-herb-region=/, response.body)
  end

  test "the manifest declares the profile states and the save gate" do
    get settings_path
    states = manifest.dig("states")

    names = states["declarations"].map { |d| d["name"] }
    %w[tab name email bio public_profile handle dirty saved
       name_ok email_ok bio_ok handle_ok form_ok can_save over].each do |name|
      assert_includes names, name
    end

    form_ok = states["declarations"].find { |d| d["name"] == "form_ok" }
    assert form_ok["derived"].is_a?(Hash) && form_ok["derived"]["all"],
      "the save gate is an AND of the field gates"
    can_save = states["declarations"].find { |d| d["name"] == "can_save" }
    assert can_save["derived"].is_a?(Hash) && can_save["derived"]["all"],
      "can_save is dirty AND form_ok"
    handle_ok = states["declarations"].find { |d| d["name"] == "handle_ok" }
    assert handle_ok["derived"].is_a?(Hash) && handle_ok["derived"]["any"],
      "handle_ok is public_profile false OR a present handle"

    conditions = states["conditionals"].values
      .flat_map { |c| Array(c["arms"]) }
      .map { |a| a["condition"]&.first }
      .compact
    %w[tab public_profile dirty saved].each { |name| assert_includes conditions, name }

    presence = states["presence"].values.select { |p| p.is_a?(Array) }.map(&:first)
    assert_includes presence, "can_save", "the save button's disabled is a presence read"
    assert_includes presence, "public_profile", "the switch binds its boolean state"
  end

  test "notifications and billing panels are parked with dependent fields" do
    get settings_path

    assert_includes response.body, "まとめ通知"
    assert_includes response.body, "年払い"
    assert_includes response.body, "請求書の宛名"
    assert_includes response.body, 'data-herb-set="frequency=daily dirty=true saved=false"'
    assert_includes response.body, 'data-herb-set="plan=starter dirty=true saved=false"'
    assert_includes response.body,
      'data-herb-reset="name email bio public_profile handle digest frequency updates plan annual invoice_name dirty saved"'
  end

  test "the manifest declares the notification and billing states" do
    get settings_path
    states = manifest.dig("states")

    names = states["declarations"].map { |d| d["name"] }
    %w[digest frequency updates plan annual invoice_name].each do |name|
      assert_includes names, name
    end

    conditions = states["conditionals"].values
      .flat_map { |c| Array(c["arms"]) }
      .map { |a| a["condition"]&.first }
      .compact
    %w[digest annual].each { |name| assert_includes conditions, name }

    presence = states["presence"].values.select { |p| p.is_a?(Array) }.map(&:first)
    %w[digest updates annual].each { |name| assert_includes presence, name }
  end
end
