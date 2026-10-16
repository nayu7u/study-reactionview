# Study ReActionView

Kaigi on Rails 2026 の発表（Marco Roth: "Herb in Rails 8.2" / ReActionView）の主張、
**ERB のみで React / Phoenix LiveView 的な細粒度リアクティビティが実現できる**
を、このRailsアプリで実際にインストール・動作確認するための検証リポジトリです。

## 実装済みデモ（`/messages`）

`app/views/messages/index.html.erb` 1枚のテンプレートに、以下のリアクティブ要素が全部入っています。

| 要素 | 記法 | 動き |
|---|---|---|
| 宣言的状態 | `<%# herb:state (composing: false, order: "oldest", draft: "") %>` | ブラウザが状態を所有 |
| 出し入れトグル | `<button data-herb-toggle="composing">` | フォームが再読込なしで開閉 |
| ソート※サーバー応答 | `<select data-herb-set="order=$value">` + `herb_state("order", "oldest")` | コントローラが同じ `index` で答え、行が鍵付きで移動 |
| 文字数カウンタ（クライアント評価） | `<textarea><%= draft %></textarea>` + `<%= draft.length %> characters` | 往復なしで更新 |
| リストの鍵 | `<%# herb:key message.id %>` + `data-herb-name` | 行は再構築されず移動/差し替えされる |
| 楽観的追加 | `<form ... data-herb-into="messages">` | POST応答を待たず行を追加し、応答で実キーと差し替え |

JavaScriptはゼロ（`import "reactionview"` のクライアントランタイムのみ）。ReactもStimulusコントローラも自作なし。

## セットアップと起動

```bash
bundle install
bin/rails db:setup            # migrate + seed
bin/rails server              # http://localhost:3000/messages
```

ReActionView の設定は `config/initializers/reactionview.rb`
（`intercept_erb = true` ですべての `.html.erb` を `Herb::Engine` で処理、`slots = true` でリアクティブテンプレート有効）。

## 検証済みの動き（curlでも再現可能）

1. `GET /messages` → 200（通常のERBのようにレンダリング）
2. `GET /messages?format=slots` + `Accept: application/vnd.herb.slots+json` + `Herb-State: {"app/views/messages/index.html.erb":{"order":"newest"}}`
   → `content-type: application/vnd.herb.slots+json`、`Cache-Control: no-store`、
   ソート分岐と鍵付き行の並び（`order: ["12","11","10","9"]` のように実ID順）がJSONで返る
3. `POST /messages?format=slots`（`message[body]=…` + CSRF + セッションCookie）
   → **201**。新規行だけが鍵（実ID）付きの要素としてスロットに載って返る —
   楽観的追加の裏側（クライアントが仮の行を実キーへ差し替える）

`bin/rails test` に上記契約の統合テスト（`test/controllers/messages_controller_test.rb`）があります。

---

This README would normally document whatever specifications you consider necessary (Rails 8.1.4 / Ruby 4.0.7 / sqlite3 / importmap-rails + propshaft / Puma / Turbo + Stimulus).
