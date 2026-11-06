class Talk < ApplicationRecord
  CATEGORIES = %w[rails frontend infra].freeze
  CATEGORY_LABELS = {
    "rails" => "Rails",
    "frontend" => "フロントエンド",
    "infra" => "インフラ"
  }.freeze

  # Why not uniqueness or a write path: the catalog is a read-only search
  # demo. The models that own writes stay on /forms (Proposal).
  validates :title, :speaker, :abstract, presence: true
  validates :category, inclusion: { in: CATEGORIES }
end
