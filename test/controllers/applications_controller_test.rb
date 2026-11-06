require "test_helper"

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "apply starts at step 1 and creates a draft" do
    assert_difference -> { ApplicationDraft.count }, 1 do
      get apply_path
    end

    assert_response :success
    assert_select "h1", "プロポーザルを応募"
    assert_select "input[name='application_draft[speaker_name]']"
    assert_select "input[name='application_draft[email]']"
    assert session[:application_draft_id]
  end

  test "an invalid step 1 answers 422 with errors and values" do
    get apply_path

    patch apply_path(step: 1), params: { application_draft: { speaker_name: "", email: "not-an-email" } }

    assert_response :unprocessable_entity
    assert_equal "text/html", response.media_type
    assert_select ".form-errors[role='alert']"
    assert_select ".field-error", minimum: 2
    assert_select "input[name='application_draft[email]'][value='not-an-email']"
    assert_select "input[name='application_draft[speaker_name]']"
  end

  test "a valid step 1 saves the draft and moves to step 2" do
    get apply_path

    patch apply_path(step: 1), params: { application_draft: { speaker_name: "山田 太郎", email: "taro@example.com" } }

    assert_redirected_to apply_path(step: 2)
    follow_redirect!
    assert_select "input[name='application_draft[title]']"
    assert_select "textarea[name='application_draft[abstract]']"
    assert_equal "山田 太郎", ApplicationDraft.last.speaker_name
  end

  test "step 2 validates the talk and advances" do
    get apply_path
    patch apply_path(step: 1), params: { application_draft: { speaker_name: "山田 太郎", email: "taro@example.com" } }

    patch apply_path(step: 2), params: { application_draft: { title: "短い", abstract: "短い", category: "unknown" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_select "input[name='application_draft[title]'][value='短い']"

    patch apply_path(step: 2), params: { application_draft: { title: "標準フォームで作るサーバー検証", abstract: "あ" * 40, category: "rails" } }
    assert_redirected_to apply_path(step: 3)
  end

  test "step 3 confirms the values and the final submit creates the proposal" do
    get apply_path
    patch apply_path(step: 1), params: { application_draft: { speaker_name: "山田 太郎", email: "taro@example.com" } }
    patch apply_path(step: 2), params: { application_draft: { title: "標準フォームで作るサーバー検証", abstract: "あ" * 40, category: "rails" } }

    get apply_path(step: 3)
    assert_response :success
    assert_select ".wizard-confirm", text: /山田 太郎/
    assert_select ".wizard-confirm", text: /標準フォームで作るサーバー検証/

    assert_difference -> { Proposal.count }, 1 do
      assert_difference -> { ApplicationDraft.count }, -1 do
        patch apply_path(step: 3)
      end
    end

    assert_redirected_to forms_path
    follow_redirect!
    assert_select ".flash", text: /プロポーザルを送信しました/
    assert_select ".proposal-card", text: /標準フォームで作るサーバー検証/
  end

  test "the back link keeps the saved values" do
    get apply_path
    patch apply_path(step: 1), params: { application_draft: { speaker_name: "山田 太郎", email: "taro@example.com" } }

    get apply_path(step: 1)

    assert_select "input[name='application_draft[speaker_name]'][value='山田 太郎']"
    assert_select "input[name='application_draft[email]'][value='taro@example.com']"
  end

  test "the step is clamped to 1..3" do
    get apply_path(step: 99)
    assert_select ".wizard-step[aria-current='step']", text: /Step 3/

    get apply_path(step: 0)
    assert_select ".wizard-step[aria-current='step']", text: /Step 1/
  end

  test "a skipped step 3 fails validation instead of creating a proposal" do
    get apply_path

    assert_no_difference -> { Proposal.count } do
      patch apply_path(step: 3)
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "two sessions get separate drafts" do
    a = open_session
    b = open_session

    assert_difference -> { ApplicationDraft.count }, 2 do
      a.get apply_path
      b.get apply_path
    end

    assert_not_equal a.session[:application_draft_id], b.session[:application_draft_id]
  end

  test "the wizard is a standard form without slots attributes" do
    get apply_path

    assert_select "form[data-herb-into]", count: 0
    assert_select "form[data-herb-set]", count: 0
  end
end

class ApplicationsDuplicateTest < ActionDispatch::IntegrationTest
  test "a second final PATCH cannot create a second proposal" do
    get apply_path
    patch apply_path(step: 1), params: { application_draft: { speaker_name: "山田 太郎", email: "taro@example.com" } }
    patch apply_path(step: 2), params: { application_draft: { title: "標準フォームで作るサーバー検証", abstract: "あ" * 40, category: "rails" } }

    assert_difference -> { Proposal.count }, 1 do
      patch apply_path(step: 3)
    end
    assert_redirected_to forms_path

    assert_no_difference -> { Proposal.count } do
      patch apply_path(step: 3)
    end
  end
end
