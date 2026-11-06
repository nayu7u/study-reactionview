# 失敗する送信（`/outbox`）設計

- 日付: 2026-11-06
- 状態: 設計案（一括指示により承認扱い）
- 対象: `/outbox`（ナビ外）
- 前提: ReActionView 0.6.0 / herb 0.11.1 / Rails 8.1.4

## 目的

楽観的追加（`data-herb-into`）が失敗したときの挙動を測る。サーバーが 500 を返すと outbox は楽観行に `failed` を立てる。その行を ERB で表示し、outbox の `retry` / `discard` API で再送・破棄する。再送/破棄には小さな JS アダプタが必要になるコストも記録する。no-JS は通常の HTML 送信で flash にする。

## 画面

- `/outbox`「Submission Queue」。
- 上に送信フォーム: タイトル + 「次の送信を失敗させる（デモ）」チェック + 送信。
- 下に提出済みリスト。各行はタイトル、状態（送信中 / 送信に失敗しました）、失敗時の「再試行」「破棄」ボタン。
- 成功は 201 の splice で行が確定。失敗は 500 で `failed` 行が残る。
- 再試行は同じ FormData を再送し、2回目は成功する（セッションの one-shot フラグ）。
- 破棄は行を消す。
- no-JS は通常の POST。失敗は flash alert、成功は flash notice で一覧に戻る。

## データと失敗の注入

`Submission`（`title:string`）を追加。seed は3件。

`SubmissionsController#create`:

- `params[:fail_once] == "1"` かつ `session[:outbox_failed_once]` が未設定なら、セッションにフラグを立てる。
  - `format.slots` は `head :internal_server_error`（本文なし）。
  - `format.html` は `redirect_to outbox_path, alert: "送信に失敗しました（デモ）"`。
- それ以外はフラグを消し、`Submission.create!`。slots は新規行だけを 201 で返し、HTML は notice で redirect。
- 再試行は同じ `fail_once=1` を含む FormData を再送するが、セッションのフラグが立っているので成功する。フラグは成功時に消える。

レイアウトに `alert` の flash 表示を追加する（既存の `notice` と並べる）。

## ビューと outbox

- ページは `herb:slots server`。一覧は `data-herb-name="submissions"` のコレクション。
- 各行は `<%# herb:key submission.id %>` と `<%# herb:state (pending: false, failed: false) %>`。
- 状態ピル:
  - 送信中: `hidden="<%= !pending %>"`
  - 失敗: `hidden="<%= !failed %>"`
- 失敗時の操作:
  ```erb
  <button type="button" data-outbox-retry>再試行</button>
  <button type="button" data-outbox-discard>破棄</button>
  ```
  これらは `hidden="<%= !failed %>"` の領域に置く。
- フォームは `form_with model: @submission, url: outbox_path, data: { herb: { into: "submissions" } }`。`check_box_tag :fail_once, "1", false`。
- 楽観行は outbox が `pending: true, failed: false` で追加。500 で `pending: false, failed: true`。再試行で `pending: true, failed: false` に戻り、201 で確定。

## 再試行/破棄のアダプタ

outbox の API は JS のみで、`data-herb-*` の属性からは呼べない。`app/javascript/outbox_retry.js` を追加する（約12行）。

```js
document.addEventListener("click", (event) => {
  const retry = event.target.closest("[data-outbox-retry]");
  if (retry) {
    event.preventDefault();
    window.HerbRuntime?.outbox?.retry(retry);
    return;
  }
  const discard = event.target.closest("[data-outbox-discard]");
  if (discard) {
    event.preventDefault();
    window.HerbRuntime?.outbox?.discard(discard);
  }
});
```

- `application.js` に `import "outbox_retry"` を追加し、`config/importmap.rb` に pin する。
- これはこのリポジトリで runtime 以外の最初のアプリ JS。`failed` 状態の表示は ERB だけでできるが、再試行/破棄の操作には API の糊が要る、というコストを記録する。
- 再試行/破棄は no-JS では動かない（no-JS の失敗は flash で完結し、failed 行を作らない）。

## テスト

- `test/models/submission_test.rb`: title presence。
- `test/controllers/submissions_controller_test.rb`:
  - GET `/outbox` がフォーム・一覧・`data-herb-into="submissions"` を出す。
  - 正常な slots POST → 201、新規行のみ、`Submission.count` +1。
  - 正常な HTML POST → redirect + notice。
  - fail_once の slots POST → 500、`Submission.count` 変化なし、セッションにフラグ。
  - 直後の再送（同じ fail_once）→ 201、+1、フラグ解除。
  - fail_once の HTML POST → redirect + alert、変化なし。
  - フォームは `data-herb-into` を持ち、no-JS でも POST できる。
- ブラウザプローブ（`/tmp/opencode/capture/outbox-probe.js`）:
  - fail_once で送信 → 楽観行が pending → 500 → failed ピル → 再試行 → 201 → 行確定。
  - 2回目の失敗 → 破棄 → 行が消える。
  - no-JS の失敗 → flash alert。
  - slots リクエスト数（失敗・再試行）と document を記録。
- `bin/ci` green。

## メディア

- `docs/media/outbox-light.png` / `outbox-dark.png`（fullPage @2x）。
- `docs/media/23-outbox.gif`: 送信失敗 → failed 行 → 再試行 → 成功、4〜5フレーム。固定クリップ・日本語フォント・フレーム寸法一致。
- `/forms` / `/apply` のメディアは変えない。

## ドキュメント

- `docs/outbox-failure.md`（新規）: outbox の失敗経路、failed/pending、再試行/破棄の JS API、アダプタのコスト、no-JS、制約。
- README: 「実務検証: 失敗する送信（`/outbox`、ナビ外）」。
- hotwire-comparison: 対比9「楽観的追加の失敗と再試行」を追加（8→9）。
- AGENTS.md: Outbox 節（500 の failed、retry/discard の API、one-shot、アダプタの12行、no-JS、メディア）。
- Patterns footer に `/outbox` のリンク。

## 非ゴール

- 実際のネットワーク障害・タイムアウトのシミュレーション（サーバーの 500 で代用）。
- 本物のジョブキュー、メール送信、認証、i18n。
- アダプタなしの ERB だけの再試行（不可能であることを docs に記録する）。
- `/forms` の変更。

## 検討した案

1. **outbox + 12行アダプタ（採用）**: failed 表示は ERB、再試行/破棄は API。失敗経路の実態を測れる。
2. **ERB だけの再送**: フォームを再表示して再送する。failed 行は残り、本当の再試行ではない。
3. **独自 fetch**: outbox を使わず、すべて自前。標準の楽観的追加の挙動を測れない。
4. **標準フォーム + 422**: 楽観的追加の失敗経路ではない。`/forms` で実証済み。

## リスク

- `outbox.retry` / `discard` が公開 API として安定か。0.6.0 の実装をプローブで確認する。
- ボタン要素から `keyOf` が楽観行の item key を引けるか。行内のボタンで確認する。
- fail_once のセッション one-shot が再試行で正しく解除されるか。
- slots の 500 が `head` で本文なしでも outbox が `failed` にするか（`!response.ok`）。
- 楽観行の `pending`/`failed` がコレクションの item state として宣言され、`setStates` が効くか。
- アダプタの importmap pin。`bin/importmap audit` とブラウザで確認する。
- no-JS の失敗は flash alert。レイアウトの alert 表示を追加する。

## 受け入れ条件

- fail_once の送信で楽観行が failed になり、再試行で成功、破棄で消える。
- failed/pending は ERB のピルで表示される。
- 再試行/破棄は 12行のアダプタで動き、そのコストが docs に記録されている。
- no-JS の失敗は flash alert、成功は flash notice。
- `bin/rails test` と `bin/ci` が green。
- `docs/outbox-failure.md`、README、hotwire-comparison（md / html）、AGENTS.md、stills / `23-outbox.gif` が更新されている。
- `/forms` / `/apply` のデータ・メディア・挙動は変えない。
