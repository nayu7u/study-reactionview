class NotesController < ApplicationController
  # Static in-memory data on purpose: this page exists to exercise the
  # client-mode UI surface (tabs, counters, palette, composer), not the
  # data layer the messages demo already covers.
  NOTES = {
    "inbox" => [
      { id: 1, title: "Buy oat milk" },
      { id: 2, title: "Draft the Kaigi on Rails reaction" },
      { id: 3, title: "Try data-herb-action=\"$refresh\"" }
    ],
    "archive" => [
      { id: 4, title: "Old draft from spring" },
      { id: 5, title: "Seed idea: counting folds" }
    ]
  }.freeze

  def index
    @notes = NOTES.fetch(herb_state("tab", "inbox"), [])
  end
end
