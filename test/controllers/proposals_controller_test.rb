require "test_helper"

# What is covered here: the standard HTML write path. The form deliberately
# does not carry data-herb-into, so a 422 renders a whole document and the
# slots client never applies the error body.
class ProposalsControllerTest < ActionDispatch::IntegrationTest
  test "index renders the form and the grouped list without a slots write" do
    get forms_path

    assert_response :success
    assert_select "h1", "Proposal Submission"
    assert_select "form[action='#{forms_path}'][method='post']"
    assert_select "form[data-herb-into]", count: 0
    assert_select "form[novalidate]", count: 1
    assert_select "input[name='proposal[speaker_name]']"
    assert_select "input[name='proposal[email]'][type='email']"
    assert_select "input[name='proposal[title]']"
    assert_select "textarea[name='proposal[abstract]']"
    assert_select "select[name='proposal[category]']"
    assert_select ".proposal-group", count: 3
    assert_select ".proposal-card", count: Proposal.count
  end

  test "an invalid submission answers 422 HTML with errors and preserved values" do
    post forms_path, params: { proposal: {
      speaker_name: "", email: "not-an-email", title: "短い",
      abstract: "短い", category: "unknown"
    } }

    assert_response :unprocessable_entity
    assert_equal "text/html", response.media_type
    assert_select ".form-errors[role='alert']"
    assert_select ".field-error", minimum: 3
    assert_select "input[name='proposal[email]'][value='not-an-email']"
    assert_select "input[name='proposal[title]'][value='短い']"
    assert_includes css_select("textarea[name='proposal[abstract]']").first.text, "短い"
  end

  test "a long invalid abstract is preserved in full" do
    long = "あ" * 601

    post forms_path, params: { proposal: {
      speaker_name: "山田 太郎", email: "taro@example.com",
      title: "長すぎる概要のテスト", abstract: long, category: "rails"
    } }

    assert_response :unprocessable_entity
    assert_includes css_select("textarea[name='proposal[abstract]']").first.text, long
  end

  test "user input is escaped in the 422 response" do
    post forms_path, params: { proposal: {
      speaker_name: "山田 太郎", email: "taro@example.com",
      title: "<script>alert(1)</script>", abstract: "<script>alert(2)</script>",
      category: "rails"
    } }

    assert_response :unprocessable_entity
    assert_no_match(/<script>alert/, response.body)
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "a valid submission creates a proposal and redirects" do
    assert_difference -> { Proposal.count }, 1 do
      post forms_path, params: { proposal: {
        speaker_name: "田中 次郎", email: "jiro@example.com",
        title: "標準フォームで作るサーバー検証",
        abstract: "422の応答を全画面で描き直し、入力値とエラーを保持する構成を紹介します。",
        category: "rails"
      } }
    end

    assert_redirected_to forms_path
    follow_redirect!
    assert_select ".flash", text: /プロポーザルを送信しました/
    assert_select ".proposal-card", text: /標準フォームで作るサーバー検証/
  end

  test "an empty database still renders the form and three empty groups" do
    Proposal.delete_all

    get forms_path

    assert_response :success
    assert_select "form[action='#{forms_path}']"
    assert_select ".proposal-card", count: 0
    assert_select ".proposal-group", count: 3
    assert_select ".proposal-group .task-note", count: 3
  end

  test "a slots POST of invalid data answers 422 slots, which the client discards" do
    post forms_path(format: "slots"),
      params: { proposal: {
        speaker_name: "", email: "bad", title: "", abstract: "", category: ""
      } },
      headers: { "Accept" => "application/vnd.herb.slots+json" }

    assert_response :unprocessable_entity
    assert_equal "application/vnd.herb.slots+json", response.media_type
    payload = JSON.parse(response.body)
    assert_includes payload["template"], "app/views/proposals/index.html.erb"
  end

  test "the client filter declares one state and three hidden presences" do
    get forms_path

    assert_response :success
    json = response.body[/<template data-herb-manifests[^>]*>(\{.*?\})<\/template>/m, 1]
    assert json
    manifest = JSON.parse(json).values.first

    declarations = manifest.dig("states", "declarations")
    assert_equal [ "filter_category" ], declarations.map { |d| d["name"] }
    assert_equal "region", declarations.first["scope"]

    presence = manifest.dig("states", "presence")
    assert_equal 3, presence.size
    assert presence.values.all? { |condition| JSON.generate(condition).include?("filter_category") }

    assert_select ".filter-chip", count: 4
    assert_select ".proposal-group[hidden]", count: 0
    assert_equal "すべて", css_select(".filter-chip[aria-pressed='true']").first.text.strip
  end
end
