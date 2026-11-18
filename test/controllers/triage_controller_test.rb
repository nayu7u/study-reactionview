require "test_helper"

class TriageControllerTest < ActionDispatch::IntegrationTest
  test "index renders the bulk selection surface" do
    get triage_path

    assert_response :success
    assert_select "h1", "Triage"
    assert_select ".triage-row", count: 3
    assert_select 'input[type="checkbox"][name="ids[]"]', count: 3
    assert_select ".triage-count", text: "0"
    assert_select "form[action=?]", triage_path do
      assert_select 'input[name="_method"][value="patch"]'
      assert_select 'select[name="priority"]'
    end
  end

  test "update changes only the selected tasks" do
    patch triage_path, params: { ids: [ tasks(:one).id, tasks(:three).id ], priority: "1" }

    assert_redirected_to triage_path
    assert_equal "2件の優先度を更新しました", flash[:notice]
    assert_equal 1, tasks(:one).reload.priority
    assert_equal 2, tasks(:two).reload.priority
    assert_equal 1, tasks(:three).reload.priority
  end

  test "update without a selection keeps the priorities" do
    patch triage_path, params: { priority: "3" }

    assert_redirected_to triage_path
    assert_equal "タスクを選択してください", flash[:alert]
    assert_equal 3, tasks(:one).reload.priority
  end

  test "update rejects an invalid priority" do
    patch triage_path, params: { ids: [ tasks(:one).id ], priority: "9" }

    assert_redirected_to triage_path
    assert_equal "優先度を選んでください", flash[:alert]
    assert_equal 3, tasks(:one).reload.priority
  end

  test "update rejects a non-numeric priority" do
    patch triage_path, params: { ids: [ tasks(:one).id ], priority: "high" }

    assert_redirected_to triage_path
    assert_equal "優先度を選んでください", flash[:alert]
    assert_equal 3, tasks(:one).reload.priority
  end
end
