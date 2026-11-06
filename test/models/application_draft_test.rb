require "test_helper"

class ApplicationDraftTest < ActiveSupport::TestCase
  test "an empty draft is valid at step 0" do
    assert ApplicationDraft.new(step: 0).valid?
  end

  test "step 1 requires a speaker and a valid email" do
    draft = ApplicationDraft.new(step: 1, speaker_name: "", email: "not-an-email")
    assert_not draft.valid?
    assert draft.errors[:speaker_name].any?
    assert draft.errors[:email].any?
  end

  test "step 2 requires the talk fields" do
    draft = ApplicationDraft.new(step: 2, speaker_name: "山田 太郎", email: "taro@example.com",
      title: "短い", abstract: "短い", category: "unknown")
    assert_not draft.valid?
    assert draft.errors[:title].any?
    assert draft.errors[:abstract].any?
    assert draft.errors[:category].any?
  end

  test "step 3 requires every field" do
    draft = ApplicationDraft.new(step: 3)
    assert_not draft.valid?
    assert draft.errors[:speaker_name].any?
    assert draft.errors[:email].any?
    assert draft.errors[:title].any?
    assert draft.errors[:abstract].any?
    assert draft.errors[:category].any?
  end

  test "proposal_attributes returns the five fields" do
    draft = ApplicationDraft.new(speaker_name: "山田 太郎", email: "taro@example.com",
      title: "タイトルです", abstract: "あ" * 40, category: "rails")
    assert_equal(
      { "speaker_name" => "山田 太郎", "email" => "taro@example.com",
        "title" => "タイトルです", "abstract" => "あ" * 40, "category" => "rails" },
      draft.proposal_attributes
    )
  end
end
