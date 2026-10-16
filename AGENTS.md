# AGENTS.md

## 目的

このリポジトリは ReActionView の検証アプリ。Kaigi on Rails 2026 での発表に基づき、
ERB のみで Phoenix LiveView 的な細粒度リアクティビティを実現するという主張を
実際にインストール・動作確認している。ReActionView 0.6.0 + herb 0.11.0
（リアクティブテンプレート要求バージョンに一致）。

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
  `<!--herb-branch:<番号>:<腕>-->"` 付きで格納され、`<template data-herb-manifests>` に**クライアントへの命令書**がJSONで載る:
  `states.declarations`（kind/derived/scope）、`reads`、`conditionals`、`presence`（boolean属性束縛と `.blank?` 等）、
  `computed`（`.length` 等）、そして client-mode の証拠として `server: {branches: {}, reads: {}}`。
  サーバーモードでは同一テンプレートでも server マップが埋まる

## テストにまつわる実測の教訓

- `response.media_type` は charset を含まない（パラメータは別途）
- スロット/パート番号はテンプレートの変更で**再番号付けされる**。アサートはインデックス番号でなく
  「items を持つスロットを探す」等の形で引くこと
- JSON本文中のstaticsはエスケープされる（`\"`）。文字マッチはpayloadをparseして読む
- fixtureはテストごとに自動ロードされる。生成デフォルト（one/two）が漏れていると比較が形骸化や着火するので、
  fixtureを明示的データで書き換えるのが早い
- test環境では debug span（`data-herb-debug-*`）が付かない（debug_mode = development?）ため、
  マーカー正規表現は開発環境と別形になる

## やらないこと（Why not 付き）

- Rails 8.2 / `config.action_view.html_erb_implementation` には手を出さない
  → rubygems 上の最新リリースは 8.1.4 であり、8.1 では intercept_erb が Herb 経由化の正攻法だから
- Node/yarn の導入をしない → importmap で完結する。追加ツールはこの検証の主題と無関係な摩擦を増やすだけ
