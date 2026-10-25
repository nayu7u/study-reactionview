# Study ReActionView

**ReActionView 0.6.0 + Herb 0.11.0 の検証ショーケース**であり、Kaigi on Rails 2026（Marco Roth: "Herb in Rails"）の主張、
すなわち **ERB だけで React 的な細粒度リアクティビティが成立する** ことを、二つの実用的な画面で実演・検証する。

- React / Stimulus / Node / yarn / ビルドパイプライン: **一切なし**。`app/javascript/application.js` は
  `import "reactionview"` の 1 行だけ。スタイルは `app.css` 1 枚の素の CSS（デザイントークン含む）。
- 細粒度の更新は Herb の slots が担う。state 変化に対して、HTML ではなく値の JSON
  （`application/vnd.herb.slots+json`）だけが往復し、クライアントが差分を当てはめる。

## 2つの画面

| 画面 | 宣言 | 見せていること |
|---|---|---|
| Sprint Hub `/` | `<%# herb:slots server %>` | サーバーが答える読み取り、key 付き行の差分更新、楽観的追加 |
| Patterns `/patterns` | `<%# herb:slots server %>` | 実務で撮る3パターン: フィルタチップ、もっと見る、詳細連動 |
| Client Lab `/lab` | `<%# herb:slots client %>` | 未描画分岐の格納（parking）、派生状態、サーバー往復ゼロのUI |

```console
$ bin/rails db:setup   # または db:seed
$ bin/rails server     # http://localhost:3000
```

## Sprint Hub（server モード、`/`）

検索・並び替え・追加はすべてサーバー側で行う。state はリクエストごとにブラウザからサーバーへ渡り、
同じアクションが HTML ではなく値で応える。

<div><img src="docs/media/hub-light.png" alt="Sprint Hub (light)" width="49%"/> <img src="docs/media/hub-dark.png" alt="Sprint Hub (dark)" width="49%"/></div>

### 機能① サーバーが答える読み取り

![検索・並び替えはサーバーが絞り込む](docs/media/01-server-reads.gif)

- 検索語・並び順は `herb_state("query")` / `herb_state("order")` としてコントローラーでも宣言し、
  ビューとコントローラーの両方が同じ名前で読む。これで最初の描画から filter が効く。
- 入力は `data-herb-debounce="220"`。打鍵のたびの往復を 220ms にまとめて、同じ `GET /?format=slots` が答える。
- リストの行は `<%# herb:key %>` 付き → 応答は `{items, order}` の鍵付き照合になり、行は移動する
  （再構築しない）。並び替え GIF で行がアニメーションせず“その場で並び替わる”のは、鍵のおかげだ。
- `$refresh`（🔄 同期）だけが明示的な「サーバーに全部聞き直す」出口。

### 機能② 細粒度更新＋計数fold

![行のチェックは往復なし、統計はfoldで即時](docs/media/02-row-state.gif)

- 取り消し線・行の文言ピルは **presence 束縛**（`checked="<%= done %>"`）＋ CSS `:has(input:checked)`
  で即時描画する。ピルは「✔ 完了」「未完了」の両方を DOM に積んで CSS で表示を切り替えている。
  server モードではブラウザ所有 state を分岐の条件には書けない（未描画側が格納されず refetch storm になる）。
- 統計「N/M 件完了」は **計数fold** で作る。キー付き行の中に
  `<% if done %><% done_count += 1 %><% end %>` の 3 タグを置くのが公式形だ。manifest には
  `count: {by: 1, when: ["done"]}` として現れ、チェックのたびにサーバー往復なしで client が計算し直す。
- 「行の見た目を属性値の補間で表現しない」（`class="<%= … if done %>"` を書かない）のが原則だ。
  属性補間はサーバー読みスロットになり、チェックのたびの往復を生む。見た目は CSS、数値は read slot で分担する。

### 機能③ 楽観的追加

![追加は 201 の新規行だけで入り、同期で確定](docs/media/03-optimistic-add.gif)

- 「＋ 新規タスク」でスライドインする backdrop ドロワー。分岐はサーバー描画のまま答える。
- 送信は楽観的で、ボタンを押すと応答を待たずに行がスプライスされる（`data-herb-into="tasks"`）。
  応答は 201 で新規行だけを返し、クライアントは `items` の splice で受ける。
- 送信に成功するとドロワーは閉じ、打ち込んだ title もリセットされる
  (`data-herb-set="submit->drawer_open=false"` と `data-herb-reset="submit->title"` の二本立て)。
- hero の合計（`Task.count`）は GET 応答では更新されるが、POST splice ではされない。
  0.6.0 のクライアントが 201 で適用するのは collection だけだ。だからシーンの最後で 🔄 同期を押して
  「楽観 → 確認」の流れを見せている（実測の制約は AGENTS.md にある）。
- JS を切っても成立する。hidden token 付きのふつうの `<form method="post">` として POST し、flash 付き redirect が返る。

### 機能④ window 句

![⌘B で開き、Esc で閉じる](docs/media/04-window-clauses.gif)

- `data-herb-set="keydown.meta+b@window->drawer_open=true"` で、⌘B（Ctrl+B）でもドロワーが開く。
  要素の外（window）にリスナーを張る句だ。`modifier AND match` の設計上、`meta+b` と `ctrl+b` は別句にする
  （1 行では OR にできない）。
- 閉じる側は `click@outside->…=false` と `keydown.esc@window->…=false` の複合だ。

## Patterns（server モード、`/patterns`）

同じ tasks テーブルを「受信箱」として組み直した、実務寄りの3パターン。すべて server mode で、
往復するのは値だけ（検索・並び替えと同じ契約）。

### 機能⑧ フィルタチップ（サーバー絞り込み＋件数バッジ）

- 優先度（1=低/2=中/3=高）は `tasks.priority` 列。チップの絞り込みは `herb_state("priority")` を
  コントローラーとビューの**両方**で読む（hub の検索と同じ契約）。
- チップのクリックは 1 属性に 2 state を代入する: `data-herb-set="priority=3 page=1"`。
  空白で区切った token は別 binding として各々実行される（クライアント実装の実測）。
- 選択中チップは `aria-pressed` の文字列補間。CSS は `[aria-pressed="true"]`。
  **state 比較は literal のみ**（`value.to_s` のような式は ErrorInTemplate）なので、
  チップは4個を literal 展開している。
- 件数バッジは `Task.group(:priority).count`。スカラーとして slots 応答に乗る。

### 機能⑨ もっと見る（鍵付き差分で行が増える）

- `page` は Integer state。「もっと見る」は `data-herb-increment="page"`。
  同じ GET slots 往復で `order`/`items` が伸び、クライアントは既存行を動かさず新しい行だけ足す。
- 全件読み込み済みの腕（「全部読み込みました」）は **ivar 条件の分岐**（`<% if @remaining > 0 %>`）。
  server モードでは state 条件でなくても wire に `branch` 値＋腕 statics が乗り、
  初期 HTML の `<!--herb-branch:N:腕-->` マーカーと突き合わせて切替が起きる。

### 機能⑩ 詳細連動（行選択→同じアクションが詳細を答える）

- 行クリックは `data-herb-set="click->selected_id=<%= task.id %>"`。詳細パネルは
  `@selected` 条件の分岐で、値は全部 `data-herb-name` の名前付きスロットで乗る
  （腕の statics は初回固定でも、スロットは毎往復差し変わる — ドロワーの文字数と同じ理屈）。
- 行のハイライトは `aria-current="<%= task.id == @selected_id %>"` — **loop データとの比較は
  state に書けない**ので controller 渡しの ivar と比較し、per-item の属性スロットとして往復する。
  鍵付き item の中の属性補間が wire に乗ることは実測済み（`aria-current`、prio クラスとも）。
- 選択解除は `data-herb-reset="selected_id"`。消えた行の ID が選択された場合は
  空の腕（`@selected` 条件）に退避して空文字の詳細を描かない。

## Client Lab（client モード、`/lab`）

この画面の未描画の分岐（タブの裏側・モーダル・hover の表示）は、初回 HTML に `<template data-herb-region>`
として格納済みだ。開閉・切替・カウントはすべてブラウザ内で完結する。`$refresh` だけが意図的な脱出口だ。

<div><img src="docs/media/lab-light.png" alt="Client Lab (light)" width="49%"/> <img src="docs/media/lab-dark.png" alt="Client Lab (dark)" width="49%"/></div>

### 機能⑤ 分岐の格納とセグメント切替

![タブの切替は往復ゼロ](docs/media/05-client-mode.gif)

- `tab` の両側（すべて / メンション）は、client モードでもサーバーが初回に両方描いて格納する。
  切替はクライアントが格納済みの分岐を採用するだけだ。メンション側は
  `@notifications.select { |n| n[:kind] == "mention" }` の行データとして別に格納してある。
- `aria-pressed="<%= tab == "all" %>"` は文字列 "true"/"false" の属性補間として出る
  （checked/selected の boolean 属性束縛とは別物）。client モードでは状態の比較だけだから、
  クライアント側で評価でき、往復はない。CSS は `[aria-pressed="true"]` で引く。

### 機能⑥ カウンタとコマンドパレット

![⌘Kパレットも往復ゼロ](docs/media/06-palette.gif)

- `data-herb-increment / decrement / reset` でカウンタを操作する。`data-herb-by="2"` を付けると一度に ±2 動く。
- ⌘K（Ctrl+K）またはクリックで開く palette 型モーダル。Esc と backdrop のクリックで閉じる。入力の文字数は即時に表示される。
- `data-herb-reset`（引数なし）は「全部戻す」で、全 states を既定値へ戻す。

### 機能⑦ switch 束縛と派生状態

![switchと派生のready](docs/media/07-derived.gif)

- `checked="<%= mute %>"` の switch は presence 束縛だ。🔕/🔔 の文言も両方置いて CSS で切り替える（機能②と同じ理屈）。
- `<%# herb:state (draft: "", ready: draft != "") %>` が **派生宣言**だ。`draft` が空でなければ `ready` が真になり、
  文字数表示の即時化と `disabled="<%= !ready %>"` の送信ボタンの有効化がクライアント内で完結する。

### 機能⑪ 多段ウィザード（step状態と派生ゲート）

- `step`（Integer state）の三つ分岐は `<% if step == 1 %>` の**別タグに展開**した三ブロック
  （case+when を1タグに詰めると Herb がパース不能になる教訓の if 版）。
- 「次へ」は `data-herb-increment="step"`、ゲートは派生状態 `name_ok: name != ""` を presence 束縛した
  `disabled`。腕ごとに入力が置ける（未描画腕の input も停めてある）。
- 完了腕は `data-herb-reset="step name email"` — 複数 state を空白で並べて一気に戻せる。

### 機能⑫ 入力バリデーション（length変換＋順序比較＋コンボ派生）

- `over: bio.length > 60` — 派生宣言に `.length` 変換と順序比較が書ける。オーバー時は警告ピルの腕が差し替わる。
- 送信ゲートはコンボ派生 `ready_bio: bio != "" && bio.length <= 60`。manifest には
  `{"all" => [["bio","","!="], ["bio",60,"<=","length"]]}` として現れる。
- 演算（20 - length など）は不可能（変換は `.length` / `.to_s` のみ）。だから表示は「N/60字」の形。

### 機能⑬ 数量ステッパー（行ごとの数量＋計数fold）

- `qty` は行ごとの Integer state。減ボタンは `disabled="<%= qty == 0 %>"` — 順序比較の presence 束縛で
  0 で握る（見た目の即時性は CSS、数値は read スロット、の分担は hub と同じ）。
- `<%= in_cart %>` 件の合計は**条件付き fold**（`<% if qty > 0 %><% in_cart += 1 %><% end %>`）。
  fold の when に順序比較が書ける。counted state をループの**前**で読むとコンパイルエラー
  （「count is complete 前」）になるので、統計行はリストの後に置く。
- 金額合計は作れない: fold の増分は整数リテラルのみ（`total += price * qty` は不可）。

### 機能⑭ アコーディオン（行ごとの open と停まった答えの腕）

- `open` は行ごとの boolean state。ヘッダーは `data-herb-toggle="open"`、本文の腕は parked。
- 腕にはサーバー読み（`faq[:a]`）が混ざるので manifest の `server.branches` に node_path が載り、
  クライアントが腕を materialize する際にサーバーへ値を取りに行く（メンションタブの腕と同じ機構の
  per-item 版 — 録画時にブラウザで確認する）。

## 検証の進め方

- **統合テスト: `bin/rails test`**。`tasks_controller_test` / `patterns_controller_test` / `showcase_controller_test` が検証する契約は、
  HTML レンダ / `herb_state` による並び替え・絞り込み / slots 応答の形状（items+order / 分岐 / スカラー混在）/
  201 splice / no-JS フォールバック / fold が manifest に現れることだ。テストは What を、
  コードは How を、コミットログは Why を書く約束。
- 初期 HTML には `<template data-herb-manifests>` として、クライアントへの命令書が載る
  （`states.declarations` / `reads` / `conditionals` / `presence` / `computed` / `server`）。DevTools で覗くと
  「何が往復せず動くか」が読める。
- dev モードでは右上に Herb バッジが出る。テンプレートタグをわざと壊すと、ファイル名＋行番号付きの
  エラーオーバーレイが出る（各 footer に案内あり）。tests + curl + ブラウザでも説明がつかない局面では、
  `docs/debug-mcp-runbook.md`（debug-mcp の adopt-on-demand 手順）を参照する。

## テンプレートの実測メモ

この検証で判明したエンジンの事実（fold の公式形、server モードと client モードの制約、slots ワイヤの形、
`<%# herb:state %>`を controller でも宣言する必要性など）は、[AGENTS.md](AGENTS.md) に随時記録している。
テンプレートを改変する前には必ずそこを当たること（境界を意図的に押して壊した記録が多い）。
