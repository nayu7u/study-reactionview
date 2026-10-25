class UiController < ApplicationController
  # Static in-memory data on purpose (same rule as the ShowcaseController):
  # the kit demo shows component contracts, not AR flows.
  TAB_OVERVIEW = [
    { id: 1, label: "PR #12 をマージ", detail: "2分前" },
    { id: 2, label: "issues を整理", detail: "1時間前" },
    { id: 3, label: "リリースノート更新", detail: "昨日" }
  ].freeze

  TAB_ACTIVITY = [
    { id: 4, label: "先月のデプロイ", detail: "14回" },
    { id: 5, label: "開いたPR", detail: "23本" }
  ].freeze

  FAQS = [
    { id: 1, q: "導入にビルドステップは要りますか?", a: "要りません。ジェネレータが ERB 断片と素の CSS をコピーするだけで、Propshaft がそのまま配ります。" },
    { id: 2, q: "state の宣言はどこに書くの?", a: "断片自身が持っています。herb:state はパーシャル単位で manifest に出るので、貼り付けたコンポーネントが自分の state を所有します。" },
    { id: 3, q: "shadcn/ui と何が違うの?", a: "Radix の代わりに Herb のコンパイラが挙動を担い、Stimulus を書かずに presence 束縛と data-herb-* 属性だけで反応します。" }
  ].freeze

  CART_ITEMS = [
    { id: 1, name: "Herb ステッカー", price: 300 },
    { id: 2, name: "ERB トートバッグ", price: 1800 },
    { id: 3, name: "slots マグカップ", price: 1200 }
  ].freeze

  def index
    @tab_overview = TAB_OVERVIEW
    @tab_activity = TAB_ACTIVITY
    @faqs = FAQS
    @cart_items = CART_ITEMS
  end
end
