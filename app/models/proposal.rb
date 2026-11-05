class Proposal < ApplicationRecord
  CATEGORIES = %w[rails frontend infra].freeze
  CATEGORY_LABELS = {
    "rails" => "Rails",
    "frontend" => "フロントエンド",
    "infra" => "インフラ"
  }.freeze

  # Why not uniqueness: the same speaker may submit more than one talk, and a
  # unique index would add DB state that this evidence page does not measure.
  validates :speaker_name, presence: true, length: { maximum: 40 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :title, presence: true, length: { minimum: 5, maximum: 80 }
  validates :abstract, presence: true, length: { minimum: 30, maximum: 600 }
  validates :category, inclusion: { in: CATEGORIES }
end
