# サーバー検証フォーム（`/forms`）設計

- 日付: 2026-11-05
- 状態: 設計案（承認待ち）
- 対象: `/forms`（ナビ外）
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

## 目的

実務で必ず通る「サーバー検証 → 422 → エラー表示 → 入力値保持」を、ReActionView のアプリ内で標準の Rails フォームとして成立させる。成功は通常のリダイレクト、失敗は 422 の HTML 全画面再描画にする。同じページに client mode の絞り込みを置き、標準フォームと slots ランタイムが互いを壊さないことを示す。

## なぜこの検証か

既存7画面のフォームは、クライアント検証（Settings / Client Lab）か楽観的追加（Sprint Hub）で、サーバーが 422 を返す経路を一度も通していない。

`data-herb-into`（outbox）を付けたフォームは、送信を横取りする。ReActionView 0.6.0 のクライアントは `!response.ok` で `SlotsRequestError` を投げ、outbox の `fail()` は楽観行に `failed` を立てるだけで、422 の HTML 本文を表示しない。つまり Rails の定番 `render :new, status: :unprocessable_entity` は、slots 経路では静かに失敗する。

実務での正解は、サーバー検証が主役のフォームを outbox に載せず、標準の HTML フォームとして送ること。この設計はその構成を1画面で固定し、テストとブラウザ実測で証拠を残す。

成功条件は次の4つ。

- 422 の全画面再描画で、エラーと入力値が残る。
- フォーム送信が slots リクエストを1本も出さない。
- 同じページの client mode 絞り込みが 0 往復で動き、入力途中のフォーム値を壊さない。
- 既存テストと `bin/ci` が green。

## 画面

- ナビ外の `/forms`。グローバルナビは7リンクのまま。Patterns の footer と docs からリンクする。
- 上: 見出し「Proposal Submission」と「サーバー検証 — 422 は標準フォームに残す」バッジ。
- 左（広い画面）: 送信フォーム。右: 提出済みプロポーザルの一覧（カテゴリ別）。
- モバイルは縦積み。
- フォーム項目: 発表者名、メール、タイトル、概要、カテゴリ（Rails / フロントエンド / インフラ）。
- 一覧: カテゴリごとのセクション。各カードにタイトル、発表者名、概要、カテゴリ。
- 絞り込み: 4つのチップ（すべて / Rails / フロントエンド / インフラ）。client mode で 0 往復。
- 成功時に「プロポーザルを送信しました」の flash を出す。

## 送信方式

- `form_with model: @proposal, url: forms_path`。`data-herb-into` を付けない。
- 送信はブラウザの通常の POST。成功は `redirect_to forms_path`、失敗は `render :index, status: :unprocessable_entity`。
- 422 の応答は `text/html`。ブラウザが全画面を描き直し、`@proposal.errors` と `@proposal` の値がそのまま出る。
- フォームに `data-herb-set` も付けない。submit を状態に書かせない（outbox の横取りと二重送信を避ける）。
- no-JS でも同じ経路。JS の有無でフォームの挙動が変わらない。
- エラーメッセージは Rails 既定（英語）。i18n は今回の主題ではない。

## 状態と絞り込み

- ビューは `herb:slots client`、状態は `filter_category: "all"` の1つ。
- チップは `data-herb-set="filter_category=rails"` のような literal set。`aria-pressed="<%= filter_category == "rails" %>"`。
- 3つのセクションは常に DOM に置き、`hidden="<%= filter_category != "all" && filter_category != "rails" %>"` の presence で出し分ける。分岐は使わない（パーシャル/分岐の 0.6.0 ギャップを避ける）。
- チップの切替は 0 slots リクエスト。フォームの入力値は state ではなく server-read なので、絞り込みでサーバーに問いに行かず、入力中の値も上書きされない。
- サーバーは絞り込みを知らない。`@proposals` は全件をカテゴリ別に返し、表示だけクライアントが切り替える。
- リロードや 422 の後は `filter_category` が初期値 `"all"` に戻る（全画面ナビゲーションのため）。これは仕様として docs に書く。

## バリデーション

```ruby
class Proposal < ApplicationRecord
  CATEGORIES = %w[rails frontend infra].freeze

  validates :speaker_name, presence: true, length: { maximum: 40 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :title, presence: true, length: { minimum: 5, maximum: 80 }
  validates :abstract, presence: true, length: { minimum: 30, maximum: 600 }
  validates :category, inclusion: { in: CATEGORIES }
end
```

- presence / length（min と max）/ format / inclusion の4系統を1画面で通す。
- email の形式はクライアントの状態言語では表現できない（変換は `.length` / `.size` / `.to_s` のみ）。サーバー検証の必然性を作る。
- uniqueness は付けない。同じ発表者が複数出せるのは自然で、DB インデックスとテストの揺れを増やすだけ。Why not コメントをモデルに書く。
- クライアント検証は足さない。今回の主題は「サーバーの答えをどう表示するか」で、二重管理すると 422 の経路が隠れる。Why not コメントをビューに書く。

## 422 の扱い

- `create` は `@proposal.save` が false なら `@proposals` を組み直して `render :index, status: :unprocessable_entity`。
- ビューは `@proposal.errors.any?` のとき、上部に `role="alert"` のエラー要約、各項目の下に `field-error` を出す。`aria-invalid` も付ける。
- 入力値は `form_with model:` が `@proposal` から描くので、422 でも保持される。
- `format=slots` の POST が来た場合も 422 を返す。応答は slots の本文になるが、クライアントは `!response.ok` で捨てる。この境界は統合テストで固定し、docs に書く（アプリのフォームは slots を送らない）。
- 422 の応答で `filter_category` は `"all"` に戻る。エラー表示を優先し、絞り込みの復元はしない。

## ルートとコントローラ

```ruby
get "/forms", to: "proposals#index", as: :forms
post "/forms", to: "proposals#create"
```

- `ProposalsController#index` は `@proposals = Proposal.order(created_at: :desc).group_by(&:category)` と `@proposal = Proposal.new`。
- `#create` は strong params `proposal[...]`、成功で redirect、失敗で 422。
- `herb_state` は使わない（絞り込みはクライアント所有）。
- `form_with` の URL は `forms_path`。

## レイアウトと CSS

- `.forms-layout`: 2カラム（フォーム / 一覧）。`52rem` 以下で1カラム。
- 既存の `.field` / `.field-label` / `.btn` / `.chip` / `.feature` / `.flash` を再利用。
- 追加: `.form-errors`（赤系の要約）、`.field-error`（小さな赤文字）、`.proposal-card`、`.proposal-group`。
- 色は既存トークンを使う。赤は既存の `.field-over` に合わせる。
- フォーカスリングは既存の `:focus-visible` に乗せる。

## テスト

- `test/models/proposal_test.rb`: 有効な fixture、各バリデーションの単体（空、短い、長い、メール形式、カテゴリ外）。
- `test/controllers/proposals_controller_test.rb`:
  - GET /forms がフォームと3セクション、4チップを出す。`form[data-herb-into]` が0。select / textarea の初期値。
  - manifest に `filter_category` が宣言され、`hidden` の presence が3つある。`aria-pressed` が state 比較。
  - 無効 POST → 422、`text/html`、エラー要約、各 `field-error`、入力値保持（email / title / abstract）。
  - 有効 POST → redirect + flash、一覧に新しい行。
  - no-JS と同じ経路（同じ POST が 422 HTML / 302）。`data-herb-into` が無いことを明示。
  - `POST /forms?format=slots` + 無効 params → 422、`application/vnd.herb.slots+json`、本文が slots payload（`template` を持つ）。クライアントが捨てる境界の記録。
  - GET /forms の初期 HTML に一覧の全カテゴリが入る（クライアント絞り込みの前提）。
- 既存の `tasks` / `patterns` / `pricing` / `settings` / `dashboard` / `showcase` / `ui` のテストが通る。
- `bin/ci` green。

## ブラウザ実測（`/tmp/opencode/capture/forms-probe.js`）

- 初期表示: slots リクエスト0。フォームは `data-herb-into` なし。
- チップ切替: 各カテゴリで slots 0、表示セクションが1つ（すべてなら3つ）。入力途中のタイトルが保持される。
- 無効送信: document POST が1回、応答 422、slots 0。`.form-errors` と `.field-error` が見え、email / title / abstract の値が残る。
- 有効送信: document POST → 302 → GET /forms、flash と新しい行。slots 0。
- 送信後のチップ切替も slots 0。
- フォントは既存の日本語スタック（画面確認のみ、メディアは撮らない）。

## ドキュメント

- `docs/forms.md`（新規）: 実務検証の本編。outbox が 422 を捨てる根拠（クライアント実装）、標準フォームの構成、422 の流れ、client mode 絞り込みとの共存、使い分けの判断表、実測値。Why not 200 envelope / custom transport も書く。
- `docs/hotwire-comparison.md`: ② に「ナビ外の実務検証」を1行、③ に対比6「サーバー検証は標準フォームに残す」、⑥ に outbox の 422 境界、⑦ を `/forms` へ更新。
- `docs/hotwire-comparison.html`: ⑥ / ⑦ と対比6の要約を同期（全文の再構成はしない）。
- `README.md`: 「7つの画面」の後に「実務検証: サーバー検証フォーム（`/forms`、ナビ外）」を追加。7画面の主張は変えない。
- `AGENTS.md`: Forms 画面の実測節（outbox の 422、標準フォームの共存、slots POST 422、0 往復の絞り込み、テスト環境の media type）。
- Patterns の footer に1行リンクを追加。メディアは再撮影しない（footer の差分は許容し、docs に注記）。

## 非ゴール

- ナビへの8リンク目追加、既存メディアの再撮影、GIF。
- Sprint Hub の作成フォームの変更。
- フォームの楽観的追加・slots 書き込み・クライアント検証。
- i18n（エラーは Rails 既定の英語）、認証、実メール送信、ページネーション、編集・削除。
- 422 を slots で表示する独自 transport。
- 一覧の keyed collection / 楽観的追加。

## 検討した案

1. **標準 HTML フォーム + 422（採用）**: 実務の正解をそのまま固定できる。全画面再描画のコストは受け入れる。
2. **`data-herb-into` の slots 書き込み**: 201 の splice は残るが、422 の本文は捨てられ、項目別エラーを出せない。`failed` の汎用表示しかない。今回の証拠にならない。
3. **200 envelope / 独自 transport**: 422 を 200 に包めば slots でエラーを表示できるが、Rails の慣習から外れ、カスタム JS が要る。ERB のみの主張を弱める。
4. **server mode の絞り込み**: 1往復で動くが、slots 応答がフォームの server-read 値も運ぶため、入力中の値が上書きされる懸念がある。client mode の 0 往復を選ぶ。
5. **8画面目としてナビに追加**: ショーケースの一員になるが、8リンクの調整と全メディア再撮影が波及する。証拠目的には過剰。
6. **Patterns にセクション追加**: Patterns の server mode 絞り込みと 422 の全画面リロードが混ざる。独立ページにする。
7. **ライブ文字数カウンタ / プレビュー**: 422 の初期値と state の初期値がずれ、全画面再描画後に表示が合わない。今回は入れない。

## リスクと確認事項

- `hidden="<%= filter_category != "all" && filter_category != "rails" %>"` の `&&` コンボが presence としてコンパイルできるか。不可ならカテゴリごとの boolean state（`show_rails` など）に分ける。
- client mode のページで、server-read のフォーム値をチップ切替が書き換えないか。ブラウザプローブで入力保持を確認する。
- `POST ?format=slots` の 422 応答が slots payload として返るか。gem の renderer の挙動を統合テストで確認する。返らない場合は 422 と media type だけを記録する。
- 422 の全画面再描画で、`form_with` が `@proposal` の値を保持するか（特に textarea）。実装後にプローブで確認する。
- Patterns footer のリンク追加で既存 still に差分が出る。再撮影しない方針を docs に書く。
- エラーメッセージが英語のまま。読み手に違和感が出るなら、次のタスクで最小の `ja.yml` を足す（今回は非ゴール）。

## 受け入れ条件

- `/forms` はナビ外で、Patterns の footer と docs から辿れる。
- フォームは `data-herb-into` を持たず、有効 POST は 302、無効 POST は 422 の `text/html`。
- 422 でエラー要約・項目別エラー・入力値（email / title / abstract）が残る。
- チップ切替は 0 slots リクエストで、入力途中のフォーム値が変わらない。
- フォーム送信は slots リクエストを出さない（document POST のみ）。
- `POST ?format=slots` の 422 が slots 本文として返り、クライアントが捨てる境界がテストと docs に記録されている。
- `bin/rails test` と `bin/ci` が green。
- `docs/forms.md`、README、hotwire-comparison（md / html）、AGENTS.md が更新されている。
- 既存の7画面のメディア・ナビ・挙動は変えない（Patterns footer の1行を除く）。
