class ShowcaseController < ApplicationController
  # Static in-memory data on purpose: the lab exists to demonstrate
  # client-mode UI machinery, not Active Record flows (the Sprint Hub
  # covers those).
  NOTIFICATIONS = [
    { id: 1, title: "Sprint Hub が slots で応答しました", detail: "@team 宛の報告", kind: "mention" },
    { id: 2, title: "presence 束縛が属性を更新しました", detail: "checked / selected / disabled", kind: "info" },
    { id: 3, title: "計数foldが統計を即時更新しました", detail: "done_count += 1", kind: "info" }
  ].freeze

  def lab
    @notifications = NOTIFICATIONS
  end
end
