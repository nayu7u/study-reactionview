# 入れ子スレッド（`/thread`）設計

- 日付: 2026-11-06
- 状態: 設計案（一括指示により承認扱い）
- 対象: `/thread`（ナビ外）
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

## 目的

投稿と返信を **入れ子のキー付きコレクション** として描き、返信の追加と slots の `$refresh` で、キー付き差分が入れ子でどこまで保たれるかを測る。返信の追加は標準の HTML フォーム（全画面）で行い、`$refresh` の slots 応答に nested collection がどう載るかを記録する。入れ子の楽観的追加（outbox）が可能かはスパイクで確かめ、結果を docs に残す。

## 画面

- `/thread`「Thread」。
- 投稿ごとにタイトル、返信の入れ子リスト、返信数、返信フォーム。
- 上部に「最新を取得」`data-herb-action="$refresh"`。
- 返信フォームは標準 POST。成功は `/thread` へ redirect + flash。
- 返信の追加後、`$refresh` で slots 応答を取得し、nested collection の差分がどう適用されるかを見る。
- no-JS: 返信フォームと redirect だけで動く。

## データ

- `Post`（`title:string`）: `has_many :replies, dependent: :destroy`、title presence。
- `Reply`（`post_id:references`, `body:text`）: `belongs_to :post`、body presence。
- seed: 3投稿、各2〜3返信。
- fixture: 2投稿、各2返信。

## ルートとコントローラ

```ruby
get "/thread", to: "posts#index", as: :thread
post "/thread/posts/:post_id/replies", to: "replies#create", as: :post_replies
```

- `PostsController#index`: `@posts = Post.includes(:replies).order(:created_at)`。
- `RepliesController#create`: `Post.find`、`Reply.create!`、`redirect_to thread_path, notice: "返信しました"`。
- 返信は slots ではなく標準 HTML。全画面で nested keys を再描画する。

## ビューと入れ子キー

```erb
<%# herb:slots server %>
<button data-herb-action="$refresh">最新を取得</button>

<% @posts.each do |post| %>
  <%# herb:key post.id %>
  <article class="thread-post">
    <h2><%= post.title %></h2>
    <ul class="thread-replies" data-herb-name="replies">
      <% post.replies.each do |reply| %>
        <%# herb:key reply.id %>
        <li class="thread-reply"><%= reply.body %></li>
      <% end %>
    </ul>
    <p class="thread-count"><%= post.replies.size %> 件の返信</p>
    <%= form_with model: [ post, Reply.new ], url: post_replies_path(post), method: :post do |form| %>
      ... body ...
      <%= form.submit "返信する", class: "btn btn-primary" %>
    <% end %>
  </article>
<% end %>
```

- 外側の `herb:key post.id` と内側の `herb:key reply.id`。
- `$refresh` の slots 応答に、外側の collection items の中へ nested collection がどう載るか（items/order/statics）を実測する。
- クライアントが外側の行を再構築せず、内側の返信だけを差分適用できるかを見る。できない場合は境界として記録する。
- `data-herb-name="replies"` は各投稿で重複する。nested collection の名前解決がどこまで効くかも記録する。
- 返信数は `post.replies.size` のサーバー読み。fold は使わない（nested collection の count は未検証のため）。

## 入れ子の楽観的追加（スパイク）

- 返信フォームに `data-herb-into="replies"` を付けると、outbox が nested collection を見つけられるか。
- 見つからない/誤った投稿に splice される場合は、標準フォームに戻し、境界として docs に書く。
- 本実装は標準フォームを採用し、スパイクの結果だけを docs に残す（`data-herb-into` は付けない）。

## テスト

- `test/models/post_test.rb` / `reply_test.rb`: presence、関連、dependent destroy。
- `test/controllers/posts_controller_test.rb`: `/thread` が投稿と入れ子の返信、返信数、フォームを出す。
- `test/controllers/replies_controller_test.rb`: 返信の作成、redirect + flash、no-JS。
- slots 応答: `GET /thread?format=slots` が nested collection を含むか、payload の形を記録する。
- `bin/ci` green。

## ブラウザ実測（`/tmp/opencode/capture/thread-probe.js`）

- `/thread` の初期表示。返信フォームで追加 → redirect → 返信が増える。
- `$refresh` → slots 応答 1回。外側の投稿が再構築されず、内側の返信だけが差分適用されるか。
- no-JS の返信追加。
- slots 応答の nested の形、DOM の変化、リクエスト数を記録する。

## メディア

- `docs/media/thread-light.png` / `thread-dark.png`（fullPage @2x）。
- `docs/media/24-thread.gif`: 返信追加 → 最新を取得 → 入れ子の差分、4〜5フレーム。固定クリップ・日本語フォント・フレーム寸法一致。
- 既存メディアは変えない。

## ドキュメント

- `docs/thread.md`（新規）: nested keys、slots 応答の形、差分適用の可否、`$refresh`、標準返信フォーム、スパイクの結果、制約。
- README: 「実務検証: 入れ子スレッド（`/thread`、ナビ外）」。
- hotwire-comparison: 対比10「入れ子コレクションのキー付き差分」を追加（9→10）。
- AGENTS.md: Thread 節（nested keys、slots の wire、差分の可否、`$refresh`、返信、メディア）。
- Patterns footer に `/thread` のリンク。

## 非ゴール

- リアルタイム更新、WebSocket、通知、認証、i18n。
- 返信の編集・削除、ページネーション、無限スクロール。
- nested の楽観的追加を本実装にすること（スパイクの結果次第。標準フォームを採用）。
- `$refresh` 以外の slots 更新。

## 検討した案

1. **標準返信フォーム + `$refresh`（採用）**: 返信は確実に追加でき、nested の slots 応答と差分を測れる。
2. **nested outbox**: 返信を楽観的に追加する。outbox の collection 名解決が nested で効くか未検証で、失敗すると誤投稿に splice する危険がある。スパイクで確認する。
3. **全画面のみ**: 返信は追加できるが、slots の nested 差分を測れない。
4. **返信をフラットな collection に**: 入れ子の主題から外れる。

## リスク

- nested `herb:key` がコンパイルできるか。外側/内側のキーが wire に載るか。
- `$refresh` の slots 応答で nested collection が items/order/statics のどの形で載るか。
- クライアントが nested の差分を適用できるか。できない場合は境界として docs に残す。
- `data-herb-name="replies"` の重複が名前解決を壊さないか。
- 返信フォームの `form_with model: [post, Reply.new]` の URL/params。
- 返信数の `post.replies.size` が N+1 にならないか（`includes`）。
- メディアの固定クリップと高さ。

## 受け入れ条件

- `/thread` が投稿と入れ子の返信をキー付きで描く。
- 返信フォームで追加でき、redirect + flash、no-JS でも動く。
- `$refresh` の slots 応答の nested の形と、差分適用の可否が docs に記録されている。
- nested の楽観的追加のスパイク結果（可/不可）が docs に記録されている。
- `bin/rails test` と `bin/ci` が green。
- `docs/thread.md`、README、hotwire-comparison（md / html）、AGENTS.md、stills / `24-thread.gif` が更新されている。
- 既存画面のデータ・メディア・挙動は変えない。
