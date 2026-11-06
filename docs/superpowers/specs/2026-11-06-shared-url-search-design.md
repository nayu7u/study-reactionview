# 共有 URL の検索（`/catalog`）設計

- 日付: 2026-11-06
- 状態: 設計案（承認待ち）
- 対象: `/catalog`（ナビ外）
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

## 目的

検索・カテゴリ・ページを URL に載せ、ブックマーク・共有・戻る・進む・リロードが成立する検索画面を作る。検索とページ送りは標準の GET フォームとリンクに任せ、同じページの「概要を閉じる」だけを client mode の state（0往復）にする。URL 状態は Rails、ページ内の一時状態は ReactionView、という分担を実測で固定する。

## なぜこの画面か

既存7画面と `/forms` は、画面内の状態変化を slots で扱うことを示してきた。一方、実アプリが必ず要求する **URL に残る状態**（検索条件・ページ・共有リンク・戻る）は一度も通していない。

ReActionView の state はクライアント所有で、slots 応答は JSON の値であり、URL を書き換える手段は 0.6.0 にない。したがって URL 状態は標準の GET ナビゲーションに置くのが素直で、ページ内の一時的な表示だけを client mode にすると、両者が干渉しない。この分担を1画面で示す。

成功条件は次の4つ。

- `?q=...&category=...&page=...` が検索・絞り込み・ページ送りを再現し、共有・リロードで同じ結果になる。
- 戻る・進むで URL と一覧が戻る。
- 検索・ページ送りは document GET で、slots リクエストを出さない。
- 「概要を閉じる」は 0 slots で、URL を変えない。no-JS では概要が最初から見える。

## 画面

- ナビ外の `/catalog`。グローバルナビは7リンクのまま。Patterns の footer、README、docs からリンクする。
- 見出し「Talk Catalog」＋「共有 URL の検索 — 検索は Rails、ページ内は ReactionView」バッジ。
- 検索フォーム: キーワード `q`（タイトル・発表者）、カテゴリ select、検索ボタン。標準の GET。
- 共有 URL の行: `共有 URL: <code><%= request.fullpath %></code>`。リクエストの実 URL をそのまま見せる。
- 結果メタ: `12 件中 1–5 件 / 3 ページ`。
- 一覧: タイトル、発表者、カテゴリ、概要。概要はクライアントの `compact` state で閉じられる。既定は開いた状態。
- ページ送り: 前へ / ページ番号 / 次へ。`q` と `category` を保ったリンク。
- 条件クリア: `/catalog` へのリンク。
- `/forms` へのリンク（プロポーザルを送る）を一箇所置く。`/forms` 側は変更しない（撮影済みメディアを stale にしないため）。

## データ

`Talk` モデルを追加する。カタログは読み取り専用で、投稿・編集・削除は持たない。

- `title:string` / `speaker:string` / `category:string` / `abstract:text` / timestamps。
- `Talk::CATEGORIES = %w[rails frontend infra]`、`Talk::CATEGORY_LABELS`。
- `validates :title, :speaker, :abstract, presence: true`、`validates :category, inclusion: { in: CATEGORIES }`。
- seed は12件（rails 6 / frontend 3 / infra 3）。1ページ5件なので、全体は3ページ、rails カテゴリは2ページになる。カテゴリ絞り込みとページ送りの組み合わせを実データで試せるようにするための配分。
- `Proposal`（`/forms` の投稿）とは別モデルにする。`/forms` のシード・メディアを変えずに、カタログ用の読み取りデータを用意するため。

## 検索と URL

- パラメータは `q`、`category`、`page`。
- `q` はタイトルと発表者の部分一致。`%` / `_` / `\` はエスケープし、`ESCAPE` をバインドで渡す（`/` の検索と同じ形）。
- `q` は前後の空白を落として検索する。空でもリダイレクトしない。
- `category` は `all` / `rails` / `frontend` / `infra`。未指定・空・`all` は `all` として受理し、リダイレクトしない。それ以外の不明な値は `all` として検索したうえで、`category` を落とした正規 URL へ 302 で寄せる。
- `page` は 1 始まり。未指定・空は 1、`page=1` も有効（リダイレクトしない）。整数でない値、1未満、ページ数超過は、先頭/末尾のページへ clamp した正規 URL へ 302 で寄せる。0 件でも 1 ページとして扱う。
- 既定値（`category=all`、`page=1`）はリダイレクトしない。検索フォームが `category=all` を送っても 302 しない。ページリンクは既定値を落とす。
- 同じパラメータが複数ある場合は Rails の最後の値に従い、特別な扱いをしない。
- 並びは `title` 昇順。1ページ5件。
- 検索フォームは `form_with url: catalog_path, method: :get`。`data-herb-into` も `data-herb-set` も付けない。検索は document GET で全画面を返す。
- ページリンクと条件クリアは `catalog_path`。`q` が空、`category` が `all`、`page` が 1 のときは、リンクからそのパラメータを落としてきれいな URL にする。

## ページ内 state

- ビューは `herb:slots client`、状態は `compact: false` の1つ。
- 「概要を閉じる」はチェックボックス（`checked="<%= compact %>"`）。既存の `.task-check` の見た目を使う。
- 各概要は `hidden="<%= compact %>"` の presence で閉じる。分岐は使わない。
- 状態はクライアント所有で、検索・ページ送りではサーバーに送らない。チェックの切替は 0 slots、URL も変えない。
- 検索・ページ送りは全画面ナビゲーションなので、`compact` は既定の「開いた」に戻る。これは仕様として docs に書く。
- no-JS ではチェックボックスは動かないが、`compact: false` の初期 HTML で概要は最初から見える。

## ルートとコントローラ

```ruby
get "/catalog", to: "catalog#index", as: :catalog
```

- `CatalogController#index` が `@query` / `@category` / `@page` / `@total` / `@pages` / `@talks` を作る。
- `PER_PAGE = 5`。
- 検索 scope は `Talk.order(:title)` に `q` の LIKE と `category` の where を重ねる。
- `@pages` は `[(@total.to_f / PER_PAGE).ceil, 1].max`。`@page` は 1..`@pages` に clamp。
- 不明な `category`、範囲外の `page` は、正規の URL（`q` / `category` / `page` のうち既定値でないものだけ）へ `redirect_to` する。
- ビューのページリンク用に、`catalog_params(page:)` を `ApplicationHelper` に置く（`q` / `category` は現在値、`page` は既定値 1 を落とす）。
- `request.fullpath` を共有 URL の行に出す。HTML エスケープは ERB に任せる。

## レイアウトと CSS

- 1カラム。`.catalog-search`（フォーム）、`.share-url`（URL 行）、`.catalog-list`（行）、`.pagination`。
- 既存の `.hero` / `.feature` / `.field` / `.select` / `.btn` / `.task-check` を再利用。
- 追加: `.catalog-row` / `.catalog-meta` / `.catalog-abstract` / `.pagination` / `.pagination a[aria-current="page"]`。
- 色とフォントは既存トークン。Tailwind などは入れない。

## テスト

- `test/models/talk_test.rb`: 有効な fixture、必須、カテゴリ外。
- `test/controllers/catalog_controller_test.rb`:
  - 既定の GET が検索フォーム（GET）、共有 URL 行、5件、3ページ、`compact` のチェックボックス、概要の `hidden` presence を出す。
  - `?q=...` がタイトル/発表者で絞り込み、フォーム値と共有 URL 行に反映される。ページリンクが `q` を保つ。
  - `?category=rails` がカテゴリで絞り込み、select が選択される。
  - `?page=2` が2ページ目を出し、1ページ目のタイトルを含まない。前へ/次へが正しい。
  - `?category=rails&page=2` が rails の2ページ目を出す（seed 6件、1ページ5件）。
  - `?q=...&category=...&page=...` の組み合わせ。
  - `page=abc` / `page=0` / `page=999` と `category=unknown` が正規 URL へ 302。`page=1` と `category=all` は 302 しない。
  - 0 件のとき「該当なし」を出し、ページは1のまま。
  - マニフェストに `compact` が宣言され、概要に `hidden` の presence がある。`form[data-herb-into]` は0。
  - no-JS: 検索フォームが GET、概要が初期 HTML で見える。
- 既存のテストが通る。`bin/ci` green。

## ブラウザ実測（`/tmp/opencode/capture/catalog-probe.js`）

- 初期表示: slots 0、共有 URL 行 `/catalog`、5件、3ページ。
- 「概要を閉じる」: slots 0、URL 不変、概要が隠れる。もう一度で戻る。
- 検索: キーワードを入れて送信 → document GET、`?q=...`、一覧が絞り込まれ、共有 URL 行が同じ URL を指す。slots 0。
- カテゴリ: select を変えて送信 → `?q=...&category=...`、一覧が絞り込まれる。slots 0。
- ページ: 次へ → `?page=2`、一覧が2ページ目、前へで戻る。`?category=rails&page=2` も確認する。slots 0。
- 戻る/進む: ブラウザの back / forward で URL と一覧が戻る。共有 URL 行も戻る。
- リロード/共有: 現在の URL を新しいページで開き、同じ一覧・フォーム値・共有 URL 行になる。slots 0。
- 概要の開閉は検索・ページ送り後に既定へ戻る。

## メディア

- `docs/media/catalog-light.png` / `catalog-dark.png`（fullPage @2x）。
- `docs/media/20-catalog.gif`: 初期（全体）→ カテゴリ Rails（`?category=rails`、2ページ）→ 概要を閉じる（URL 不変、0往復）→ 次ページ（`?category=rails&page=2`）→ 戻る（`?category=rails`）、5フレーム。検索 `q` はプローブで別途確認する。
- 撮影は既存の capture と同じくヘッドレス Chromium。日本語フォントを CDP で確認し、固定 clip の全フレーム寸法一致を assert する。URL バーは写らないため、ページ内の共有 URL 行を証拠にする。

## ドキュメント

- `docs/url-state.md`（新規）: 実務検証の本編。URL 状態は Rails、ページ内は ReactionView という分担、GET フォーム/リンク、slots を使わない理由、`compact` の 0 往復、戻る/共有/リロードの実測、制約（全画面リロード、`compact` のリセット、no-JS）。
- `README.md`: 「実務検証: 共有 URL の検索（`/catalog`、ナビ外）」を `/forms` の次に追加。stills/GIF、テスト一覧。
- `docs/hotwire-comparison.md`: 「6つの局面」を「7つ」にし、対比7「共有 URL とページ内状態」を追加。URL はナビゲーション、slots はページ内、という分担を書く。
- `docs/hotwire-comparison.html`: 見出しの数と対比7の要約を同期。
- `AGENTS.md`: Catalog 画面の実測節（URL パラメータ、GET、0 slots、`compact`、戻る/共有、canonical redirect、メディア）。
- Patterns の footer に `/catalog` のリンクを1行追加する。stills は footer より上で切れているため再撮影しない。

## 非ゴール

- slots で検索すること、URL 同期のカスタム JS、`pushState` / `popstate` のアダプタ。
- `compact` を URL に載せること（ページ内の一時状態に留める）。
- カタログの投稿・編集・削除、認証、i18n、全文検索、複数ソート。
- グローバルナビへの追加、`/forms` の変更、`/forms` メディアの再撮影。
- 検索のインクリメンタル表示（入力中に結果が変わる）やオートコンプリート。

## 検討した案

1. **GET 検索 + in-page slots（採用）**: URL は Rails のナビゲーション、ページ内の一時状態は ReactionView。カスタム JS なし、no-JS も保てる。
2. **slots + URL 同期スクリプト**: `herb:state-change` と `popstate` で URL を同期する。リアクティブ検索は可能だが、アプリに約30行の JS が入り、「カスタム JS なし」の主張が限定される。入力のデバウンスと URL、リクエストの順序も自前で揃える必要がある。
3. **GET 検索のみ**: URL は確実だが、ページに ReactionView の要素がなく、検証として薄い。
4. **`Proposal` を再利用して seed を増やす**: `/forms` の一覧・メディアが変わる。カタログ用の読み取りデータを別モデルにする方が影響が小さい。
5. **ナビに8リンク目として追加**: 8リンクの調整と既存メディアの再撮影が波及する。ナビ外にする。
6. **`compact` を URL に載せる**: 表示の好みを URL に混ぜると、共有 URL が閲覧者の好みを含む。ページ内の一時状態に留める。

## リスクと確認事項

- `hidden="<%= compact %>"` の presence が client mode でコンパイルされ、チェックボックスの `checked` と両立するか。Settings の switch と同じ形なので動く見込み。ブラウザプローブで 0 slots と表示切替を確認する。
- 検索フォームの GET が `q=&category=all` のような既定値も URL に載せる。共有 URL 行は実 URL を見せ、ページリンクは既定値を落とす。両者の違いを docs に書く。
- `page` / `category` の canonical redirect が 302 を返し、戻る履歴を増やさないか。不正な URL のときだけなので許容する。
- 戻る/進むで bfcache が使われた場合、共有 URL 行はキャッシュされた HTML のままになる。URL と一致するので問題ないが、プローブで確認する。
- メディアの clip は検索フォーム・URL 行・一覧・ページ送りが入る高さにする。概要を閉じると一覧が短くなるが、clip は固定し、フレーム寸法を揃える。
- 12件の seed が `/forms` の一覧に影響しないこと（別モデル）。
- seed の配分（rails 6 / frontend 3 / infra 3）は、カテゴリ+ページ送りを実データで示すための裁定。4/4/4 にするとカテゴリ絞り込みは常に1ページになる。
- 既定値（`category=all` / `page=1`）をリダイレクトしないのは、検索フォームの自然な送信で 302 を挟まないため。不明値・範囲外だけを正規化する。

## 受け入れ条件

- `/catalog` はナビ外で、Patterns footer と README/docs から辿れる。
- `?q` / `?category` / `?page` が検索・絞り込み・ページ送りを再現し、共有・リロードで同じ結果になる。`?category=rails&page=2` も再現する。
- 戻る/進むで URL と一覧が戻る。
- 検索・ページ送りは document GET で slots 0。「概要を閉じる」も 0 slots で、URL を変えない。
- no-JS でも検索・ページ送り・概要の閲覧ができる。
- `bin/rails test` と `bin/ci` が green。
- `docs/url-state.md`、README、hotwire-comparison（md / html）、AGENTS.md が更新され、stills と GIF が追加されている。
- `/forms` のデータ・メディア・挙動は変えない。
