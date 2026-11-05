require "test_helper"

# What is covered here: the server-side contract the form relies on.
# The browser never validates these rules; it posts and reads the 422.
class ProposalTest < ActiveSupport::TestCase
  test "a fixture proposal is valid" do
    assert proposals(:rails_talk).valid?
  end

  test "requires a speaker name and caps it at 40 characters" do
    proposal = proposals(:rails_talk)

    proposal.speaker_name = ""
    assert_not proposal.valid?
    assert proposal.errors[:speaker_name].any?

    proposal.speaker_name = "あ" * 41
    assert_not proposal.valid?
    assert proposal.errors[:speaker_name].any?
  end

  test "requires an email in a valid format" do
    proposal = proposals(:rails_talk)

    proposal.email = ""
    assert_not proposal.valid?
    assert proposal.errors[:email].any?

    proposal.email = "not-an-email"
    assert_not proposal.valid?
    assert proposal.errors[:email].any?
  end

  test "requires a title between 5 and 80 characters" do
    proposal = proposals(:rails_talk)

    proposal.title = "短い"
    assert_not proposal.valid?
    assert proposal.errors[:title].any?

    proposal.title = "a" * 81
    assert_not proposal.valid?
    assert proposal.errors[:title].any?
  end

  test "requires an abstract between 30 and 600 characters" do
    proposal = proposals(:rails_talk)

    proposal.abstract = "短い"
    assert_not proposal.valid?
    assert proposal.errors[:abstract].any?

    proposal.abstract = "あ" * 601
    assert_not proposal.valid?
    assert proposal.errors[:abstract].any?
  end

  test "requires a known category" do
    proposal = proposals(:rails_talk)

    proposal.category = "unknown"
    assert_not proposal.valid?
    assert proposal.errors[:category].any?
  end
end
