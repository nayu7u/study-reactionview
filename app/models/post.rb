class Post < ApplicationRecord
  has_many :replies, dependent: :destroy
  validates :title, presence: true
end
