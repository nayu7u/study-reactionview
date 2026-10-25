# AGENTS.md

## 目的

このリポジトリは ReActionView の検証アプリ。Kaigi on Rails 2026（Marco Roth: "Herb in Rails 8.2"）の
主張 — **ERB のみで Phoenix LiveView 的な細粒度リアクティビティ** — を、実用的なアプリ風の
機能別ショーケースで実演・検証している。ReActionView 0.6.0 + herb 0.11.1
（0.11.0 から 0.11.1 への更新は bin/ci 全ゲートで再検証済み。ワイヤ形式の実測メモは変らず通用）。

2画面構成: `Sprint Hub`（`/`, server mode: 検索/ソート/ドロワー/楽観的追加）と
`Client Lab`（`/lab`, client mode: 分岐のparked保管・派生状態・palette）。

## 作業規約（必ず守る）

- コード: How を表現する
- テストコード: What を表現する
- コミットログ: Why を記録する（コミット単位は作業の区切りごと、経緯が追跡できるように）
- コードコメント: Why not を書く（なぜ別のやり方をしないのかを明示。前提の再説明はしない）
- こまめにコミットする

## ReActionView メモ（調査済み事実）

- 設定は `ReActionView.configure` のブロック引数 `config` を使う。`ReActionView.configuration`
  というアクセサは **存在しない**（bin/rails runner での検証用コードは `ReActionView.config` を見ること）
- `config.slots = true|false|:server|:client`。`true` のとき `default_slot_mode` は `:server`
  （ブラウザ所有の state 変化でもサーバーに問いに行くモード）
- importmap-rails 環境では JS クライアントは gem が自動で pin する。`config/importmap.rb` に手書きは不要
  （`app/javascript/application.js` への `import "reactionview"` のみでよい）
- Node/yarn が無い環境。ビルドステップなし importmap を使う（これは ReActionView の売りとも一致）
- slots リクエストの形: `GET /messages?format=slots` + `Accept: application/vnd.herb.slots+json`
  + `Herb-State: {"<テンプレートパス>": {"<state>": "<値>"}}`。応答は HTML でなく値の JSON
- `herb_state(name, default)` がコントローラ・ビュー両方で使える（`config.slots` 有効時のみ）
- ループ行は `<%# herb:key message.id %>`。無いと行再構築＋コンパイル時ワーニング

## 動作確認コマンド

- サーバー: `bin/rails server`（dev でスロット用開発サーバーが内蔵起動し、アドレスを表示。
  アセットを追加・リネームしたら再起動すること — Propshaft は起動時にロードパスを確定させ、
  実測では旧プロセスが app.css を見失い 500 を返し続けた）
- 設定出力: `bin/rails runner 'c = ReActionView.config; puts [c.intercept_erb, c.slots, c.default_slot_mode, c.dev_server_enabled?].inspect'`
- seed: `bin/rails db:setup`（schema 缶詰後は `bin/rails db:seed`）
- 統合テスト: `bin/rails test`（reactive 契約 = HTML レンダ / herb_state による並び替え / slots 応答 / no-JS フォールバック）

## 実測済みのスロット・ワイヤ形式（0.6.0）

- 応答ヘッダ: `content-type: application/vnd.herb.slots+json; charset=utf-8`、`Cache-Control: no-store`
- 本体: `{"template": "...", "version": "...", "occurrence": 0, "slots": {<番号>: {...}}}`
  - 分岐は `{"branch": 0|1|…|null, "statics": "<マークアップ>", "slots": {...}}`
  - コレクションは `{"items": {"<実ID>": {"<パート番号>": "<値>"}}, "order": ["<ID>", …], "statics": "<行テンプレート>"}`
    — React流の鍵付き照合で、クライアントは行を再構築せず移動・差し替えする
- `POST …?format=slots` は **201** で新規行のみを返す（楽観的追加の差し替え用）
- `herb:slots server` 時、textarea は `data-herb-slot="N:raw_text"`、補間属性は `…:attribute:name` として分岐外のスロットへ載る
- client mode では未描画ブランチが `<template data-herb-region="app/views/<テンプレート>:<version>">` に
  `<!--herb-branch:<番号>:<腕>-->` 付きで格納され、`<template data-herb-manifests>` に**クライアントへの命令書**がJSONで載る:
  `states.declarations`（kind/derived/scope）、`reads`、`conditionals`（条件の腕）、`presence`（boolean属性束縛）、
  `computed`（`.length` 等の変換）、`server`
- `server` マップ（`server.branches` / `server.reads`）: 平常時（GET初期描画・全client-evaluable）は
  serverモード・client mode の**両方**で空。埋まるのは「分岐の腕に server-read（任意のRuby/ループデータ）が
  混ざったとき」— client mode でメンション腕に `.select` ループを置いたら `branches` に node_path が列挙された。
  「serverモードで埋まる」説は撤回（モード判別には使えない）

## テストにまつわる実測の教訓

- `response.media_type` は charset を含まない（パラメータは別途）
- スロット/パート番号はテンプレートの変更で**再番号付けされる**。アサートはインデックス番号でなく
  「items を持つスロットを探す」等の形で引くこと
- JSON本文中のstaticsはエスケープされる（`\"`）。文字マッチはpayloadをparseして読む
- fixtureはテストごとに自動ロードされる。生成デフォルト（one/two）が漏れていると比較が形骸化や着火するので、
  fixtureを明示的データで書き換えるのが早い
- test環境では debug span（`data-herb-debug-*`）が付かない（debug_mode = development?）ため、
  マーカー正規表現は開発環境と別形になる

## テンプレートにまつわる実測の教訓

- **`case` + `when` を1つのERBタグに詰めない**: Herb はパース不能として ErrorInTemplate。
  `<% case x %><% when "a" %>…<% when "b" %>…<% else %>…<% end %>` と各々別タグにする
- **コレクションを `<% if @tasks.any? %>` 等の分岐で包むな**: slots応答が items/order 形式ではなく
  分岐の statics として全体が返り、鍵付き差分適用が壊れる。コレクションは必ずレベルを保つ
- **行クラスの状態補間（`class="<%= … if done %>"` など）を書かない**: `attribute_interpolation` スロット =
  サーバー読み＝チェックのたびに往復。presence 束縛（`checked`）+ CSS `:has(input:checked)` で即時描画に寄せる
- **計数foldの公式形は3タグ**: `<% if done %><% done_count += 1 %><% end %>` をキー付きitem body内に。
  `done_count += 1 if done`（修飾子if）は fold_increment が1文としてパースできず、
  「client never sees a server-side write」という紛らわしいエラーになる。
  counted state は **ループより前で読むな**（heroの統計文はリスト直下へ移動した）。
  マニフェストには declarations[i].count = {collection, when, by} として現れる
- **aria-pressedはpresence束縛でなく文字列補間**: `aria-pressed="<%= tab == "all" %>"` は
  "true"/"false" の文字列属性として出る（checked/selected/disabled の boolean属性束縛とは別物）。
  client mode では純状態比較なのでクライアント評価＝往復なし。CSSは `[aria-pressed="true"]` で引く
- **serverモードではブラウザ所有statesを条件にした分岐を書くな**: 腕がparkedされずクライアントに
  materializeできず → switchBranch失敗 → refetch が追加されるが、steeringにitem状態(done)や
  counted(done_count)は載らないのでサーバー回答が常に行禁化→要求storm。見た目は presence＋CSSで、
  数値はREAD slot（`<%= done_count %>`）で置く。行の文言ピルも同様（両方の文言をDOMに置き
  `:has(input:checked)` で切替）
- **POST 201 の応答で適用されるのは collection のspliceのみ**: region級のサーバー読み（`Task.count` 等）は
  GET応答でしか適用されない（検索の往復ではバッジが動くのに、追加直後には動かない — 実測）。
  追加直後は `$refresh`（または次のGET）でheroが追いつく。GIF／レポートではこの手順を見せる
- **create応答のspliceはquery/filter状態を無視して入る**（コントローラーのcreateスコープに
  フィルターが無いため）。検索中に追加すると絞り込まれていない行が差し込まれる
- slots応答の slots 値は**スカラー（数値/真偽/文字列）が混ざる**。Hashと決め打ちしない
  （hero の合計はスカラー、presence束縛は真偽値、分岐は Hash{branch, statics, slots}）
- create 応答はコントローラーが絞ったスコープで一式を再計算する。
  「全件の合計」を `@tasks.size` で出すと一瞬 1件表示になるため、合計は `Task.count` のように独立に取る
- `herb_state` をコントローラーから呼ばないと、ビュー側だけ state を読んでいてもフィルターは効かない
 （Toolbarが様になってにもかかわらず、起きた）。ビューとコントローラー両方が設計側物として読む必要がある

## 調査ツール

- debug-mcp（Kaigi on Rails 2026・riraさんの講演）は **adopt-on-demand**: 実行時状態に依存するバグで
  tests+curl+ブラウザで説明がつかない局面で導入する。手順は `docs/debug-mcp-runbook.md`
  （stdio MCP・opencode.json に local 登録・`RUBY_DEBUG_OPEN=true bin/rails server` で attach）

## やらないこと（Why not 付き）

- Rails 8.2 / `config.action_view.html_erb_implementation` には手を出さない
  → rubygems 上の最新リリースは 8.1.4 であり、8.1 では intercept_erb が Herb 経由化の正攻法だから
- Node/yarn の導入をしない → importmap で完結する。追加ツールはこの検証の主題と無関係な摩擦を増やすだけ
- Tailwind / PostCSS / あらゆるビルドパイプラインをスタイルで導入しない
  → ビルドステップゼロがデモの前提。app.css に素のCSS（デザイントークン含む）で書く
- 行クラスのstate補間（`class="<%= … if done %>"` のようなもの）を戻さない
  → 属性補間はサーバー読みスロットになりチェックごとに往復する。
  見た目の状態は presence 束縛（`checked`）+ CSS `:has(input:checked)` で即時追随させる
- モーダルフォームを `board_path` にPOSTさせない → board はGETルートのみ。CRUDの入口は
  `tasks_path`（正攻法の分離）。`data-herb-into` はスプライス先コレクションの名前指定に過ぎない
