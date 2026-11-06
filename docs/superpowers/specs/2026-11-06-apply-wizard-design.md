# 検証つきウィザード（`/apply`）設計

- 日付: 2026-11-06
- 状態: 設計案（一括指示により承認扱い）
- 対象: `/apply`（ナビ外）
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

## 目的

3ステップのプロポーザル応募ウィザードを作る。各ステップは標準フォームでサーバー検証し、失敗は 422 の HTML 全画面再描画でエラーと入力値を保持する。下書きは DB に保存し、セッションで紐付ける。最後の確認ステップで `Proposal` を作成する。カスタム JS は使わない。

## なぜ

`/forms` は1画面の作成・編集・削除を実証した。実務の応募・オンボーディングは多段で、各ステップの検証と「戻る」が要る。ステップごとの 422、セッション下書き、明示的な戻る、最後の確定を1画面で測る。

## 画面

- `/apply` はステップ1（発表者名・メール）。
- `/apply?step=2` はステップ2（タイトル・概要・カテゴリ）。
- `/apply?step=3` は確認（値の表示と「送信する」）。
- 上部にステップインジケータ（1 発表者 / 2 トーク / 3 確認）。完了済みのステップへは GET リンクで戻れる。
- 各ステップに「戻る」「次へ」または「送信する」。ステップ1の「戻る」は `/forms` へ。
- 最後の送信で `Proposal` を作成し、`/forms` へリダイレクトして flash「プロポーザルを送信しました」。
- 下書きは `ApplicationDraft` に保存し、`session[:application_draft_id]` で紐付ける。URL に draft id は出さない。

## データ

`ApplicationDraft`（`application_drafts`）:

- `speaker_name:string` / `email:string` / `title:string` / `abstract:text` / `category:string`。
- `attr_accessor :step`（DB には保存しない。現在のステップの検証に使う）。
- 検証はステップ依存:
  - step >= 1: speaker_name presence + max 40、email presence + format。
  - step >= 2: title presence + 5..80、abstract presence + 30..600、category inclusion（`Proposal::CATEGORIES`）。
  - step 0（下書き作成時）は検証しない。
- `proposal_attributes` は 5項目のハッシュを返し、最後の `Proposal.create!` に渡す。

## ルートとコントローラ

```ruby
get "/apply", to: "applications#show", as: :apply
patch "/apply", to: "applications#update"
```

- `ApplicationsController#show`: `step` を 1..3 に clamp し、セッションの下書き（なければ作成）を `@application` に。`@application.step = @step`。
- `#update`: 同じ下書きに `application_draft[...]` を assign（step 3 はフィールドなしなので assign しない）。`valid?` なら:
  - step < 3: `save` して `redirect_to apply_path(step: step + 1)`。
  - step 3: トランザクションで `Proposal.create!(@application.proposal_attributes)` と下書き削除、セッション削除、`/forms` へ redirect + flash。
- 無効なら `render :show, status: :unprocessable_entity`。`@application.errors` と入力値が残る。
- ステップを飛ばす URL（`?step=3`）は許可するが、そのステップの検証（全項目）が走る。無効なら 422。
- 下書きはセッションの id でのみ引く。他人の下書きは見えない。

## ビュー

- `app/views/applications/show.html.erb` 1枚で3ステップを切り替える。
- ステップ1/2は `form_with model: @application, url: apply_path(step: @step), method: :patch`。フィールドはステップごとに出し分ける（サーバー側の `if @step`）。
- ステップ3は `form_with url: apply_path(step: 3), method: :patch` の確認フォーム（フィールドなし、送信ボタンのみ）。
- エラー要約（`role="alert"`）と項目別 `.field-error`、`aria-invalid` は `/forms` と同じ。
- ステップインジケータはリンク（GET）。現在のステップは `aria-current="step"`。
- ステップ1の「戻る」は `/forms`。ステップ2の「戻る」は `apply_path(step: 1)`、ステップ3は `step: 2`。
- no-JS でもフォームとリンクだけで動く。

## テスト

- `test/models/application_draft_test.rb`: step 0 は空でも有効、step 1 の必須/形式、step 2 の文字数/カテゴリ、step 3 は全部、`proposal_attributes`。
- `test/controllers/applications_controller_test.rb`:
  - GET `/apply` がステップ1と下書き作成、セッション id。
  - step 1 無効 PATCH → 422、エラー、値保持、下書きは未保存のまま。
  - step 1 有効 → `?step=2` へ redirect、下書き保存。
  - step 2 無効/有効。
  - step 3 の確認表示、`?step=99` は 3、`?step=0` は 1。
  - step 3 の PATCH で `Proposal` が1件増え、下書きが消え、セッションが消え、`/forms` へ redirect + flash。
  - 戻る（GET step 1）で値が残る。
  - 2つの独立セッションが別の下書きを持つ（`open_session`）。
  - 標準フォームで `data-herb-into` / `data-herb-set` を持たない。
- 既存テストと `bin/ci` が green。

## ブラウザ実測（`/tmp/opencode/capture/apply-probe.js`）

- `/apply` → 空で次へ → 422（エラーと値）→ 入力 → step 2 → 無効で 422 → 修正 → step 3 → 戻る → step 2 → 次へ → 確認 → 送信 → `/forms` の flash と新しいカード。
- 各操作は document GET/PATCH で slots 0。
- no-JS でも同じ流れ。
- ブラウザの戻る/進むは明示リンクとは別物として記録する（PATCH の履歴は再送信の確認を出すことがある）。

## メディア

- `docs/media/apply-light.png` / `apply-dark.png`（fullPage @2x）。
- `docs/media/22-apply.gif`: step 1 → 422 → step 2 → step 3 → 送信成功、5〜6フレーム。固定クリップ・日本語フォント・フレーム寸法一致。
- `/forms` のメディアは変えない（ウィザードへのリンクは README / Patterns footer / docs から）。

## ドキュメント

- `docs/wizard.md`（新規）: 3ステップ、ステップごとの 422、セッション下書き、戻る、最後の確定、slots 0、no-JS、制約。
- README: 「実務検証: 検証つきウィザード（`/apply`、ナビ外）」を追加。
- hotwire-comparison: 対比8「多段フォームの検証は各ステップの 422」を追加（7→8）。
- AGENTS.md: Wizard 節（セッション下書き、step 検証、最後のトランザクション、プローブ、メディア）。
- Patterns footer に `/apply` のリンクを追加。

## 非ゴール

- slots / client mode でのウィザード、URL 同期 JS、カスタム JS。
- 認証、ユーザーごとの下書き一覧、中断下書きの自動削除、メール送信、i18n。
- ブラウザの戻る/進むで PATCH を再送信する挙動の保証（明示リンクを正とする）。
- `/forms` の変更（メディアを stale にしない）。

## 検討した案

1. **DB 下書き + セッション + ステップ別 GET/PATCH（採用）**: リロード・戻る・no-JS に強く、ステップごとの 422 を標準フォームで測れる。
2. **セッションのハッシュに下書き**: DB 不要だが、セッションサイズとテストの扱いが増える。DB の方が実務的。
3. **1画面の client state**: サーバー検証が各ステップで走らず、「検証つき」の主題に反する。
4. **ステップを POST のみ**: 戻るに再送信が要る。GET の戻るリンク + PATCH の前進にする。

## リスク

- ブラウザの戻るで PATCH の再送信確認が出る。明示的な「戻る」GET を正とし、プローブで記録する。
- ステップを飛ばす URL は許可するが、そのステップの検証で弾く。テストで固定。
- 放棄された下書きが DB に残る。今回は自動削除しない（非ゴール）。dev では seed で消さない。
- 最後の `Proposal.create!` と下書き削除をトランザクションにする。
- セッション id がない/古い場合は新しい下書きを作る。
- メディアの固定クリップはステップごとの高さが違う。最大を測って固定する。

## 受け入れ条件

- 3ステップが GET `?step=` と PATCH で動き、各ステップの無効入力が 422 でエラーと値を保持する。
- 戻るリンクで前のステップの値が残る。
- 最後の送信で Proposal が1件増え、下書きとセッションが消え、`/forms` に flash 付きで戻る。
- 全操作で slots 0、no-JS でも動く。
- `bin/rails test` と `bin/ci` が green。
- `docs/wizard.md`、README、hotwire-comparison（md / html）、AGENTS.md、stills / `22-apply.gif` が更新されている。
- `/forms` のデータ・メディア・挙動は変えない。
