# Triage — 一括選択と一括更新（`/triage`、ナビ外）

行を複数選び、優先度をまとめて更新する画面。選択はブラウザ内の per-item state、更新は標準の `PATCH /triage` フォームに分けた。Hotwire なら Stimulus で選択集合と件数を持ち、送信は form で行う部分を、ReActionView では presence とカウントfoldで置き換えている。

## 何を確かめるか

- 行ごとの `selected` state が独立し、チェックのたびに slots リクエストが飛ばないこと。
- `selected_count` のカウントfoldが、選択した行数に追随すること。
- 一括更新が標準フォームの1ドキュメントリクエストで動き、選択した ID だけが更新されること。
- no-JS でもチェックと更新が動くこと。
- グローバルな「全選択」が per-item state のスコープ制約で書けないこと。

## 実装の形

```erb
<%# herb:slots client %>
<%# herb:state (selected_count: 0) %>

<% @tasks.each do |task| %>
  <%# herb:key task.id %>
  <%# herb:state (selected: false) %>
  <% if selected %><% selected_count += 1 %><% end %>
  <input type="checkbox" name="ids[]" value="<%= task.id %>" checked="<%= selected %>">
<% end %>

<p><%= selected_count %> 件を選択中</p>
```

- `selected` は行の state。`checked="<%= selected %>"` は presence バインディング。
- `selected_count` はリストの後に読む。ループ前で読むと「count is not complete」になる（Hub と同じ制約）。
- 更新は `form_with url: triage_path, method: :patch`。チェックボックスは native の `ids[]` として送る。
- コントローラーは `Task.where(id: ids).update_all(priority:, updated_at:)` で選択行だけを更新する。

## 実測（2026-11-18 / 0.6.1 / herb 0.11.2）

`bin/verify-reactionview run --feature triage-bulk` で確認した。

| 操作 | slots リクエスト | ドキュメントリクエスト | 結果 |
|---|---:|---:|---|
| 2行をチェック | 0 | 0 | カウントが `2` に、行がハイライト |
| 優先度「低」を選んで更新 | 0 | 1（PATCH → redirect） | flash「2件の優先度を更新しました」、2行のバッジが「低」 |
| 未選択の行 | 0 | 0 | 優先度は変わらない |

- 選択は **0 slots**。チェックは presence と CSS `:has(input:checked)` で完結する。
- 一括更新は **0 slots / 1 document**。slots の POST ではなく、通常のフォーム送信でリダイレクトする。
- no-JS でもチェックと更新は動く。選択数の表示だけは初期値 `0` のまま（クライアント計算のため）。
- 全選択はできない。`selected` は行の state で、ループの外のボタンから全インスタンスへ書き込む手段がない。行ごとのチェックに留めた。
- `Task.priority` を直接更新する。dev で試した後は `bin/rails db:seed` で seed の優先度に戻せる。テストは fixture の3行だけを使う。

## テスト

```console
$ bin/rails test test/controllers/triage_controller_test.rb
$ bin/verify-reactionview run --feature triage-bulk
```

コントローラーテストは、選択行だけの更新、未選択時の alert、範囲外の優先度、非数値の優先度を固定する。ブラウザ検証は選択0往復と標準フォームの1ドキュメントを測る。

## メディア

- `docs/media/triage-light.png` / `triage-dark.png` — 初期表示。
- `docs/media/33-triage.gif` — 2行選択 → 優先度「低」 → 更新 → flash とバッジ更新。

## Why not a slots POST

選択は native checkbox のままにし、実行は標準フォームにした。理由は3つある。

1. no-JS でも同じ経路で動く。チェックと送信はブラウザ標準のまま。
2. bulk 専用の outbox や `data-herb-into` のコレクションを増やさずに済む。
3. 選択数と見た目はクライアント、データ更新はサーバーという境界が明確になる。

全選択を足すなら、行 state とは別にグローバルな選択集合を設計する必要がある。0.6.1 の scalar state では配列を持てないため、この画面ではやらない。
