class UiController < ApplicationController
  # Spike data on purpose: the ui kit demo needs rows to hang per-item
  # component states on, nothing more.
  ROWS = [
    { id: 1, q: "スパイク1", a: "答え1" },
    { id: 2, q: "スパイク2", a: "答え2" }
  ].freeze

  def index
    @rows = ROWS
  end
end
