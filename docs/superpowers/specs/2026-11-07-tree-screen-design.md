# 深いツリー（`/tree`）設計

- 日付: 2026-11-07
- 状態: 設計案（承認済み）
- 対象: `/tree`（ナビ外）
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

> **実装時の裁定（2026-11-07）**: 再帰 partial の `open` は成立しなかった。partial の `herb:state` は全インスタンスで共有され、per-item state を partial に渡すと `ActionView::SyntaxErrorInTemplate`、同名 state はテンプレートをまたいで衝突する。設計の案5（レベル別テンプレート + `open_root` / `open_l2` / `open_l3`）を採用した。実測は `docs/tree.md` と `AGENTS.md`。

## 目的

3階層以上のファイルツリーを描き、**深さ2以上の入れ子で、ノードごとの開閉 state がどこまで独立に動くか**を測る。Thread は深さ1の入れ子、UI Kit の Accordion は1階層の per-item state までしか測っていない。Tree は、再帰 partial の中の `herb:state` と `hidden` presence が深い入れ子でも成立するか、`$refresh` の前後で開閉状態が保たれるかを見る。

## 何を確かめるか

- 再帰 partial の中の `herb:state (open: true)` が、ノードごとに独立した state としてコンパイルされるか。
- `hidden="<%= !open %>"` の presence が、深さ2以上の各ノードで正しく効くか。
- フォルダの開閉が **0 slots リクエスト**で動くか。
- `$refresh` の slots 応答で、深い入れ子のキー付き差分が適用されるか。開閉状態が生存するか。
- no-JS で初期 HTML が読めるか（全フォルダを開いた状態で出す）。

## 画面

- `/tree`「Tree」。ナビ外。Patterns の footer、README、docs からリンクする。
- 上部: 見出し、説明、`N nodes / M folders`、`最終取得 HH:MM:SS`、`最新を取得` ボタン。
- 本体: ファイルツリー。フォルダは開閉ボタン、ファイルは行のみ。
- 初期状態は全フォルダ open。no-JS でも全ノードが読める。GIF は「深いフォルダを閉じる → 開く」を見せる。
- 下部に、この画面で測ることを短く書く。server mode との対比ではなく、client mode の深さの検証であることを示す。

```
▾ app/
  ▾ views/
    ▾ trees/
      index.html.erb
      _folder.html.erb
      _file.html.erb
    ▸ tasks/
  ▾ models/
    tree_node.rb
    task.rb
▾ config/
  routes.rb
```

## データ

- `TreeNode`（`tree_nodes`）:
  - `name:string`（null: false）
  - `kind:string`（null: false、`folder` / `file`）
  - `parent_id:integer`（nullable、自己参照）
  - `position:integer`（null: false、default 0）
- 関連:
  - `belongs_to :parent, class_name: "TreeNode", optional: true, inverse_of: :children`
  - `has_many :children, -> { ordered }, class_name: "TreeNode", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent`
- validation: `name` の presence、`kind` の inclusion。
- `scope :ordered, -> { order(:position, :id) }`。
- seed: 4階層（`app/views/trees/index.html.erb` まで）を含む15〜20ノード。`TreeNode.destroy_all` してから作る。
- fixture: 10ノード、4階層。レベルは root を1として数える。レベル3のフォルダとレベル4のファイルを含める。`tree_nodes(:app)` などをラベルで参照する。

**Why DB-backed**: 実アプリ風のショーケースであり、ツリーの初期描画をサーバー読みにしたいから。静的な配列だとモデル・seed・fixture の検証が消え、画面だけの玩具になる。

## ルートとコントローラ

```ruby
get "/tree", to: "trees#index", as: :tree
```

- `TreesController#index`:
  ```ruby
  nodes = TreeNode.ordered.to_a
  @children_by_parent = nodes.group_by(&:parent_id)
  @roots = @children_by_parent[nil] || []
  @node_count = nodes.size
  @folder_count = nodes.count { |node| node.kind == "folder" }
  @loaded_at = Time.current
  ```
- `@children_by_parent` を partial に渡し、ノードごとの `children` 取得で N+1 を作らない。
- `@loaded_at` は `$refresh` の可視の証拠。ツリーの内容が変わらなくても、再取得したことが画面で分かる。

## ビューと state

`app/views/trees/index.html.erb`:

```erb
<%# herb:slots client %>

<section class="tree-page">
  <h1>Tree</h1>
  <p>深さ2以上の入れ子で、ノードごとの開閉が 0 往復で動くか。</p>
  <p><%= @node_count %> nodes / <%= @folder_count %> folders ・
     最終取得 <span data-herb-name="loaded_at"><%= @loaded_at.strftime("%H:%M:%S") %></span></p>
  <button class="btn btn-ghost" data-herb-action="$refresh">最新を取得</button>

  <ul class="tree-root">
    <% @roots.each do |root| %>
      <%# herb:key root.id %>
      <%# herb:state (open: true) %>
      <% if root.kind == "folder" %>
        <%= render "folder", node: root, open: open, children_by_parent: @children_by_parent %>
      <% else %>
        <%= render "file", node: root %>
      <% end %>
    <% end %>
  </ul>
</section>
```

`app/views/trees/_folder.html.erb`:

```erb
<% children = children_by_parent[node.id] || [] %>

<li class="tree-node tree-folder">
  <button class="tree-toggle" data-herb-toggle="open" aria-expanded="<%= open %>">
    <span class="tree-chevron" aria-hidden="true"></span>
    <span class="tree-icon" aria-hidden="true">📁</span>
    <span class="tree-name"><%= node.name %></span>
  </button>

  <ul class="tree-children" hidden="<%= !open %>">
    <% children.each do |child| %>
      <%# herb:key child.id %>
      <%# herb:state (open: true) %>
      <% if child.kind == "folder" %>
        <%= render "folder", node: child, open: open, children_by_parent: children_by_parent %>
      <% else %>
        <%= render "file", node: child %>
      <% end %>
    <% end %>
  </ul>
</li>
```

- `open` は **`herb:key` と同じループの中で宣言する**。Accordion の per-item state と同じ形で、partial の occurrence index に依存しない。親のループで宣言した state を `open:` として子 partial に渡す。
- 子のコレクションを `if children.any?` で包まない。分岐で包むと slots 応答が items/order ではなく branch statics になり、キー付き差分が壊れる（AGENTS.md の実測）。空のフォルダは空の `<ul>` を出し、CSS の `.tree-children:not(:has(> li)) { display: none; }` で見せない。ERB の空白テキストがあるため `:empty` は使えない。

`app/views/trees/_file.html.erb`:

```erb
<li class="tree-node tree-file">
  <span class="tree-row">
    <span class="tree-chevron tree-chevron-empty" aria-hidden="true"></span>
    <span class="tree-icon" aria-hidden="true">📄</span>
    <span class="tree-name"><%= node.name %></span>
  </span>
</li>
```

- 開閉は `open` の per-folder state。`data-herb-toggle="open"` で切り替え、`hidden="<%= !open %>"` の presence で子リストを出す。
- `aria-expanded="<%= open %>"` は "true"/"false" の文字列補間。client mode ではクライアント評価。
- `herb:key` は各ループの中で宣言する。再帰 partial の内側でも、キーは「その子を描くループ」に置く。
- フォルダとファイルの分岐は `child.kind` のサーバー側条件。kind は変わらないので、クライアントが分岐を切り替えることはない。`$refresh` で partial の分岐が materialize されて値が落ちる場合は、分岐を増やさずに境界として記録する（markup を二重にしない）。
- ファイル行には state を持たせない。子のループではファイルにも `open` state が付くが、ファイルの markup は読まない。

## `$refresh` の位置づけ

- `最新を取得` は `data-herb-action="$refresh"`。slots 応答1回で、`loaded_at` とツリーのキー付き差分が返る。
- 目的は、深い入れ子のキー付き差分と、**クライアント所有の `open` state が refresh 後も残るか**の実測。
- 状態が残らない場合は、その挙動を docs に記録し、画面の主要操作（開閉）は 0 往復のまま維持する。`$refresh` を必須の操作にはしない。

## no-JS

- 初期 `open: true` なので、`hidden` は付かず、全ノードが HTML で読める。
- 開閉ボタンは押しても何も起きない。`最新を取得` も動かない。
- no-JS の要件は「初期ツリーが読めること」に限定する。開閉のフォールバックは `<details>` を別途使う話であり、この画面の検証対象ではない。

## テスト

- `test/models/tree_node_test.rb`:
  - `name` / `kind` の validation。
  - `parent` / `children` の自己参照。
  - `dependent: :destroy` で子孫が消える。
  - `ordered` が `position` 順。
- `test/controllers/trees_controller_test.rb`:
  - `GET /tree` が 200。`h1` が "Tree"。
  - `.tree-node` の数が `TreeNode.count` と一致。
  - `.tree-folder` / `.tree-file` の数が一致。
  - `ul.tree-children ul.tree-children ul.tree-children` が出る（root を1としたレベル4まで）。
  - フォルダごとに `button[data-herb-toggle='open']` がある。
  - `button[data-herb-action='$refresh']` と `[data-herb-name='loaded_at']`。
  - 初期 HTML に `ul.tree-children[hidden]` がない（全開）。
  - `_folder` の manifest に `open` の declaration と `hidden` の presence がある。
  - `GET /tree?format=slots` が成功し、`loaded_at` とツリーの値を返す。nested の形は payload を parse して確認する。
  - `aria-expanded` は統合テストで assert しない。Wizard の `aria-current` と同じく、コレクション内の動的属性はテスト環境で slot 化されて落ちる（ブラウザでは動く）。`aria-expanded` の確認はブラウザプローブに置く。
- fixture は `test/fixtures/tree_nodes.yml` に明示データを置く。
- `bin/rails test` と `bin/ci` を green にする。

## ブラウザ実測（`/tmp/opencode/capture/tree-probe.js`）

- 初期表示: slots 0、全フォルダが開いている。
- レベル1のフォルダを閉じる: slots 0、子が隠れる、`aria-expanded="false"`。
- レベル2のフォルダを閉じる: slots 0、孫が隠れる。
- レベル3のフォルダを閉じる: slots 0、ひ孫が隠れる。
- 別のフォルダを開閉しても、他のフォルダの状態が変わらない（独立）。
- `最新を取得`: slots 1、`loaded_at` が変わる。開閉状態が残るかを記録する。
- リロード: 全開に戻る。
- no-JS: 全ノードが読める。開閉は動かない。
- manifest: `_folder` の declarations / presence を記録する。

## メディア

- `docs/media/tree-light.png` / `tree-dark.png`（fullPage @2x）。
- `docs/media/25-tree.gif`: 初期（全開）→ レベル1を閉じる → レベル2を閉じる → レベル3を閉じる → レベル2を開く → `最新を取得`。5〜6フレーム。
- 固定クリップは `.tree-page` の初期 box。全フレームの寸法一致を assert する。日本語フォントは `Noto Sans CJK JP` を CDP で確認する。
- 既存メディアは変えない。

## ドキュメント

- `docs/tree.md`（新規）: 目的、画面、再帰 partial と `herb:key`、per-node state、0 往復の実測、`$refresh` の結果、no-JS、制約。
- README: 「実務検証: 深いツリー（`/tree`、ナビ外）」を追加。
- `docs/hotwire-comparison.md` / `.html`: 証明マップに対比11「深い入れ子の per-node 状態」を追加。Hotwire 側は再帰 partial + Stimulus、ReActionView 側は再帰 partial + `herb:state` + `hidden` presence。
- AGENTS.md: Tree 節（深さ2+の state、再帰 partial、`$refresh` の結果、no-JS、メディア）。
- Patterns footer に `/tree` のリンク。

## 非ゴール

- ノードの追加・削除・並べ替え・選択・検索。
- 任意深度の保証。まずは seed の4階層で測る。
- ドラッグ＆ドロップ。
- `$refresh` 以外のサーバー更新。
- リアルタイム更新、WebSocket、認証、i18n。
- UI Kit への Tree コンポーネント抽出。深さ2+の挙動が確認できたら、別の変更として検討する。

## 検討した案

1. **client mode + 再帰 partial + per-node `open`（採用）**: 開閉は 0 往復。深さ2+の state と presence を測れる。`$refresh` を足せば深いキー付き差分も測れる。
2. **server mode + `$refresh` のみ**: 開閉のたびに往復するか、state を分岐に読ませる必要がある。`open` は presence なので steering に載らず、開閉のたびの往復は成立しない。client mode が自然。
3. **静的な入れ子配列**: DB とモデルを作らない。画面は速いが、実アプリ風のショーケースとして弱く、seed/fixture の検証も消える。
4. **ネイティブ `<details>`**: no-JS は完璧だが、ReActionView の state/presence を測れない。この画面の目的と違う。
5. **明示的なレベル別 partial（再帰なし）**: 再帰 partial の `herb:key` が不安定な場合のフォールバック。レベル1〜3のフォルダとレベル4のファイルを別 partial で描く。実装は増えるが、各ループとキーが同じテンプレートに載る。まず再帰で試し、失敗したらこちらに落とす。

## リスク

- 再帰 partial の内側で `herb:key` が正しくキーとして解釈されるか。ループとキーが同じテンプレートにあることを確認する。
- ループ内の `herb:state (open: true)` がレベル2以上でも per-item state として独立するか。Accordion は1階層で実測済み。
- `hidden="<%= !open %>"` がレベル2以上で効くか。
- `$refresh` 後に `open` 状態が残るか。残らない場合は境界として記録する。
- `child.kind` の分岐が `$refresh` で materialize され、サーバー読みが落ちないか。落ちる場合は分岐を増やさず、境界として記録する。
- seed/fixture の自己参照が正しく張れるか。
- メディアの固定クリップと高さ（全開だと縦に長い）。GIF はレベル3まで見える範囲に切る。

## 受け入れ条件

- `/tree` が DB のツリーを4階層（root をレベル1としてレベル4まで）で描く。
- フォルダの開閉がブラウザで 0 slots リクエスト、レベル1/2/3で独立して動く。**動く画面を納品する**。再帰 partial でキーか state が壊れる場合は、明示的なレベル別 partial に落として動かし、再帰 partial の境界を docs に記録する。フォールバックでも独立した開閉が成立しない場合は、初期ツリーが読める状態に留め、境界を docs に記録する（壊れたデモを完成扱いにしない）。
- `最新を取得` が slots 1回で `loaded_at` を更新する。開閉状態の生存可否が docs に記録されている。
- no-JS で初期ツリーが全開で読める。
- `bin/rails test` と `bin/ci` が green。
- `docs/tree.md`、README、hotwire-comparison（md / html）、AGENTS.md、Patterns footer、stills / `25-tree.gif` が更新されている。
- 既存画面のデータ・メディア・挙動は変えない。
