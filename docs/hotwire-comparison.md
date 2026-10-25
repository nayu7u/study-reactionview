# Hotwire を使わずともよい、を体感する — ReActionView 対比ノート

ReActionView 0.6.0 + herb 0.11.1 の検証リポジトリ（Kaigi on Rails 2026 の主題検証）。
本リポジトリの主張「**ERB のみで Phoenix LiveView 的な細粒度リアクティビティ**」を、
Hotwire（Turbo + Stimulus）が担っていた役割ごとに分解して、実コードで対比します。

> スタイル付き HTML 版は [`docs/hotwire-comparison.html`](./hotwire-comparison.html)。
> GitHub は `.html` を `text/plain` で配信するためレンダリングされない —
> [raw.githack](https://raw.githack.com/nayu7u/study-reactionview/main/docs/hotwire-comparison.html)
> 経由かローカルで開いてください。この Markdown 版は GitHub 上でそのまま読めます（内容は同一・相互リンク済み）。

目次: ① 主張の分解 / ② 証明マップ / ③ 実コード対比 / ④ 概念読替表 / ⑤ 往復はいつ飛ぶか / ⑥ 正直な境界 / ⑦ 次に足すなら

---

## ① 主張の分解 — Hotwire の2層を、モード2つで置き換える

### 層1 — Turbo Frame / Turbo Stream / form の往復 → **server mode**

DB を引く更新（検索・ソート・ページネーション・作成）。Turbo だと form + `turbo-frame` +
部分テンプレート＋枠外の値（合計バッジ等）を更新する Stream まで必要になりがち。
ReActionView は `herb_state` と `data-herb-*` 属性だけで、
同じアクションが HTML を出しつつ部分更新のワイヤも返す。

実装: `/`（Sprint Hub）と `/patterns`（Patterns）

### 層2 — Stimulus コントローラ（リアクティブUI）→ **client mode**

DB を引かない更新（文字数・妥当性・開閉・カウンタ・ステップ）。Hotwire だと
Stimulus を書くこと自体が「Turbo 外の生 JS 層」。client mode ではテンプレートが
状態と分岐をコンパイル解析し、クライアントへの命令書（manifest）を自動生成 —
操作は**全てブラウザ内で完結（0 往復）**。

実装: `/lab`（Client Lab）と `/ui`（UI Kit）

### JS の実体（実ファイル・全4行）

```js
// app/javascript/application.js
// Why not "controllers": the showcase is a zero-custom-JS demo — Stimulus
// wiring would only muddy the measured claim that ERB alone carries the UI.
import "reactionview"
```

`node_modules` もビルドも不要。`turbo` / `stimulus` の pin は Rails 生成の標準配置だが
**このアプリは import していない**。UI に必要なのは gem が自動 pin する reactionview クライアント 1 本。
（本リポジトリの制約「Node/yarn を導入しない → importmap で完結」と同じ土台。）

---

## ② 証明マップ — 4画面が消している Hotwire の部品

全部動くので `bin/rails server` で確認できます。

| 画面 | モード | 機能 | Hotwire なら書かされていたもの | ReActionView での代わり |
|---|---|---|---|---|
| **Sprint Hub** (`/`) | server | 検索・並び替え | form + `turbo-frame` + 部分テンプレ＋（文字入力単位にするなら）Stimulus debounce | `data-herb-set="query=$value"` + `data-herb-debounce` |
| | | 完了チェック・統計 | 行の class 切替の Stimulus＋統計の再描画 | presence 束縛（`checked`）＋CSS `:has()`＋計数 fold（`done_count`） |
| | | 作成ドロワー | Stimulus での dialog 開閉、focus・backdrop 処理 | `<% if drawer_open %>`＋`data-herb-set="click@outside->… esc@window->…"` |
| | | 楽観的追加 | Stimulus で先に DOM を挿入 or Turbo Stream 追従（順序・鍵の整合は自前） | `data-herb-into="tasks"` → POST 201 の splice |
| **Patterns** (`/patterns`) | server | フィルタチップ | chips 用の form submit、aria 状態の保守 | `data-herb-set="priority=3 page=1"`＋`aria-pressed` スロット |
| | | もっと見る | `link_to …, data: { turbo_stream: … }`＋append ストリーム / フレーム増設 | `data-herb-increment="page"`＋`$refresh`（鍵付き差分で既存行は動かない） |
| | | 詳細連動 | 行クリック → 別フレーム再描画、選択状態を Stimulus で管理 | 同じ往復が詳細の分岐と `data-herb-name` スロットに答える |
| **Client Lab** (`/lab`) | client | タブ・カウンタ・パレット | Stimulus ×3（tab / unread / palette） | `herb:state` 宣言＋`data-herb-set / -increment / -reset` |
| | | ライブ入力・バリデーション | 文字数・妥当性・disabled 同期のコントローラ | 派生宣言（`ready_bio: bio != "" && bio.length <= 60`）＋presence の `disabled` |
| | | ウィザード（3ステップ） | ステップ＋入力ゲートのコントローラ | `step` 状態の分岐（未描画の腕は `<template data-herb-region>` に格納済み） |
| **UI Kit** (`/ui`) | client | switch・accordion 等 9コンポーネント | shadcn/ui 相当の Stimulus Data API と更新の配管 | パーシャル単位の `herb:state`（region スコープ）＋presence 束縛 — **全操作 0 往復**（実測） |
| | | 数量ステッパー | 行ごとの qty 管理と全体合計を Stimulus に | 行ごと `<%# herb:state (qty: 0) %>`＋計数 fold の `in_cart` |

---

## ③ 実コード対比 — 4つの局面

並びは「上: **Hotwire 側**（Hotwire で同じ挙動のために典型的に書かされるコード =
**代表形の仮置き、本リポジトリには無い**）」「下: **ReActionView 側**（本リポジトリの**実物**）」。
「局所更新の配管」と「生 JS の部分」がどう消えるかを縦に読めます。

### 対比 1 — 検索の絞り込み（打たれるたびに活きる、DB引きの1往復）

**Hotwire 側（代表形）— 置く場所が3つ: Stimulus コントローラ / form＋frame / 部分テンプレ**

```js
// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Turbo には「input 単位の submit」が無いので自作する
  submit({ target }) {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => target.form.requestSubmit(), 220)
  }
}
```

```erb
<%= form_with url: tasks_path, data: { turbo_frame: "tasks" } do %>
  <%= text_field_tag :query, params[:query],
        data: { controller: "search", action: "input->search#submit" } %>
<% end %>

<turbo-frame id="tasks"> … </turbo-frame>
```

> 枠外のバッジ（全件数）は frame の外なので、Turbo Stream か frame 増設で**別途配管**が必要。

**ReActionView 側（実物）— 属性1つ**

```erb
<%# app/views/tasks/index.html.erb %>
<input class="field" value="<%= query %>"
  data-herb-set="query=$value" data-herb-debounce="220"
  placeholder="タスクを検索…">

<%# 反転する分岐が往復の「スイッチ」になる %>
<% if query.empty? %>全件表示<% else %>
  「<%= query %>」の結果（サーバーで絞り込み済み）
<% end %>
```

```rb
# app/controllers/tasks_controller.rb — 同じアクションが応答する
# （実物は LIKE の % _ \ エスケープを追加で含む）
term = herb_state("query", "")
@tasks = Task.order(created_at: direction).where(...) if term.present?
```

> 「`if query.empty?` の反転」が往復のトリガ。行もバッジも同じ往復の slots ワイヤで
> 一体に更新されるので、部分更新の配管を複数作らない。文字入力中は腕が反転しない限り
> 通信なし — debounce は属性備え付け。

### 対比 2 — 楽観的追加（押した瞬間に行が入る）

**Hotwire 側（代表形）— 楽観は Stimulus、正は Turbo Stream**

```js
// 楽観的に置くには Stimulus で先に DOM を作る —
// 差し込み口・順序・鍵の整合は自前管理になる
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "row"]
  submit(event) {
    event.preventDefault()
    const li = this.rowTarget.content.firstElementChild.cloneNode(true)
    li.querySelector("[data-title]").textContent =
      event.target.querySelector("[name='task[title]']").value
    this.listTarget.prepend(li)
  }
}
```

```erb
<%# app/views/tasks/create.turbo_stream.erb — 後から「正」が届く配管は別 %>
<%= turbo_stream.prepend "tasks", @task %>
```

> 楽観側と正側が別の仕組みに別れがち。順序や重複、鍵照合は手で管理する領分。
> （もっと手軽に Turbo Frame で送るなら、それは**往復待ちの描画**になり楽観でなくなる）

**ReActionView 側（実物）— 属性3つ**

```erb
<%# app/views/tasks/index.html.erb %>
<form action="<%= tasks_path %>" method="post"
  data-herb-into="tasks"
  data-herb-set="submit->drawer_open=false"
  data-herb-reset="submit->title">
```

```rb
# app/controllers/tasks_controller.rb — 201 で新規「行」だけ届ける
format.slots do
  @tasks = Task.where(id: task.id)
  render :index, status: :created # 201 + 行の statics
end

# no-JS の従来フォールバックも同じコントローラで
format.html do
  flash[:notice] = "タスクを追加しました"
  redirect_to root_path
end
```

> **201 応答の collection splice**。クライアントは鍵付き照合で**新規行だけ**差し込み
> （既存行は動かない）。行の statics は GET と同じテンプレートコンパイルから出るので
> 整合が取れる。ドロワーを閉じる/クリアする `data-herb-set` / `-reset` も form と同時発火。

### 対比 3 — ライブ入力とバリデーション（ここが Stimulus の独壇場だったはず）

**Hotwire 側（代表形）— コントローラ＋3ターゲットの同期**

```js
// app/javascript/controllers/char_count_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "count", "submit"]
  connect() { this.update() }
  update() {
    const v = this.inputTarget.value
    this.countTarget.textContent = `${v.length} 文字`
    this.countTarget.classList.toggle("over", v.length > 60)
    this.submitTarget.disabled = v.length === 0 || v.length > 60
  }
}
```

```erb
<textarea data-controller="char-count"
  data-action="input->char-count#update">…</textarea>
<span data-char-count-target="count"></span>
<button data-char-count-target="submit">保存</button>
```

> Turbo に入力毎の反応機構は基本無いので、これはどの実装でも Stimulus に落ちる。
> （Turbo Stream 往復で作るなら打鍵ごとの点滅になる）

**ReActionView 側（実物）— 宣言1行**

```erb
<%# app/views/showcase/lab.html.erb（機能⑦/⑫ の抜粋） %>
<%# herb:state (draft: "", ready: draft != "", bio: "",
      ready_bio: bio != "" && bio.length <= 60, over: bio.length > 60) %>

<textarea value="<%= draft %>" aria-label="下書き入力" placeholder="下書きを入力…"></textarea>
<p><%= draft.length %> 文字<% if ready %>・送信準備OK<% end %></p>
<button disabled="<%= !ready %>">送信</button>

<%# bio 側は文字数オーバー: over で ⚠ ピル、ready_bio で保存ゲート %>
```

> **派生状態の宣言**だけで、文字数・出し分け・disabled 全部が **0 往復**で反応する。
> `ready_bio` はコンボ派生、`over` は length 変換＋順序比較として manifest に入る。
> なお textarea は `value=` 束縛なので、リセット後も表示まで追従する。

### 対比 4 — 行ごとの数量ステッパー（per-item 状態）

**Hotwire 側（代表形）— 行ごとの状態は JS 側 dataset（HTML から見えない）**

```js
// app/javascript/controllers/stepper_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  step({ currentTarget, params }) {
    const row = currentTarget.closest("[data-row]")
    const qty = Math.max(0, (Number(row.dataset.qty) || 0) + params.delta)
    row.dataset.qty = qty
    row.querySelector(".qty").textContent = qty
    row.querySelector(".minus").disabled = qty === 0
    this.recalcTotal() // 全行を走査して合計を張り直す
  }
}
```

> 合計の再計算も Stimulus 預け（逆にここなら金額×数量も書ける — §⑥の境界と引き換え）。

**ReActionView 側（実物）— 属性1組**

```erb
<%# app/views/components/ui/_stepper.html.erb %>
<%# herb:state (in_cart: 0) %>   <%# 行ごとに: %>
<%# herb:state (qty: 0) %>

<button data-herb-decrement="qty" disabled="<%= qty == 0 %>" aria-label="減らす">−</button>
<span class="ui-stepper-qty"><%= qty %></span>
<button data-herb-increment="qty" aria-label="増やす">＋</button>
<% if qty > 0 %><% in_cart += 1 %><% end %>

<%# 統計はリストの直後（fold が完了してから読む） %>
<%= in_cart %> 点をカートに追加
```

> **state は HTML に住んでいる**（行ごと宣言、hidden への presence）。
> 鍵付き item に紐づいた状態なので、行が増減しても state が追従する。
> ただし `in_cart` は計数 fold（`+= 1` の整数リテラル増分のみ）—
> 金額合計は「クライアントでは作れない」が正確な境界（§⑥）。

---

## ④ 概念読替表

| Hotwire の部品 | 役割 | ReActionView での代わり | 実装場所 |
|---|---|---|---|
| `<turbo-frame>` | 局所更新の枠 | `data-herb-name` コレクション＋`<%# herb:key … %>`（鍵付き差分適用） | tasks/index, patterns |
| Turbo Stream（append / replace…） | 応答後の部分操作 | POST 201 の collection splice（`data-herb-into`） | tasks#create |
| `form_with` ＋ submit リスナー | 値の往復 | `data-herb-set="query=$value"` ＋ `data-herb-debounce`（form不要） | tasks/index |
| Stimulus（入力リアクティブ） | 派生値・妥当性 | `<%# herb:state (…) 派生宣言 %>` と presence 束縛（`disabled`, `checked`, `hidden`） | lab 機能⑦⑫, ui/_switch |
| Stimulus（per-item targets） | 行ごとの状態 | 行内 `<%# herb:state (qty: 0) %>` ＋ `data-herb-increment/decrement` | lab 機能⑬, ui/_stepper |
| Stimulus / dialog 要素 | 開閉・Esc・backdrop | `<% if drawer_open %>` ＋ `data-herb-set="click@outside->… keydown.esc@window->…"` | tasks 機能③, lab 機能⑥ |
| `classList.toggle` / `hidden` 直接操作 | 見た目切替 | `data-herb-toggle` ＋ CSS `:has()` / `[hidden]` ガード | ui/_switch, lab 機能⑭ |
| importmap の turbo / stimulus pins | JS ランタイム | `import "reactionview"` 1行（gem が pin 済み・ビルドなし） | app/javascript/application.js |

---

## ⑤ 往復はいつ飛ぶか — DevTools で数えられる形で

「Turbo より通信が減る」は口でなく `?format=slots` のリクエスト数として読めます。

- **server mode（`/`, `/patterns`）**: 往復は**state を読む分岐の腕が反転した時だけ**1回。
  検索の腕反転は `<% if query.empty? %>` がトリガ、ソート select 単体は 0（実測）。
  連続タイピングで腕が反転しない間は行を触らず、文字はクライアント評価で更新。
  - なお steering（`Herb-State` ヘッダ）に載るのは**分岐の条件が読んでいる state** に限る。
    往復させたい state は必ずどこかの state 条件分岐に読ませる —
    Patterns の3本柱（`if / elsif` 連鎖、`page > 1`、`selected_id > 0`）はその実装。
- **client mode（`/lab`, `/ui`）**: 全操作 **0 往復**。未描画ブランチは初期レスポンスの
  `<template data-herb-region>` に格納済みで、`<template data-herb-manifests>`
  （states / reads / conditionals / presence / computed の命令書）に従って
  ブラウザ内で腕の materialize・presence・fold が進む。
  UI Kit の9コンポーネント全操作は slot 往復 0 を実測（`docs/ui-kit.md`）。
  意図的に同期を取り直したい時だけ `data-herb-action="$refresh"` が脱出ハッチ。
- **共通の帳尻**:
  - `$refresh` 等の action は `data-herb-set` と同要素に併置できる（同 dispatch の state は 1 リクエストに合流）
  - no-JS 環境では form が通常の POST → `format.html` の redirect／flash で完結
    （フォールバック契約を統合テストで固定）
  - 応答は HTML でなく値の JSON（`application/vnd.herb.slots+json`）— 行まるごとの再送ではない

---

## ⑥ 正直な境界 — 0.6.0 時点の実測で書けないもの

営業コピーではなく実測ノートなので、クライアント評価が届かない枠も並べます。
どれも対処パターンが確立済み。

- **演算・金額合計は fold に載らない** — fold の増分は整数リテラルのみ
  （`<% in_cart += 1 %>` の3タグ形）。`total += price * qty` 系は設計段階で諦め、
  サーバー側の READ slot（1 往復）に置く。派生の変換テーブルも
  `.length` / `.size` / `.to_s` のみ。
- **ループデータとの比較は literal のみ** — `task.id == selected_id` は ErrorInTemplate。
  コントローラから ivar（`@selected_id`）を渡し、per-row の属性スロットとして
  往復させる（patterns の実装）。
- **per-item 分岐の腕に置いたサーバー読みの値は空で届く** — statics は materialize
  されるが値は乗らない（0.6.0 実測）。対処は「答えを腕に置かない」:
  `hidden="<%= !open %>"` の presence 束縛＋CSS `[hidden]` ガード
  （lab 機能⑭、ui コンポーネント全体）。
- **パーシャル内の分岐腕は parked されない** — client mode でも region テンプレート
  自体が出ない（ui-kit 実測）。パーシャルでは腕でなく presence（hidden）＋CSS で切替、が定石。
- **POST 201 の splice は collection のみ** — region 級のサーバー読み（`Task.count` 等）
  は次の GET でしか追いつかない。追加直後の hero は `$refresh` 頼み、という手順を
  見せるのが誠実。
- **server モードでブラウザ所有 state を条件にした分岐を置かない** — steering に
  載らず、要求が常に行禁化（要求 storm）。見た目は presence＋CSS、数値は READ slot へ。

> **この境界の読み方**: 「Stimulus を捨てると何ができなくなるか」が暗黙でなく明文化されて
> いるのが検証リポジトリとしての価値。`bin/rails test` は HTMLレンダ / herb_state による
> 並び替え / slots 応答 / no-JS フォールバックの契約を固定しているので、境界の再現性も
> コミットで追跡できます。

---

## ⑦ 次に足すなら — 「Hotwire 不要」をさらに刺す候補UI

1. **行とヘッダの同時連動（ピン/星）— 最有力**: 行の星を押すと、行の見た目とヘッダの
   「ピン済み N」が即時に揃う。星の塗りは presence 束縛＋CSS、`N` は計数 fold
   （`when: "pinned"`）でクライアント評価 — **0 往復**。Hotwire なら2か所の DOM 同期
   （Stimulus）か Stream 往復が要る。既存の実測パターン（presence + fold + toggle）の
   組合せのみで組める。
2. **横並べ比較画面（`/compare`）**: `turbo-rails` を Gemfile に足し（importmap pin のみ・
   ビルドレス）、同じタスク管理を Turbo Frame/Stream 版と ReActionView 版で並べ、
   Network 往復とコード量を横に対応させる。決定的な説得力はあるが、Gemfile 変更の
   範囲確認が必要。
3. **送信前計算フォーム（送料・合計）**: 入力に連動して合計や保存ボタンが変わるUI。
   `price * qty` は fold 外なので READ slot の **1 往復**で答える「正直版」—
   Hotwire では Stimulus なしに書けない局面を ReActionView が1往復で置く形を示せる。
   §⑥の境界の正面の実例になる。

---

実測の経緯と制約の詳細は `AGENTS.md`（ReActionView メモ / 実測済みワイヤ形式）と
`docs/ui-kit.md` 参照。生成日: 2026-10-25。
