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

- サーバー: `bin/rails server`（dev でスロット用開発サーバーが内蔵起動し、アドレスを表示）
- 設定出力: `bin/rails runner 'c = ReActionView.config; puts [c.intercept_erb, c.slots, c.default_slot_mode, c.dev_server_enabled?].inspect'`
- seed: `bin/rails db:setup`（schema 缶詰後は `bin/rails db:seed`）

## やらないこと（Why not 付き）

- Rails 8.2 / `config.action_view.html_erb_implementation` には手を出さない
  → rubygems 上の最新リリースは 8.1.4 であり、8.1 では intercept_erb が Herb 経由化の正攻法だから
- Node/yarn の導入をしない → importmap で完結する。追加ツールはこの検証の主題と無関係な摩擦を増やすだけ
