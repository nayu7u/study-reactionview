# 失敗する送信（`/outbox`） — 楽観的追加の 500 と再試行

ReActionView 0.6.0 + herb 0.11.1 の検証アプリで、**楽観的追加（`data-herb-into`）が失敗したとき**の挙動を測った記録です。画面は `/outbox`（ナビ外）。サーバーが 500 を返すと outbox は楽観行に `failed` を立て、再試行・破棄できます。再試行/破棄の操作だけは outbox の JS API を呼ぶ小さなアダプタが必要です。

![失敗 → failed 行 → 再試行 → 成功](media/23-outbox.gif)

## 何を確かめたか

`/forms` の 422、`/catalog` の GET、`/apply` の多段フォームは、いずれも標準フォームの経路でした。実務では「押した瞬間に行が入り、後から失敗が分かる」楽観的追加も必要です。

- 500 の slots 応答で、楽観行が `failed` になるか。
- 失敗した行を ERB だけで表示できるか。
- 再試行・破棄はどこまで ERB の属性で書けるか。
- no-JS ではどうフォールバックするか。

## 結論

`failed` の**表示**は ERB で書けます。`pending` / `failed` の per-row state と `hidden` の presence を置けば、outbox が 500 のときに自動で失敗ピルと操作ボタンが出ます。

一方、**再試行・破棄の操作**は `HerbRuntime.outbox.retry/discard` の JS API しかなく、`data-herb-*` 属性からは呼べません。`app/javascript/outbox_retry.js` の小さなアダプタで `data-outbox-retry` / `data-outbox-discard` を拾って呼ぶ必要があります。これはこのリポジトリで runtime 以外の最初のアプリ JS です。

## 失敗の経路

```ruby
def create
  if params[:fail_once] == "1" && !session[:outbox_failed_once]
    session[:outbox_failed_once] = true
    respond_to do |format|
      format.slots { head :internal_server_error }
      format.html { redirect_to outbox_path, alert: "送信に失敗しました（デモ）" }
    end
    return
  end
  ...
end
```

- `fail_once` はセッションの one-shot。最初の slots POST は 500、同じ FormData の再試行は 201 になる。
- 楽観行は outbox が `pending: true, failed: false` で追加。500 で `pending: false, failed: true`。再試行で `pending: true, failed: false` に戻り、201 で確定。
- 行の状態ピルは `hidden="<%= !pending %>"` / `hidden="<%= !failed %>"`。失敗時の操作は `hidden="<%= !failed %>"` の領域に置く。
- 楽観行のタイトルは `data-herb-name="title"` が必要。無いと outbox の `text: true` がタイトルを埋められず、空の行になる（実測）。
- `data-herb-into` は `data: { "herb-into" => "submissions" }` と直接指定する。`data: { herb: { into: ... } }` では属性が出なかった。

## 再試行/破棄のアダプタ

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

- `application.js` に `import "outbox_retry"`、`config/importmap.rb` に pin。
- 再試行は outbox が保持している同じ FormData を送り直す。セッションの one-shot フラグが 2 回目を成功させる。
- 破棄は楽観行を消す。サーバーには何も送らない。

## 実測

ブラウザ実測は `/tmp/opencode/capture/outbox-probe.js`（headless Chromium、リポジトリ外）。

| 操作 | slots | 結果 |
|---|---|---|
| fail_once で送信 | 1（500） | 楽観行が pending → failed。失敗ピルと操作が出る |
| 再試行 | 1（201） | failed が消え、行が確定。`Submission` が1件増える |
| 2回目の失敗 → 破棄 | 1（500） | 行が消える |
| no-JS の失敗 | 0（HTML） | alert flash。行は作られない |

プローブの要約は `failed: true`, `retry: true`, `discard: true`, `noJS: true`, `slots: 3`, `documents: 1` です。統合テストでは 201 の新規行、500 とセッション、再試行の 201、HTML の alert、no-JS フォームを固定しています。

## 制約

- 再試行/破棄は JS が要ります。ERB の属性だけでは完結しません。
- no-JS の失敗は flash alert で、failed 行は作りません。楽観的追加は JS の機能です。
- 失敗はサーバーの 500 で injected しています。実際のネットワーク断・タイムアウトではありません。
- `fail_once` はセッションの one-shot。再試行の FormData に `fail_once=1` が残っていても、2回目は成功します。
- 本物のジョブキューやメール送信ではありません。`/forms` / `/apply` のメディアと挙動は変えていません。

## 使い分け

- 楽観的に行を入れたい書き込みは `data-herb-into`。失敗表示は `failed` の presence、操作は小さな API アダプタ。
- サーバー検証が主役のフォームは `/forms` の 422。
- 多段のサーバー検証は `/apply` のステップ別 422。
- 検索・共有 URL は `/catalog` の標準 GET。

outbox の失敗は「表示は ERB、操作は API」という分担になります。この小さなアダプタを許容できるなら、楽観的追加の失敗も実務で扱えます。
