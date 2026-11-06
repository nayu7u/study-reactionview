# 入れ子スレッド（`/thread`） — キー付きコレクションの深さ

ReActionView 0.6.0 + herb 0.11.1 の検証アプリで、**投稿と返信を入れ子のキー付きコレクション**として描き、slots の `$refresh` で nested collection がどこまで保たれるかを測った記録です。画面は `/thread`（ナビ外）。返信は標準フォーム、`$refresh` は server mode の slots 要求です。

![返信を追加し、最新を取得しても外側の投稿は再構築されない](media/24-thread.gif)

## 何を確かめたか

外側のコレクション（投稿）の中に、内側のコレクション（返信）を `herb:key` で入れ子にしたとき、次の3点が未検証でした。

- 入れ子の `herb:key` がコンパイルされ、slots の wire に nested collection が載るか。
- クライアントが外側の行を再構築せず、内側の返信だけを差分適用できるか。
- 返信の楽観的追加（outbox）が入れ子でも成立するか。

## 結論

**表示と差分は成立します。** `$refresh` の slots 応答には、外側の collection item の中に nested collection が `items` / `order` / `statics` の形で載りました。クライアントは外側の投稿行を再構築せず（プローブで行に付けたマーカーが残った）、内側の返信を差分適用しました。

**入れ子の outbox は成立しません。** 返信フォームに `data-herb-into="replies"` を付けて送信しても、返信は追加されず、ページエラーも出ませんでした（静かな no-op）。本実装は標準の返信フォーム（全画面 + redirect + flash）を採用しています。

## 入れ子キーと wire

```erb
<% @posts.each do |post| %>
  <%# herb:key post.id %>
  <article class="thread-post">
    ...
    <ul class="thread-replies" data-herb-name="replies">
      <% post.replies.each do |reply| %>
        <%# herb:key reply.id %>
        <li class="thread-reply"><%= reply.body %></li>
      <% end %>
    </ul>
    ...
  </article>
<% end %>
```

`$refresh` の slots 応答（要約）:

```json
{
  "slots": {
    "0": {
      "items": {
        "1": {
          "1": "スロットの質問",
          "2": {
            "items": { "1": { "3": "キー付き差分は入れ子でも効きますか？" } },
            "order": ["1", "2", "5"],
            "statics": "...<li class=\"thread-reply\" data-herb-slot=\"3:child\"></li>..."
          }
        }
      },
      "order": ["1", "2", "3"]
    }
  }
}
```

- 外側の item のパートに、内側の collection が `items` / `order` / `statics` として入れ子で載る。
- 内側の `herb:key` は `items` のキーと `order` に反映される。
- クライアントは外側の item を再構築せず、内側の返信だけを差し替える。プローブでは `$refresh` の前後で外側の行に付けた `data-probe-preserved` が残った。
- 返信数のサーバー読み（`post.replies.size`）も同じ応答で更新される。

## 返信

```erb
<%= form_with model: [ post, Reply.new ], url: post_replies_path(post), method: :post, class: "thread-form" do |form| %>
  <%= form.text_field :body, class: "field" %>
  <%= form.submit "返信する", class: "btn btn-primary" %>
<% end %>
```

- 標準の POST。成功は `/thread` へ redirect + flash。
- no-JS でも同じ経路で返信できる。
- 返信の追加は全画面なので、入れ子のキーは初期 HTML として再描画される。差分の実測は `$refresh` で行う。

## 実測

ブラウザ実測は `/tmp/opencode/capture/thread-probe.js`（headless Chromium、リポジトリ外）。

| 操作 | slots | 結果 |
|---|---|---|
| 返信を追加 | 0（HTML） | redirect + flash、返信が増える |
| 最新を取得 | 1 | 外側の行は保持（`data-probe-preserved` が残る）、内側の返信が差分適用 |
| 入れ子 outbox（スパイク） | 1（500? なし） | 返信は追加されず、ページエラーもなし（静かな no-op） |
| no-JS の返信 | 0（HTML） | 返信が追加される |

プローブの要約は `reply: true`, `refreshSlots: 1`, `outerPreserved: "yes"`, `replyCount: 5`, `spikeRows: 0`, `spikePosts: 0`, `pageErrors: []`, `noJSReply: 1` です。nested の wire は `nestedPreview` に記録しています。

統合テストでは、投稿・入れ子の返信・返信数・返信フォーム・`$refresh`、slots 応答の nested、返信の redirect + flash + 件数、標準フォーム（`data-herb-into` なし）を固定しています。

## 制約

- 入れ子の楽観的追加（outbox）はできません。`data-herb-into="replies"` は静かな no-op でした。返信は標準フォーム + 全画面です。
- `$refresh` の slots 応答で nested の差分は効きますが、返信の追加自体は往復（document POST）です。
- `data-herb-name="replies"` は投稿ごとに重複します。今回の `$refresh` は nested の位置で解決されましたが、outbox の名前解決には使えませんでした。
- 返信数はサーバー読みで、fold ではありません。nested collection の count fold は未検証です。
- 返信の編集・削除、ページネーション、リアルタイム更新は対象外です。

## 使い分け

- 入れ子の表示と、サーバー読みの差分更新は slots で成立する。外側のキーを保ち、内側だけを差し替えられる。
- 入れ子の書き込みは標準フォーム + 全画面にする。outbox を入れ子に載せない。
- 単一コレクションの楽観的追加は `/outbox` の outbox、サーバー検証は `/forms` / `/apply`、URL は `/catalog`。

入れ子は「読む・差分で更新する」には向きますが、「楽観的に書き込む」には 0.6.0 では別の設計が要ります。この境界を、外側の行を壊さずに内側だけ更新できることとセットで記録しました。
