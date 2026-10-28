# Dashboard 画面（7画面目）設計

- 日付: 2026-10-28
- 状態: 設計案（承認待ち）
- 対象: `/dashboard`
- 前提: ReActionView 0.6.0 / herb 0.11.1

## 目的

遅いサーバー読みを、ページ全体を待たせずに届ける画面を作る。`<Async>` / `<Lazy>` / `<Fragment>` / `poll` の4つを1つのダッシュボードに載せ、どこが先に届き、どこが状態変更で取り直され、どこが繰り返し更新されるかを、リクエスト数として読める形にする。

題材は Sprint Hub と同じ Task データにする。新しいテーブルやバックグラウンドジョブは作らない。

## なぜ Dashboard か

Client Lab はブラウザ内の操作、Settings はフォーム、Pricing はサーバー計算だった。Dashboard は「サーバー読みが遅い」という、これまでの画面が扱っていない時間の軸を足す。`<Async>` と `<Lazy>` は初回HTMLから内容を外し、`<Fragment>` は状態変更で古くなったサーバー読みを Fallback に差し替え、`poll` は読みを繰り返す。4つとも Herb の slots component で、専用 JavaScript は書かない。

## 画面

- 7画面目。`/dashboard` を追加し、グローバルナビの Sprint Hub の次に Dashboard を入れる。
- ヒーローに「Client mode — 遅延を測る」のバッジと、遅延デモの ON/OFF リンクを置く。
- 上部に `<Async>` のサマリー（全タスク・優先度高・直近24時間）。
- 中段左に `<Fragment>` の優先度フォーカス集計（すべて / 高 / 中 / 低）と、その下に `<Lazy>` の最近のアクティビティ。
- 中段右に `<Async poll="3000">` のハートビート（最終同期とデモ用キュー）。
- 最下部に、初回・スクロール・フォーカス変更・poll のリクエスト数を説明する静的な計測メモを置く。
- モバイルでは1列に積む。ナビは7リンクになるため、狭い幅では padding と font-size を詰めて1行に収める。

## 状態

`app/views/dashboard/index.html.erb` は client mode。公開 state は `focus` だけ。

```erb
<%# herb:slots client %>
<%# herb:state (focus: "all") %>
```

- `focus` は `"all"` / `"high"` / `"medium"` / `"low"`。優先度ボタンは `data-herb-set` の literal。
- `focus` はサーバー読みの引数でもある。ボタンを押すと、クライアントは古くなったサーバー読みを取り直し、`<Fragment>` が Fallback を出す。
- `<Async>` / `<Lazy>` の内部 state（`_herb_block_N`）は Herb が生成する。テンプレートで宣言しない。
- 遅延デモの ON/OFF は state にしない。`?slow=1` の URL パラメータとし、リンクのページ再読み込みで切り替える。
- コントローラーは空にする。集計はビューのヘルパーが state を引数に受けて行う。サーバー読みの登録には state そのものを渡す必要がある（`focus: focus`）。コントローラーの ivar を渡すと Herb は state read を見つけられない。

## 4つの部品

### `<Async>` サマリー

```erb
<Async delay="150" hold="400">
  <%= render "dashboard/summary" %>
  <Fallback>
    <div class="skeleton" aria-hidden="true">…</div>
  </Fallback>
</Async>
```

- 初回HTMLには Fallback だけが入る。ページのマウント直後にブロック要求が飛び、内容が差し替わる。
- `delay="150"` で、速い応答では Fallback をちらつかせない。`?slow=1` では 900ms 待つので、150ms 後に Fallback が見える。
- 内容は全タスク数、優先度高（`priority: 3`）の件数、直近24時間の件数。Task に完了列はないため、完了率は出さない。

### `<Lazy>` アクティビティ

```erb
<Lazy delay="150" hold="400">
  <%= render "dashboard/activity" %>
  <Fallback>
    <p class="skeleton-note">スクロールすると最近のタスクを読み込みます。</p>
  </Fallback>
</Lazy>
```

- 初回HTMLでは Fallback。ブロックが viewport に近づいたときだけブロック要求が飛ぶ。
- 内容は `Task.order(created_at: :desc).limit(5)`。タイトル、優先度、相対時刻。
- ファーストビューに入れず、スクロールして初めて要求される位置に置く。GIF ではスクロールして Fallback → 内容の順を見せる。

### `<Fragment>` 優先度フォーカス集計

```erb
<div class="focus-seg">
  <button data-herb-set="focus=all" aria-pressed="<%= focus == "all" %>">すべて</button>
  <button data-herb-set="focus=high" aria-pressed="<%= focus == "high" %>">高</button>
  <button data-herb-set="focus=medium" aria-pressed="<%= focus == "medium" %>">中</button>
  <button data-herb-set="focus=low" aria-pressed="<%= focus == "low" %>">低</button>
</div>

<Fragment delay="120" hold="500" on="focus">
  <%= render "dashboard/focus_stats", focus: focus %>
  <Fallback>
    <p class="skeleton-note">集計中…</p>
  </Fallback>
</Fragment>
```

- 初回HTMLには `all` の集計が入る。優先度ボタンを押すと `focus` が変わり、`focus_stats` のサーバー読みが古くなる。Fallback を出してから、新しい集計が届く。
- 優先度ボタンは `<Fragment>` の外に置く。中に置くと Fallback がボタンまで覆い、連続で切り替えられなくなる。
- `on="focus"` を明示する。読みの自動検出に頼らず、この state の書き込みで Fallback を出す意図を固定する。
- `focus_stats` は選択した優先度のタスク数を、7日 / 30日 / 全期間の内訳付きで返す。`all` は全タスク。
- 期間別（7日 / 30日 / 全期間）を主役にしない。なぜなら、既存の seed と fixture は最近のタスクに偏り、3つの期間で同じ数になるからだ。優先度なら既存データで差が出て、seed も他の画面のメディアも変えずに済む。

### `poll` ハートビート

```erb
<Async poll="3000" delay="150" hold="400">
  <%= render "dashboard/heartbeat" %>
  <Fallback>
    <p class="skeleton-note">同期中…</p>
  </Fallback>
</Async>
```

- 初回は Fallback。マウント直後に1回読み、以降は3秒ごとにブロック要求を繰り返す。
- 内容は最終同期時刻と、デモ用のキュー深さ。キューは `Time.current` から決まるシミュレーション値で、実ジョブではない。
- クライアントは `document.hidden` の間、poll を止める（実装済み）。GIF とプローブは表示中の更新だけを見る。
- 3秒間隔はデモ用。実運用の間隔ではない。

## 遅延デモ

`?slow=1` のときだけ、**slots リクエスト**のサーバー読みを900ms遅らせる。

```rb
# app/helpers/dashboard_helper.rb
SLOW_SECONDS = 0.9

def slow_demo? = params[:slow] == "1"

private

def slow_slots
  return unless slow_demo? && request.format.slots?
  return if @slow_slots_slept

  @slow_slots_slept = true
  sleep SLOW_SECONDS
end
```

- `dashboard_summary` / `focus_stats` / `recent_activity` / `heartbeat` の各ヘルパーが、先頭で `slow_slots` を呼ぶ。
- 1リクエストにつき1回だけ眠る。slots の再描画はテンプレート全体を描画するため、複数のヘルパーが呼ばれても合計は900msに固定する。各ヘルパーで眠ると、フォーカス変更が数秒かかってしまう。
- 初回HTMLでは `request.format.slots?` が false なので眠らない。ページの外枠と `<Fragment>` の初期内容はすぐ返る。
- `<Async>` / `<Lazy>` のブロック要求、`<Fragment>` の再取得、poll は slots なので眠る。Fallback が見える。
- コントローラー全体を `sleep` させない。なぜなら、初回HTMLまで遅くなり、「外枠は速く、重い部分だけ後から」というこの画面の主張が消えるからだ。
- 画面上の state トグルにしない。なぜなら、遅延 state を steering に載せる設計が増え、4つの部品の検証がぼやけるからだ。URL なら共有でき、ページ再読み込みだけで切り替わる。

ヒーローのリンクは、OFF のとき `?slow=1` へ、ON のとき `/dashboard` へ戻す。文言は「遅延デモ: OFF」/「遅延デモ: ON（900ms）」。

## データ

既存の Task だけを使う。migration は追加しない。

- サマリー: `Task.count`、`Task.where(priority: 3).count`、`Task.where(created_at: 24.hours.ago..).count`
- フォーカス集計: `focus` に応じた `Task.where(priority: ...)` の合計と、7日 / 30日 / 全期間の内訳
- アクティビティ: 直近5件
- ハートビート: `Time.current` と、そこから決まるデモ用キュー値
- 完了状態はDBにない（Hub の done はブラウザ所有）。ダッシュボードでは扱わない。

## リクエスト

`?slow=1` のときの期待値。

| 操作 | リクエスト | 遅延 |
|---|---|---|
| 初回表示 | document 1 + Async 2（サマリー / ハートビート） | document は即時、各 Async は 900ms |
| アクティビティまでスクロール | Lazy block 1 | 900ms |
| 優先度ボタン | slots 1（Fragment 再取得） | 900ms |
| poll | 3秒ごとに block 1 | 各 900ms（次回は応答後3秒） |
| 遅延リンク | document 1（再読み込み） | 即時 |

- Async 2本は並行に飛ぶ。順序は保証しない。
- 初回の Fragment 内容は document に含まれる。追加のリクエストはない。
- `?slow=0`（またはパラメータなし）では、各ブロックは通常の速度で返る。`delay="150"` により Fallback が見えないことがある。
- slots 再描画が複数のヘルパーを呼んでも、`slow_slots` のメモ化で1リクエスト900msに抑える。

## テスト

`test/controllers/dashboard_controller_test.rb`。

- 初回HTML: 見出し、7リンクのナビ、遅延リンク、フォーカスボタン、Async / Lazy の Fallback、Fragment の初期集計。
- manifest: `focus` の宣言、`states.fragments` に async 2（片方は `poll: 3000`）、lazy 1、Fragment 1 が載る。
  - Fragment の `reads` はスロット番号の配列で、state 名ではない。`on` に `"focus"`、`server.reads` に `"focus"` があることを見る。
- 初回HTMLにサマリー / アクティビティの内容がなく、Fallback だけがあること。
- 遅延リンク: 通常時は `?slow=1` へ、`?slow=1` 時は `/dashboard` へ戻る。
- ブロック要求: manifest の `fragments` から async / lazy のブロック番号を引き、`format: :slots` と `Herb-Block` ヘッダで要求する。応答の JSON にサマリー / アクティビティの内容が入る。番号は直書きしない。
- Fragment 再取得: `Herb-State` に `focus=high` を載せた slots 要求で、高優先度の集計に変わる。テンプレートパスは manifest のキーから引く。
- スイートでは `sleep` を起こさない（`slow` を付けない）。900ms の実測はブラウザプローブで行う。

ブラウザプローブ（`/tmp/opencode/capture/dashboard-probe.js`）。

- `?slow=1` で初期 document 1、Async block 2 を確認。各ブロックが 800ms 以上かかること、Fallback が見えてから内容に変わることを確認。
- スクロールで Lazy block 1、フォーカス変更で slots 1（`Herb-Block` なし）、poll で 3秒後に block 1 を確認。各 800ms 以上。
- `?slow=0` で同じ操作をして、ブロックが 500ms 未満で返ることを確認。
- 7リンクのナビが 800px / 1000px で1行に収まること。
- 日本語フォントスタックと、CDP の実フォントが `Noto Sans CJK JP` であること。
- pageerror / console error がないこと。

## メディア

- `docs/media/dashboard-light.png` / `dashboard-dark.png`（1000×900、fullPage）。
- `docs/media/18-dashboard.gif`（1000×900 の viewport。フレームは Fallback → Async 内容 → Fragment Fallback → Fragment 内容 → Lazy までスクロール → Lazy Fallback → Lazy 内容 → poll 更新）。
- 7リンクナビになるため、Hub / Patterns / Client Lab / Pricing / Settings の stills と Hub 03 / 04 の GIF、`ui-dialog.png`（ナビが写る full-page still）を撮り直す。ナビが写らない要素クリップの GIF はそのまま。
- 静止画・GIF とも日本語フォントスタックで撮り、CDP で実フォントを確認する。GIF は固定の viewport サイズで撮り、フレーム寸法を揃える（Settings の教訓）。

## ドキュメント

- README: 7画面、Dashboard の行、機能⑱〜㉑（Async / Lazy / Fragment / poll）、`18-dashboard.gif`、テスト一覧。
- `docs/hotwire-comparison.md`: 証明マップに Dashboard 行、§⑤ に遅延リクエストの数え方、§⑥ に no-JS / 疑似キューの境界。
- AGENTS.md: ブロック要求の `Herb-Block`、`?slow=1`、`poll` の停止条件、7リンクナビ、実測したリクエスト数。
- HTML twin の同期は E まで待つ。D の `/compare` は作らない。

## 非目標

- 実際のバックグラウンドジョブ、WebSocket、Action Cable、ワーカープロセス
- 完了率の永続化、Task 以外のモデル、migration
- 認証、権限、実運用の監視
- no-JS での遅延コンテンツの読み込み（初回HTMLは Fallback のまま。`<noscript>` で案内する）
- 4つの部品を別々の画面に分けること
- D の Turbo 比較画面、E の HTML twin 同期

## 検討した案

- **1画面の client mode（採用）**: 公式ドキュメントの `<Async>` / `<Lazy>` / `<Fragment>` は `herb:slots client` で例示されている。Task の集計はサーバー読みのまま、`focus` だけをクライアント state にする。4つを1画面で比較できる。
- **server mode の1画面**: データはサーバー寄りで素直だが、遅延コンポーネントの例が client mode で、ブロックの内部 state がサーバー応答でどう扱われるかを追加検証する必要がある。採用しない。
- **機能ごとに別画面**: 1つずつは読みやすいが、ダッシュボードにならず、ルートとナビとドキュメントが増える。採用しない。
- **期間別の集計**: 既存データが最近に偏り、7日 / 30日 / 全期間が同じ数になる。古い seed を足すと他の画面の件数とメディアまで変わる。採用しない。
- **固定ディレイ**: 常に遅く、通常の画面として重い。採用しない。
- **画面内の遅延 state**: 再読み込みなしで切り替わるが、steering と再取得の設計が増える。採用しない。
- **新しい集計テーブル / ワーカー**: 遅延の題材は作れるが、この検証に不要な migration と運用が増える。採用しない。

## リスクと実装時に確かめること

- `<Async>` / `<Lazy>` / `<Fragment>` がこのアプリの Rails 8.1 + ReActionView 0.6.0 で実際にコンパイルされ、ブロック要求が返ること。実装の最初のタスクで最小のブロック応答をテストに固定する。
- `Fragment` の `on="focus"` と、`focus_stats(focus)` のサーバー読み検出が両立すること。`focus: focus` のように state そのものを渡し、manifest の `on` と `server.reads` を確認する。
- `Herb-Block` 応答の JSON 形。テストは manifest の `fragments` から番号を引き、内容の文字列で確認する。
- `slow_slots` が初回HTMLで眠らないこと。プローブで document の応答時間とブロックの応答時間を分けて測る。
- `slow_slots` のメモ化が1リクエスト1回で効くこと。フォーカス変更の slots 応答が約900msで返ることをプローブで測る。
- 7リンクのナビが 800px で1行に収まること。狭い幅の padding / font-size を調整し、プローブでリンクの `top` が1種類であることを確認する。
- `poll` の3秒間隔と900ms遅延が重なると、実効間隔は約3.9秒になる。GIF とプローブの待ち時間はこれに合わせる。
