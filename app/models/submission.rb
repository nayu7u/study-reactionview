class Submission < ApplicationRecord
  validates :title, presence: true, length: { maximum: 80 }
end
