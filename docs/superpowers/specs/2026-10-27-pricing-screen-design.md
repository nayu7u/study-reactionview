# Pricing / 見積もり画面（5画面目）設計

- 日付: 2026-10-27
- 状態: 設計案（承認待ち）
- 対象: `study-reactionview`（ReActionView 0.6.0 + herb 0.11.1）

## 目的

5画面目として、SaaS の料金プランを選ぶと見積もりが変わる `/pricing` を追加します。狙いは、既存の4画面がまだ見せていない「**業務ロジックはサーバーに残したまま、UI だけを反応させる**」という境界を、実務でよくある題材で示すことです。

プラン・席数・年払い・優先サポートを変えると、サーバーが小計・割引・税・合計を計算し直します。ブラウザに返るのは HTML 全体ではなく、内訳の値だけです。金額の計算式を JavaScript に写さない、という判断をそのまま画面で示します。

## ゴール

- `/pricing` を追加し、レイアウトのナビゲーションから開けるようにする。
- 4つの状態（`plan` / `seats` / `annual` / `support`）を server mode で扱う。
- 操作ごとに `GET /pricing?format=slots` が1回だけ飛び、内訳と合計が差し替わる。
- 金額はすべて Ruby 側で計算し、ビューでは READ slot（`data-herb-name`）として表示する。
- 各 state をどこかの条件分岐に読ませ、steering ヘッダに載るようにする。
- 統合テストで、初期表示・各組み合わせの計算・slots 応答・manifest の条件分岐を固定する。
- README、Hotwire 対比ノート、AGENTS.md を5画面構成に更新する。

## 非ゴール

- 見積もりの保存、DB モデル、決済、認証、メール送信。
- no-JS での再計算。初期表示は読めますが、操作には JavaScript が必要です。no-JS フォールバックは既存の Sprint Hub が担います。
- `<Async>` / `<Lazy>` / `<Fragment>` / polling（遅延読み込みは後続のテーマ）。
- Hotwire / Stimulus / 独自 JavaScript の導入。
- 画像・GIF の撮影。必要なら実装後に既存の Playwright 環境で追加します。

## 制約（0.6.0 / 0.11.1 の実測）

- 金額の計算には server mode を使います。client mode の fold は整数リテラルの加算しかできず、派生状態も比較と `.length` / `.size` / `.to_s` までです。掛け算・税率・割引は表現できません。
- server mode で往復が起きるのは、state を読む条件分岐の答えが反転したときです。さらに steering ヘッダに載るのは、条件分岐が読んでいる state だけです。したがって、`plan` / `seats` / `annual` / `support` はそれぞれ、どこかの分岐に読ませます。
- 席数のように、分岐が反転しない操作があります。`seats >= 10` は 5→6 では反転しません。こうした操作には `data-herb-action="$refresh"` を合成し、同じ dispatch の state を1リクエストに合流させます。
- 金額は `data-herb-name` の READ slot に置きます。分岐の statics は初回固定でも、slot の値は毎往復差し替わります。
- state の比較は literal のみです。プランカードの `aria-pressed` は `plan == "starter"` のように literal で書きます。ループ変数との比較は使えません。
- state は Boolean / Integer / String のみです。金額はすべて Integer で計算し、Float を使いません。
- `<select>` の `value` バインドは初期表示を反映しません。プランはボタン、年払いは2つのボタン、サポートはチェックボックスで扱います。
- 初期 state は literal です。URL パラメータから state の初期値を取らないため、no-JS の再計算は行いません。

## 検討した案

### 画面候補

1. **Pricing / 見積もり（採用）**: 金額計算をサーバーに残す。既存4画面にない業務ロジックの題材で、実務での導入判断にも直結する。
2. **設定画面**: タブ・依存フィールド・未保存状態を client mode で見せる。安全だが、Client Lab の switch・ウィザード・バリデーションと重なる。
3. **ピン / スター一覧**: 行の状態とヘッダ集計を0往復で同時更新する。単体の画面にすると fold + presence の組み合わせ1つ分で薄く、既存画面の追加機能に向く。

### 実装方式

1. **通常のフォーム再送**: 実装は単純だが、画面全体がリロードされ、ReActionView の細粒度更新を見せられない。
2. **client mode で計算**: 金額計算を JavaScript に写すことになり、サーバー側の料金ルールと二重管理になる。fold と派生状態だけでは掛け算・税率を表現できない。
3. **server mode + slots + READ slot（採用）**: 計算は Ruby に残し、返すのは内訳の値だけ。既存の Patterns と同じ往復の仕組みで、金額の境界をはっきり見せられる。

## 料金モデル

すべて税抜表示、合計は税込です。金額は日本円の整数で扱います。

| 項目 | 値 |
|---|---|
| Starter | ¥1,200 / 席 / 月 |
| Team | ¥2,400 / 席 / 月 |
| Business | ¥4,000 / 席 / 月 |
| ボリューム割引 | 10席以上で席位料金の10%OFF |
| 年払い割引 | 12か月分の小計から15%OFF |
| 優先サポート | +¥10,000 / 月（定額） |
| 消費税 | 10% |

計算順序は次のとおりです。すべて整数除算で、端数は切り捨てます。

1. 席位料金 = プラン単価 × 席数
2. ボリューム割引 = 10席以上なら席位料金 × 10 / 100
3. 月額小計 = 席位料金 - ボリューム割引 + 優先サポート
4. 小計 = 月額小計 × 請求月数（月払い1、年払い12）
5. 年払い割引 = 年払いなら小計 × 15 / 100
6. 税抜合計 = 小計 - 年払い割引
7. 消費税 = 税抜合計 × 10 / 100
8. 合計 = 税抜合計 + 消費税

代表例:

| 条件 | 合計（税込） |
|---|---|
| Team / 5席 / 月払い / サポートなし | ¥13,200 |
| Team / 5席 / 年払い / サポートなし | ¥134,640 |
| Business / 12席 / 年払い / サポートあり | ¥596,904 |

初期状態は Team / 5席 / 月払い / サポートなしです。

## 画面構成

`app/views/pricing/index.html.erb` は `<%# herb:slots server %>` で始まり、次の state を宣言します。

```erb
<%# herb:state (plan: "team", seats: 5, annual: false, support: false) %>
```

### 左側: 条件

- **プランカード（3枚）**: Starter / Team / Business。各カードはボタンで、`data-herb-set="plan=starter"` のように literal を書きます。選択中は `aria-pressed="<%= plan == "starter" %>"` で示します。カードには単価と短い特徴を静的表示します。
- **席数ステッパー**: `−` は `data-herb-decrement="seats" data-herb-action="$refresh"`、`+` は `data-herb-increment="seats" data-herb-action="$refresh"`。`−` は `disabled="<%= seats <= 1 %>"`、`+` は `disabled="<%= seats >= 50 %>"` で両端を止めます。席数は `seats` の READ slot として表示します。
- **請求サイクル**: 「月払い」「年払い」の2ボタン。`data-herb-set="annual=false"` / `annual=true` と `aria-pressed` で表現します。
- **優先サポート**: `checked="<%= support %>"` のチェックボックス。`if support` の分岐で内訳に行を出します。

### 右側: 見積もり

上部に「サーバーが計算」のバッジを置き、次の内訳を表示します。

- 基本料金（プラン名 × 席数）
- ボリューム割引（10席以上のとき）
- 優先サポート（オンのとき）
- 小計（月払い / 年払いでラベルを切り替え）
- 年払い割引（年払いのとき）
- 税抜合計
- 消費税（10%）
- 合計（税込）

内訳の値は `data-herb-name` の READ slot にします。合計は大きく表示し、`aria-live="polite"` を付けます。

### 分岐と steering

- `plan` を読む分岐: 選択中プランの説明を if / elsif / else で出し分ける。
- `seats` を読む分岐: `if seats >= 10` でボリューム割引の行を出す。
- `annual` を読む分岐: 年払い割引の行と請求ラベルを切り替える。
- `support` を読む分岐: 優先サポートの行を出す。

`seats` の増減だけは分岐が反転しないことがあるため、`$refresh` を合成します。プラン・年払い・サポートは分岐の反転が往復を起こします。

### no-JS の扱い

初期表示は通常の HTML として読めます。ただし、操作後の再計算は JavaScript が必要です。state の初期値が literal で、URL パラメータからの種付けを行わないため、通常フォームで再送すると表示と state がずれます。この画面では no-JS の再計算を対象外とし、その旨を画面の注記に書きます。

## コントローラとルーティング

`config/routes.rb` に `get "/pricing", to: "pricing#index"` を追加します。

`app/controllers/pricing_controller.rb` の骨子:

```ruby
class PricingController < ApplicationController
  PLANS = {
    "starter" => { label: "Starter", price: 1_200, blurb: "小さく始める", features: ["基本機能", "5GB ストレージ"] },
    "team" => { label: "Team", price: 2_400, blurb: "チームで使う", features: ["SSO", "共有ワークスペース", "10GB ストレージ"] },
    "business" => { label: "Business", price: 4_000, blurb: "統制と安心", features: ["監査ログ", "SLA", "無制限ストレージ"] }
  }.freeze

  SEAT_MIN = 1
  SEAT_MAX = 50
  VOLUME_THRESHOLD = 10
  VOLUME_PERCENT = 10
  ANNUAL_PERCENT = 15
  TAX_PERCENT = 10
  SUPPORT_FEE = 10_000

  def index
    requested_plan = herb_state("plan", "team")
    @plan_key = PLANS.key?(requested_plan) ? requested_plan : "team"
    @plan = PLANS.fetch(@plan_key)
    @plans = PLANS

    @seats = integer_state("seats", 5).clamp(SEAT_MIN, SEAT_MAX)
    @annual = boolean_state("annual", false)
    @support = boolean_state("support", false)

    @seat_fee = @plan[:price] * @seats
    @volume_discount = @seats >= VOLUME_THRESHOLD ? @seat_fee * VOLUME_PERCENT / 100 : 0
    @support_fee = @support ? SUPPORT_FEE : 0
    monthly_subtotal = @seat_fee - @volume_discount + @support_fee
    @months = @annual ? 12 : 1
    @subtotal = monthly_subtotal * @months
    @annual_discount = @annual ? @subtotal * ANNUAL_PERCENT / 100 : 0
    @discounted = @subtotal - @annual_discount
    @tax = @discounted * TAX_PERCENT / 100
    @total = @discounted + @tax
  end
end
```

`integer_state` は Patterns と Pricing の両方で使うため、`ApplicationController` に移します。`boolean_state` も同じ場所に置きます。`integer_state` は Patterns の実装をそのまま移し、`boolean_state` は `true` / `"true"` だけを真として受けます。`herb_state` はヘッダの生値を型変換なしで返すため、手作りヘッダに対する防御的キャストです。

## ビューの注記

画面下部に、次の3点を短く書きます。

- 金額はすべてサーバーで計算していること。
- 席数の増減だけは分岐が反転しないので `$refresh` を合成していること。
- 内訳は READ slot なので、同じ slots 応答で値だけが差し替わること。

## スタイル

`app/assets/stylesheets/app.css` に次を追加します。

- `.pricing-layout`: 既存の `.split` を基本にした2カラム。52rem 以下で1カラム。
- `.plan-grid` / `.plan-card`: 3枚のプランカード。選択中は `[aria-pressed="true"]` で強調。
- `.billing-options` / `.billing-option`: 月払い・年払いの2ボタン。
- `.pricing-summary` / `.price-line` / `.price-total`: 見積もりカードと内訳。
- `.seat-stepper`: 既存の `.qty-group` / `.qty-value` を再利用し、必要なら席数用の最小限の調整を足す。
- `.site-nav { flex-wrap: wrap; }`: ナビが5項目になっても折り返せるようにする。

色は既存のデザイントークンを使い、Tailwind などは導入しません。

## テスト

`test/controllers/pricing_controller_test.rb` を追加します。

1. **初期表示**: `/pricing` が成功し、`h1` が Pricing、プランカード3枚、Team が選択中、席数5、月払い、サポートなし、合計 ¥13,200 を表示する。
2. **操作属性**: 席数の `+` / `−` に `data-herb-increment` / `decrement` と `data-herb-action="$refresh"` がある。プランカードに literal の `data-herb-set` がある。
3. **営業計算**: `Herb-State` に Business / 12席 / 年払い / サポートありを渡した slots 応答が、¥4,800 のボリューム割引、¥95,760 の年払い割引、¥10,000 のサポート、¥54,264 の消費税、¥596,904 の合計を返す。
4. **年払いのみ**: Team / 5席 / 年払い / サポートなしで ¥134,640 を返す。
5. **境界**: 9席ではボリューム割引の行が出ず、10席では出る。
6. **manifest**: `plan` / `seats` / `annual` / `support` が declarations にあり、conditionals の条件に4つとも現れる。`seats` の presence バインディング（`<= 1` など）も確認する。
7. **防御的キャスト**: 不明なプランは Team に落ち、`seats` が範囲外なら 1〜50 に丸まる。

スロット番号はテンプレート変更でずれるため、アサートは番号ではなく「statics にこの文言を含む Hash を探す」「values にこの金額を含む」という形で書きます。

## ドキュメント更新

- `README.md`: 「4つの画面」を「5つの画面」にし、表と節を追加。テスト一覧に `pricing_controller_test` を追加。
- `docs/hotwire-comparison.md`: 証明マップに Pricing の行を追加し、§③ に「料金計算をサーバーに残す」対比を追加。§⑦ の候補から見積もりフォームを外す。画面数の記述を5に更新。
- `AGENTS.md`: 5画面目の概要を追加。実装後に、`seats` の `$refresh` と steering、Boolean state のキャスト、金額を READ slot に置く理由を実測メモとして追記。
- `app/views/layouts/application.html.erb`: ナビに Pricing を追加。

## 受け入れ条件

- `bin/rails test` が通る。
- `bin/ci` の全ゲートが通る。
- ブラウザで `/pricing` を開き、プラン・席数・年払い・サポートを操作すると、`?format=slots` が1回飛び、内訳と合計だけが変わる。ページ全体はリロードされない。
- DevTools の manifests で、4つの state と対応する conditionals を確認できる。
- 5項目のナビがデスクトップとモバイルで崩れない。
- README / Hotwire 対比ノート / AGENTS.md が5画面構成になっている。

## リスクと確認事項

- **`$refresh` と increment の順序**: 席数の増減で、state の書き込みより先にリクエストが組み立てられないか。実装後に headless Chromium で `Herb-State` ヘッダを確認する。問題があれば、席数を `<select>` に変えるか、`data-herb-set` で明示値を書く方式に切り替える。
- **分岐内の READ slot**: 年払い割引・サポート・ボリューム割引の金額が、分岐の切替後も更新されるか。Patterns の詳細パネルと同じ形なので動く見込みだが、実測で確認する。動かなければ、金額を分岐の外に出し、`hidden` の presence バインディングで行を出し分ける。
- **5項目のナビ**: `.site-nav` の折り返しと、ヘッダーの高さを確認する。
- **no-JS**: 再計算できないことを画面に明記する。これは意図的な非ゴールです。
- **画像/GIF**: 今回は必須にしない。記事用に必要なら、実装後に既存の撮影環境で追加する。

## 実装後に残す判断

- プラン名・単価・割引率・サポート料金は、この設計では上記の値に固定する。変更する場合は設計の更新として扱う。
- 文言と CSS の細部は実装者に任せる。
- 見積もりの保存や送信は、必要になった時点で別の設計にする。
