class TreeNode < ApplicationRecord
  KINDS = %w[folder file].freeze

  belongs_to :parent, class_name: "TreeNode", optional: true, inverse_of: :children
  has_many :children, -> { order(:position, :id) },
    class_name: "TreeNode", foreign_key: :parent_id,
    dependent: :destroy, inverse_of: :parent

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :ordered, -> { order(:position, :id) }
end
