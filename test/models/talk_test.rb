require "test_helper"

# What is covered here: the read-only catalog's data contract.
class TalkTest < ActiveSupport::TestCase
  test "a fixture talk is valid" do
    assert talks(:rails_one).valid?
  end

  test "requires a title, speaker and abstract" do
    talk = talks(:rails_one)

    talk.title = ""
    talk.speaker = ""
    talk.abstract = ""
    assert_not talk.valid?
    assert talk.errors[:title].any?
    assert talk.errors[:speaker].any?
    assert talk.errors[:abstract].any?
  end

  test "requires a known category" do
    talk = talks(:rails_one)

    talk.category = "unknown"
    assert_not talk.valid?
    assert talk.errors[:category].any?
  end
end
