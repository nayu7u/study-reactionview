# ピン／スター（行とサマリーの同時連動）設計

- 日付: 2026-10-28
- 状態: 承認済み（2026-10-28）
- 対象: Sprint Hub（`/`）のタスク行
- 前提: ReActionView 0.6.0 / herb 0.11.1

この設計は A（ピン／スター）だけを扱う。D の Turbo 比較は今回やらない。HTML twin の同期は最後（E）にまとめる。

## 目的

タスク行の星を押すと、星の見た目と「N件ピン留め」が同時に変わる。サーバーには問い合わせず、**0往復**で揃える。Hotwire なら2箇所の DOM 同期（Stimulus）か Stream 往復になる場面を、1つの行内 state とカウントfoldで済ませる。

## なぜ Hub か

Hub はすでに per-row の `done` state と `done_count` のカウントfoldを持つ。同じ形で `pinned` / `pinned_count` を足せる。Patterns の行はサーバー読みの選択ボタンで、星を足すとモードが混ざる。新画面 `/pins` は fold + presence 1組で薄い。

## 仕様

- 各タスク行の `herb:state` に `pinned: false` を追加する（既存の `done` と同じ行スコープ）。
- 行の星は、チェックボックスを presence バインディングにしたラベルで作る。

```erb
<label class="task-pin">
  <input type="checkbox" aria-label="ピン留め" checked="<%= pinned %>">
  <span class="pin-glyph" aria-hidden="true">★</span>
</label>
```

- 星の塗りと行の強調は CSS で行う。既存の done 用 `:has(input:checked)` は、ピンのチェックボックスにも当たらないよう `.task-check input:checked` にスコープする。

```css
.task-list li:has(.task-check input:checked) { /* 既存の done の見た目 */ }
.task-list li:has(.task-pin input:checked) { /* ピンの行強調 */ }
.task-list li:has(.task-pin input:checked) .pin-glyph { /* 星を塗る */ }
```

- トップの state に `pinned_count: 0` を追加する。行内で次の3タグ形を置く。

```erb
<% if pinned %><% pinned_count += 1 %><% end %>
```

- カウントの読みはループの後。既存の `task-stat` の隣に「N件ピン留め」を置く。**ヘッダではなくリスト直後のサマリー**にする。カウントfoldをループ前で読むとコンパイルエラーになるため、DOM の読み順を守る。
- 星はブラウザ所有。リロードで消える。永続化しない。
- done のチェックとピンは独立させる。done を変えても pinned_count は動かず、ピンを変えても done_count は動かない。

## 非ゴール

- ピンの永続化、サーバー側の絞り込み、ピン順ソート、API。
- 新しい画面。
- no-JS のピン操作。JavaScript が無いとチェックボックスの見た目は変わっても count は動かない。

## 代替案

1. **新画面 `/pins`**: fold + presence の組合せ1つ分で薄い。既存画面の追加機能に向く。
2. **Patterns の行に星**: 行がサーバー読みの選択ボタンで、クライアント所有の星とモードが混ざる。
3. **ヘッダに count**: カウントfoldをループ前で読むことになりコンパイルエラー。CSS `order` で見た目だけ上に置く手もあるが、読み順と支援技術の順序がずれるので採らない。

→ **Hub の行 + リスト直後のサマリー**を採用する。

## テスト

- `tasks_controller_test`:
  - 初期 HTML に `.task-pin input[type="checkbox"]` がタスク数ぶんある。
  - サマリーに「0 件ピン留め」がある。
  - manifest に `pinned` と `pinned_count` が宣言され、count が `when: ["pinned"]` / `by: 1` で現れる。
  - 既存の `done` / `done_count` のテストが通る。
- ブラウザプローブ（`/tmp/opencode/capture`）:
  - 星を2つ押す -> `?format=slots` リクエスト **0**、サマリーが「2 件ピン留め」、星が塗られる。
  - done のチェックで `done_count` だけが動き、`pinned_count` は動かない。
  - リロードでピンが消える（永続化しないことの確認）。

## ドキュメントとメディア

- README の Sprint Hub に `### 機能⑯ 行とサマリーの同時連動（ピン／星）` と GIF `docs/media/16-pin.gif` を追加。
- Hub の light/dark 静止画は星が入るので撮り直す。撮影は `app.css` の日本語フォントスタック
  （`Hiragino Sans` / `Noto Sans CJK JP` / `Meiryo` / `Yu Gothic`）で行い、Pricing の媒体と同じ条件にする。
  Linux の `system-ui` 経由で中国語（SC）字形に落ちないよう、フォントファミリをキャプチャ側で
  system-ui に戻さない。
- `docs/hotwire-comparison.md` の §⑦ からピン候補を外す。
- `AGENTS.md` に、counted state のサマリーはリスト直後、done と pin の `:has` スコープ、0往復の実測を追記。
- `docs/hotwire-comparison.html` のスタイル版は E でまとめて同期する。

## 受け入れ条件

- 星とサマリーが 0 slots リクエストで同時に変わる。
- done と pin が干渉しない。
- 統合テストと `bin/ci` が green。
- README の Hub 節に GIF、Hub の静止画が更新されている。
