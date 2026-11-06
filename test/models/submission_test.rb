require "test_helper"

class SubmissionTest < ActiveSupport::TestCase
  test "a fixture submission is valid" do
    assert submissions(:one).valid?
  end

  test "requires a title" do
    submission = submissions(:one)
    submission.title = ""
    assert_not submission.valid?
    assert submission.errors[:title].any?
  end
end
