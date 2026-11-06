# 編集・削除（`/forms`）設計

- 日付: 2026-11-06
- 状態: 設計案（一括指示により承認扱い）
- 対象: `/forms` と `/forms/:id/edit` / `/forms/:id/delete`
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

## 目的

`/forms` の作成だけで止まっている CRUD を、編集（PATCH）と削除（DELETE）まで標準の HTML フォームで完成させる。更新の失敗は 422 の全画面再描画でエラーと入力値を保持し、削除は確認ページを挟んで標準の `button_to` で行う。カスタム JS は使わない。

## なぜ

`/forms` は「サーバー検証つきの作成」を実証したが、実務のフォームは編集と削除が要る。更新は PATCH でも 422 の経路が同じように成立するか、削除は no-JS の標準フォームで安全にできるか、一覧の操作から自然に辿れるかを見る。

## 画面とルート

```ruby
get "/forms/:id/edit", to: "proposals#edit", as: :edit_form
patch "/forms/:id", to: "proposals#update", as: :form
get "/forms/:id/delete", to: "proposals#confirm_destroy", as: :confirm_destroy_form
delete "/forms/:id", to: "proposals#destroy"
```

- 一覧の各カードに「編集」「削除」のリンクを置く。
- `edit` は作成と同じフォーム（共有パーシャル）で、送信先を `form_path(@proposal)`、method を `:patch`、ボタンを「更新する」にする。
- 更新成功は `/forms` へリダイレクトし、flash「プロポーザルを更新しました」。
- 更新失敗は `render :edit, status: :unprocessable_entity`。エラー要約・項目別エラー・入力値が残る。
- 削除はまず確認ページ（`GET /forms/:id/delete`）を出し、タイトルと「削除する」`button_to`（`method: :delete`）を置く。成功は `/forms` へリダイレクトし、flash「プロポーザルを削除しました」。
- 削除の確認は JS の `confirm` ではなく、確認ページで行う。no-JS でも同じ経路。

## コントローラ

- `before_action :set_proposal, only: %i[edit update confirm_destroy destroy]`。
- `edit` は `@proposal` を描くだけ。
- `update` は `@proposal.assign_attributes(proposal_params)`。保存できれば redirect、できなければ 422 で `edit`。
- `confirm_destroy` は確認ページ。
- `destroy` は `@proposal.destroy` して redirect。
- `create` / `index` は変えない（フォームは共有パーシャルに置き換えるが、マークアップは同一）。

## フォームの共有

`app/views/proposals/_form.html.erb` を作り、`index` の作成フォームと `edit` が使う。

```erb
<%= form_with model: @proposal, url: local_assigns.fetch(:url, forms_path),
  method: local_assigns.fetch(:method, :post), class: "proposal-form",
  html: { novalidate: true } do |form| %>
  ...
  <%= form.submit local_assigns.fetch(:submit_label, "送信する"), class: "btn btn-primary" %>
<% end %>
```

- `index` は `render "form"`（作成）。
- `edit` は `render "form", url: form_path(@proposal), method: :patch, submit_label: "更新する"`。
- パーシャル内のエラー要約・項目別エラー・`aria-invalid` は作成時と同じ。
- 削除ボタンは編集フォームの **外** に置く（フォームの入れ子を避ける）。

## 確認ページ

- 見出し「プロポーザルを削除」。
- 対象のタイトル・発表者・カテゴリを表示。
- `button_to "削除する", form_path(@proposal), method: :delete, class: "btn btn-primary"`。
- 「キャンセル」は `link_to "キャンセル", forms_path`。
- 削除は取り消せないことを明記する。

## テスト

- 一覧の各カードに編集・削除リンクがある。
- `GET /forms/:id/edit` が既存値のフォームと「更新する」を出す。
- 無効な PATCH → 422、`text/html`、エラー要約・項目別エラー・入力値保持。
- 有効な PATCH → redirect、値が更新される。
- `GET /forms/:id/delete` が確認ページを出す。
- `DELETE /forms/:id` → redirect、件数が1減る、一覧から消える。
- 編集・確認ページは標準フォームで、`data-herb-into` / `data-herb-set` を持たない。
- no-JS: 編集・更新・確認・削除が同じ経路で動く。
- 既存の作成・一覧・フィルタのテストが通る。

## ブラウザ実測（`/tmp/opencode/capture/forms-crud-probe.js`）

- 一覧 → 編集 → 無効な値で更新 → 422（エラーと入力値）→ 修正 → 更新成功 → flash。
- 削除リンク → 確認ページ → 削除 → 一覧から消える。
- 各操作は document GET/POST で slots 0。
- no-JS でも編集・削除が動く。

## メディア

- `forms-light.png` / `forms-dark.png` / `19-forms.gif` を、カードの操作リンクを含めて撮り直す。
- `21-forms-crud.gif`: 一覧 → 編集 → 422 → 修正 → 更新成功 → 削除確認 → 削除、5〜6フレーム。
- 編集ページの still は不要（一覧と GIF で足りる）。日本語フォントと固定クリップは既存と同じ。

## ドキュメント

- `docs/forms.md` に編集・削除・更新 422・確認ページ・slots 0 を追記。
- README の `/forms` 節に CRUD と `21-forms-crud.gif`。
- AGENTS.md の Forms 節に編集・削除の実測。
- hotwire-comparison の対比6に、更新も 422 の標準フォームで完結することを1行追記。

## 非ゴール

- slots での更新・削除、独自 transport、カスタム JS。
- 論理削除、認証、権限、監査ログ、i18n。
- 行内編集（一覧の行をその場でフォームにする）は、422 の全画面経路と競合するため今回は扱わない。
- 一覧のページネーション（`/forms` の一覧は全件のまま）。

## 検討した案

1. **一覧の操作 + 編集ページ + 確認ページ（採用）**: 既存の `/forms` をそのまま CRUD に拡張できる。422 の経路も編集で再利用できる。
2. **行内編集**: 一覧の行をその場でフォームにすると、更新の 422 が全画面になり、行の状態と競合する。編集ページの方が実務的。
3. **新しい管理画面**: `/forms` のメディアを変えずに済むが、同じ Proposal の CRUD が2画面に分裂する。`/forms` を育てる。
4. **JS の confirm で削除**: このアプリはカスタム JS を持たない。確認ページで代替する。

## リスク

- 共有パーシャル化で作成フォームのマークアップが変わり、`/forms` の既存メディアが stale になる。メディアを撮り直す。
- `button_to` の DELETE が no-JS で動くか。統合テストとプローブで確認する。
- 更新の 422 で `form_with model:` が PATCH の URL を保つか。`url: form_path(@proposal)` を明示する。
- 削除確認の GET は副作用なし。削除は DELETE のみ。
- 一覧のフィルタ（client mode）は編集・削除の全画面遷移でリセットされる。仕様とする。

## 受け入れ条件

- 一覧から編集・削除に辿れ、更新の 422 でエラーと入力値が残る。
- 削除は確認ページを経て、標準の DELETE で行える。
- 編集・更新・削除は document リクエストで slots 0。no-JS でも動く。
- 既存の作成・検索・フィルタが壊れない。
- `bin/rails test` と `bin/ci` が green。
- `/forms` のメディアと `21-forms-crud.gif`、docs が更新されている。
