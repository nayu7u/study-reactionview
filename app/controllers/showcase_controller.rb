class ShowcaseController < ApplicationController
  # Static in-memory data on purpose: the lab exists to demonstrate
  # client-mode UI machinery, not Active Record flows (the Sprint Hub
  # covers those).
  NOTIFICATIONS = [
    { id: 1, title: "Sprint Hub が slots で応答しました", detail: "@team 宛の報告", kind: "mention" },
    { id: 2, title: "presence 束縛が属性を更新しました", detail: "checked / selected / disabled", kind: "info" },
    { id: 3, title: "計数foldが統計を即時更新しました", detail: "done_count += 1", kind: "info" }
  ].freeze

  # Static in-memory data on purpose (same rule as NOTIFICATIONS): the lab
  # demonstrates client-mode machinery, and these widgets only need rows to
  # hang per-item states on.
  CART_ITEMS = [
    { id: 1, name: "Herb ステッカー", price: 300 },
    { id: 2, name: "ERBトートバッグ", price: 1800 },
    { id: 3, name: "slotsマグカップ", price: 1200 }
  ].freeze

  FAQS = [
    { id: 1, q: "ビルドステップは本当に要らないの?", a: "要りません。importmap が gem の JS を pin するので、Node も yarn もバンドラも不要です。" },
    { id: 2, q: "state はどこに保持されるの?", a: "ブラウザ所有の state は JS メモリ、サーバーが答える読み取りは herb_state として毎往復のヘッダに乗ります。" },
    { id: 3, q: "既存の ERB と混ぜられる?", a: "config.action_view.html_erb_implementation を差し替える正攻法は Rails 8.2 から。8.1 では intercept_erb で。" }
  ].freeze

  def lab
    @notifications = NOTIFICATIONS
    @cart_items = CART_ITEMS
    @faqs = FAQS
  end
end
