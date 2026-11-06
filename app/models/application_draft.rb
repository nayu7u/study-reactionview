class ApplicationDraft < ApplicationRecord
  # Why a virtual step: the draft stores the fields once, while each wizard
  # step asks only for the fields that step owns. The step is not persisted;
  # the URL is the step.
  attr_accessor :step

  validates :speaker_name, presence: true, length: { maximum: 40 }, if: -> { step.to_i >= 1 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { step.to_i >= 1 }
  validates :title, presence: true, length: { minimum: 5, maximum: 80 }, if: -> { step.to_i >= 2 }
  validates :abstract, presence: true, length: { minimum: 30, maximum: 600 }, if: -> { step.to_i >= 2 }
  validates :category, inclusion: { in: Proposal::CATEGORIES }, if: -> { step.to_i >= 2 }

  def proposal_attributes
    attributes.slice("speaker_name", "email", "title", "abstract", "category")
  end
end
