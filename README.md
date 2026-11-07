# Study ReActionView

**ReActionView 0.6.0 + Herb 0.11.1 の検証ショーケース**。Kaigi on Rails 2026（Marco Roth: "Herb in Rails"）の主張、
すなわち **ERB のみで Phoenix LiveView 的な細粒度リアクティビティが成立する** ことを、7つのナビ画面と
6つの実務検証で実演する。

- React / Stimulus / Node / yarn / ビルドパイプラインは、アプリのコードからは一切使っていない。
  `app/javascript/application.js` は `import "reactionview"` と、`/outbox` の再試行/破棄を拾う小さなアダプタだけ。
  Rails 標準の `turbo-rails` / `stimulus-rails` は Gemfile と importmap に残るが、import していない。
- スタイルは `app.css` と UI Kit 用の `reactionview_ui.css` の2枚。どちらも素の CSS で、ビルドはない。
- 細粒度の更新は Herb の slots が担う。state 変化に対して、HTML ではなく値の JSON
  （`application/vnd.herb.slots+json`）だけが往復し、クライアントが差分を当てはめる。
- Hotwire（Turbo + Stimulus）が担っていた役割ごとの対比は [docs/hotwire-comparison.md](docs/hotwire-comparison.md)。

## 7つのナビ画面

| 画面 | 宣言 | 見せていること |
|---|---|---|
| Sprint Hub `/` | `<%# herb:slots server %>` | サーバーが答える読み取り、key 付き行の差分更新、ピン/星の同時連動、楽観的追加 |
| Dashboard `/dashboard` | `<%# herb:slots client %>` | Async / Lazy / Fragment / poll の遅延読み。0.6.0 で動く範囲とギャップ |
| Patterns `/patterns` | `<%# herb:slots server %>` | 実務から拾った3パターン: フィルタチップ、もっと見る、詳細連動 |
| Pricing `/pricing` | `<%# herb:slots server %>` | サーバーが計算する見積もり、steering、presence、READ slot |
| Settings `/settings` | `<%# herb:slots client %>` | タブ・依存フィールド・未保存状態・デモ保存（全操作 0 往復） |
| Client Lab `/lab` | `<%# herb:slots client %>` | 未描画分岐の格納（parking）、派生状態、サーバー往復ゼロのUI |
| UI Kit `/ui` | `<%# herb:slots client %>` | shadcn/ui モデルの検証キット reactionview-ui（9コンポーネント、全操作スロット往復 0） |

機能番号は画面内の検証項目番号で、README の並びは画面順だ。Hub の ⑯ は ② のリスト内、
Settings の ⑰ と Dashboard の ⑱〜㉑ は各画面のタグに対応する。

## ナビ外の6つの実務検証

| 画面 | 見せていること | ドキュメント |
|---|---|---|
| `/forms` | 標準 `form_with` と 422 の全画面再描画。同じページの client mode 絞り込み（0往復） | [docs/forms.md](docs/forms.md) |
| `/catalog` | 検索・カテゴリ・ページを URL に載せる。概要の開閉だけ client mode（0往復） | [docs/url-state.md](docs/url-state.md) |
| `/apply` | 3ステップの応募フォーム。各ステップは標準フォームでサーバー検証、下書きはセッション | [docs/wizard.md](docs/wizard.md) |
| `/outbox` | 楽観的追加の 500 失敗を `failed` 行・再試行・破棄で扱う | [docs/outbox-failure.md](docs/outbox-failure.md) |
| `/thread` | 入れ子のキー付きコレクション。外側の投稿を再構築せず返信だけを差分適用 | [docs/thread.md](docs/thread.md) |
| `/tree` | 4階層のファイルツリー。深さ2以上の開閉も per-node state で 0往復 | [docs/tree.md](docs/tree.md) |

ナビには出さない。Patterns の footer、README、各 docs からリンクしている。

## 2つのモード

| | server mode | client mode |
|---|---|---|
| state | ブラウザ所有。リクエストごとに `Herb-State` で送る | 初回 HTML に宣言と未描画分岐を格納する |
| 更新 | 同じアクションが slots 応答で値だけを返す | クライアントが格納済みの分岐と state を評価する |
| サーバー読み | DB 検索・計算・一覧など何でも読める | 初回のサーバー読みが基本。ループ内のサーバー読みは branch refetch になる |
| 向く用途 | 検索・並び替え・詳細・料金計算 | タブ・フォーム・ウィザード・アコーディオン |
| 0.6.0 の境界 | state 条件の分岐が反転したときだけ自動で往復する。反転しない操作は `$refresh` を合成する | パーシャル内の分岐は materialize されないため、presence（`hidden`）と CSS で切り替える |

GIF は操作の見た目を示す。0往復/1往復の回数は headless Chromium のプローブで測った値で、GIF 単体では分からない。

## セットアップ

Ruby 4.0.9 / Rails 8.1.4 / SQLite で動く。Node / yarn は不要。

```console
$ bin/setup --skip-server  # bundle install + db:prepare
$ bin/rails db:setup       # 初回の seed 込み DB
$ bin/rails server         # http://localhost:3000
$ bin/ci                   # Rubocop / 監査 / Brakeman / テスト / seed 再投入
```

## Sprint Hub（server モード、`/`）

検索・並び替え・追加はすべてサーバー側で行う。state はリクエストごとにブラウザからサーバーへ渡り、
同じアクションが HTML ではなく値で応える。

<div><img src="docs/media/hub-light.png" alt="Sprint Hub (light)" width="49%"/> <img src="docs/media/hub-dark.png" alt="Sprint Hub (dark)" width="49%"/></div>

### 機能① サーバーが答える読み取り

![検索・並び替えはサーバーが絞り込む](docs/media/01-server-reads.gif)

- 検索語・並び順は `herb_state("query")` / `herb_state("order")` としてコントローラーでも宣言し、
  ビューとコントローラーの両方が同じ名前で読む。これで最初の描画から filter が効く。
- 入力は `data-herb-debounce="220"`。打鍵のたびの往復を 220ms にまとめて、同じ `GET /?format=slots` が答える。
- リストの行は `<%# herb:key %>` 付き → 応答は `{items, order}` のキー付き照合になり、行は移動する
  （再構築しない）。並び替え GIF で行がアニメーションせず“その場で並び替わる”のは、キーのおかげだ。
- `$refresh`（🔄 同期）だけが明示的な「サーバーに全部問い合わせ直す」手段だ。

### 機能② 細粒度更新＋楽観的追加

![行のチェックとピン/星は0往復、統計はfoldで即時](docs/media/02-row-state.gif)

- 取り消し線・行の文言ピルは **presence バインディング**（`checked="<%= done %>"`）＋ CSS `:has(input:checked)`
  で即時描画する。ピルは「✔ 完了」「未完了」の両方を DOM に置いて CSS で表示を切り替えている。
  server モードではブラウザ所有 state を分岐の条件には書けない（未描画側が格納されず refetch storm になる）。
- 統計「N/M 件完了」は **カウントfold** で作る。キー付き行の中に
  `<% if done %><% done_count += 1 %><% end %>` の 3 タグを置くのが決まった形だ。manifest には
  `count: {by: 1, when: ["done"]}` として現れ、チェックのたびにサーバー往復なしで client が計算し直す。
- 「行の見た目を属性値の補間で表現しない」（`class="<%= … if done %>"` を書かない）のが原則だ。
  属性補間はサーバー読みスロットになり、チェックのたびの往復を生む。見た目は CSS、数値は read slot で分担する。
- ピン/星も同じリストの中で動く。詳細は機能⑯にまとめた。

#### 楽観的追加

![追加は 201 の新規行だけで入り、同期で確定](docs/media/03-optimistic-add.gif)

- 「＋ 新規タスク」でスライドインする backdrop ドロワー。分岐はサーバー描画のまま答える。
- 送信は楽観的で、ボタンを押すと応答を待たずに行が差し込まれる（`data-herb-into="tasks"`）。
  応答は 201 で新規行だけを返し、クライアントは `items` の splice で受ける。
- 送信に成功するとドロワーは閉じ、打ち込んだ title もリセットされる
  (`data-herb-set="submit->drawer_open=false"` と `data-herb-reset="submit->title"` の二本立て)。
- hero の合計（`Task.count`）は GET 応答では更新されるが、POST splice ではされない。
  0.6.0 のクライアントが 201 で適用するのは collection だけだ。GIF の最後で 🔄 同期を押し、
  hero が 10→11 に変わって「楽観 → 確認」が完了する（実測の制約は AGENTS.md にある）。
- 検索中に追加すると、201 の splice は query を無視して新しい行を差し込む。同期すると検索結果に戻る。
- コントローラーは no-JS の `POST /tasks` も受ける。hidden token 付きのふつうの `<form method="post">` として送れば、
  flash 付き redirect が返る。ただし Hub のドロワーは JS で開くため、ブラウザで JS を切ると作成フォームには到達しない。
  no-JS のフォーム操作は `/forms` などで確認する。

### 機能③ ドロワーとフォームのバインディング（window句を含む）

![Ctrl+B で開き、Esc で閉じる](docs/media/04-window-clauses.gif)

- `data-herb-set="keydown.meta+b@window->drawer_open=true"` で、⌘B（Ctrl+B）でもドロワーが開く。
  要素の外（window）にリスナーを張る句だ。`modifier AND match` の設計上、`meta+b` と `ctrl+b` は
  **1つの binding では OR にできない**。空白区切りの別 binding として並べる。
- 閉じる側は `click@outside->…=false` と `keydown.esc@window->…=false` の複合だ。
- 送信の成功でドロワーを閉じる処理と、title のリセットは機能②の楽観的追加で使っている。

### 機能⑯ ピン／星（機能②のリスト内）

![行の星と「N件ピン留め」が0往復で揃う](docs/media/16-pin.gif)

- 行の星は `pinned` の presence バインディング。星の塗りと行の強調は CSS `:has(.task-pin input:checked)` で行う。
- 「N件ピン留め」は `pinned_count` のカウントfold。カウントはループの後でしか読めないため、
  ヘッダではなくリスト直後のサマリーに置いている。
- 星はブラウザ所有の state。リロードで消えるが、行の見た目とサマリーは **0 往復**で揃う。
- done の `:has(input:checked)` は `.task-check` にスコープし、ピンのチェックと干渉させない。

## Dashboard（client モード、`/dashboard`）

ページの外枠を先に返し、重い集計だけを後から届ける。`<Async>` / `<Lazy>` / `<Fragment>` / `poll` の4つを1画面に並べ、0.6.0 で動く範囲と動かない範囲を分けて記録する。遅延デモは `?slow=1` で切り替える。

<div><img src="docs/media/dashboard-light.png" alt="Dashboard (light)" width="49%"/> <img src="docs/media/dashboard-dark.png" alt="Dashboard (dark)" width="49%"/></div>

### 機能⑱ Async サマリー

![Async・poll・Fragment・Lazy の遅延読みが後から届く](docs/media/18-dashboard.gif)

- 初回HTMLは Fallback だけ。マウント直後に2本のブロック要求（サマリー / ハートビート）が飛ぶ。`?slow=1` では各900ms、ページ本体は約30msで返る（実測）。
- 2本目はサーバーが直列なら待たされ、907ms / 1812ms になった（実測）。クライアントは同時に発行している。
- ブロックの内容は **inline** で書く。0.6.0 のブロック応答は partial の statics を運ばず、`render` した partial は描画されない（実測）。
- サマリーは全タスク、優先度高、直近24時間。Task に完了列はないため、完了率は出さない。

### 機能⑲ Lazy の defer と配置ギャップ

- `<Lazy>` は初期表示の位置ではブロック要求が1回飛び、内容が届く。`?slow=1` ではサーバーが直列なら2703ms、`slow=0` では6ms（実測）。
- Fallback は「読み込み中…」と最新3件。ブロックの内容が届くと本文に置き換わる。
- カードを下段（初期 viewport の外）に置くと、0.6.0 ではスクロールしても slots 要求が0で Fallback のまま（実測）。カードは初期表示の位置に置き、この配置依存の制約をリクエストカードに明記した。
- コレクションをブロック内に置くと `items` が空になるため、3件は明示的な行で描画している。

### 機能⑳ Fragment の優先度フォーカス

- 優先度（すべて / 高 / 中 / 低）は `focus` state。`focus: focus` でサーバー読みを登録し、`on="focus"` と `server.reads` が manifest に載る。
- 変更は slots 1回（910ms）で集計が 10→3 に更新される。**Fallback は0.6.0のブラウザでは観測されなかった**（実測）。状態読みと集計更新は動くが、Fallback の見た目は制約として記録する。
- ボタンは `<Fragment>` の外に置く。中に置くと Fallback がボタンまで覆う。

### 機能㉑ poll ハートビート

- `<Async poll="3000">` のブロックが3秒ごとに再取得される。`?slow=1` では各907ms、次回は応答後3秒。
- クライアントは `document.hidden` の間、poll を止める。表示中の更新だけを GIF とプローブで確認した。
- キュー値は `Time.current` から決まるデモ用のシミュレーションで、実ジョブではない。

## Patterns（server モード、`/patterns`）

同じ tasks テーブルを「受信箱」として組み直した、実務寄りの3パターン。すべて server mode で、
往復するのは値だけ（検索・並び替えと同じ約束）。

<div><img src="docs/media/patterns-light.png" alt="Patterns (light)" width="49%"/> <img src="docs/media/patterns-dark.png" alt="Patterns (dark)" width="49%"/></div>

### 機能⑧ フィルタチップ（サーバー絞り込み＋件数バッジ）

![チップの絞り込みはサーバーが答える](docs/media/08-chips.gif)

- 優先度（1=低/2=中/3=高）は `tasks.priority` 列。チップの絞り込みは `herb_state("priority")` を
  コントローラーとビューの両方で読む（hub の検索と同じ約束）。
- チップのクリックは 1 属性に 2 state を代入する: `data-herb-set="priority=3 page=1"`。
  空白で区切った token は別 binding として各々実行される（クライアント実装の実測）。
- **往復が起きる条件は「state を読む分岐を作る」こと**: server mode では、分岐の答えが反転したときにだけ
  GET slots が飛び、ヘッダには「分岐の条件が読んでいる state」しか載らない（ブラウザ実測）。
  だからノートは priority の if/elsif 連鎖にして、全遷移でどこかの分岐が反転するようにしてある。
  これがないと、同一要素に `data-herb-action="$refresh"` を合成しても state が載らない。
- 選択中チップは `aria-pressed` の文字列補間。CSS は `[aria-pressed="true"]`。
  **state 比較は literal のみ**（`value.to_s` のような式は ErrorInTemplate）なので、
  チップは4個を literal 展開している。
- 件数バッジは `Task.group(:priority).count`。スカラーとして slots 応答に乗る。

### 機能⑨ もっと見る（キー付き差分で行が増える）

![もっと見るはキー付き差分で行を追加し、読み切ると全件読み込み済みの分岐に差し替わる](docs/media/09-load-more.gif)

- `page` は Integer state。「もっと見る」は `data-herb-increment="page"`＋`data-herb-action="$refresh"`
  （2ページ目→3ページ目は分岐が反転しないので、`$refresh` の合成で往復を保証する）。
  同じ GET slots 往復で `order`/`items` が伸び、クライアントは既存行を動かさず新しい行だけを追加する。
- 「N ページ目を表示中」は `page > 1` の if（else無し）で、ページ state を分岐に読ませる役割も兼ねる。
- 「全部読み込みました」を表示する分岐は **ivar 条件の分岐**（`<% if @remaining > 0 %>`）だ。
  server モードでは state 条件でなくても wire に `branch` 値と分岐の statics が乗り、
  初期 HTML の `<!--herb-branch:N:現在の分岐-->` マーカーと突き合わせて切替が起きる。
- ⑨ のタグは ⑧ のカード内に置いている。読み込みは ⑧ のチップと同じ受信箱で起きる。

### 機能⑩ 詳細連動（行選択→同じアクションが詳細を答える）

![行クリックから行への切替まで、往復は値だけ](docs/media/10-detail.gif)

- 行クリックは `data-herb-set="click->selected_id=<%= task.id %>"`＋`data-herb-action="$refresh"`。
  行から行への切替は `selected_id > 0` の分岐が反転しないので `$refresh` を合成する
  （ヘッダは timer 発火時に組み立てられるので、1 リクエストに新 state が載る）。
- 詳細パネルの条件は `selected_id > 0`（**state 条件でないと往復が発生しない**。ivar 条件は
  wire に乗るだけで steering しない。いずれも実測）。値は全部 `data-herb-name` の名前付きスロットで乗る
  （分岐の statics は初回固定でも、スロットは毎往復差し替わる。ドロワーの文字数と同じ理屈だ）。
- 行のハイライトは `aria-current="<%= task.id == @selected_id %>"` で行う。**loop データとの比較は
  state に書けない**ので、controller 渡しの ivar と比較して、per-item の属性スロットとして往復する。
  キー付き item の中の属性補間が wire に乗ることは実測済み（`aria-current`、prio クラスとも）。
- 選択解除は `data-herb-reset="selected_id"`。消えた行の ID が選択された場合は
  値が空の詳細パネル側（state 条件の答え）になる。消えた行のデータが表示に残ることはない。

## Pricing（server モード、`/pricing`）

SaaS の料金プランを選ぶと見積もりが変わる計算画面。プラン・席数・年払い・優先サポートは
ブラウザ所有の state で、金額の計算はすべて Ruby 側に残す。JavaScript には料金式を書かない。

<div><img src="docs/media/pricing-light.png" alt="Pricing (light)" width="49%"/> <img src="docs/media/pricing-dark.png" alt="Pricing (dark)" width="49%"/></div>

### 機能⑮ サーバー計算の見積もり

![プラン・席数・年払い・サポートの変更で、見積もりが1往復で更新される](docs/media/15-pricing.gif)

- `plan` は state 条件の分岐が反転して1往復する。`seats` / `annual` / `support` は分岐が
  反転しないため、steering 用の非反転条件（`seats > 0`、`annual == true || annual == false`、
  `support == true || support == false`）と `data-herb-action="$refresh"` の合成で1往復させる。
  これらの条件は常に真だが、state を steering ヘッダに載せるために読ませている。
- 内訳の金額は `data-herb-name` の READ slot。ボリューム割引・年払い割引・優先サポートの行は
  分岐の中に置かず、state の表示属性（年払い・サポートは `data-active`、ボリュームは `hidden` の
  presence）で出し分ける。分岐の中のサーバー読みは切替後に branch refetch を1回呼ぶため
  （0.6.0 実測）、金額は分岐の外に置くのが定石だ。
- headless Chromium で、プラン・席数・年払い・サポートの各操作が **1 リクエスト**で
  内訳と合計を更新することを確認済み。ページはリロードされない。
- JavaScript を切ると初期表示のみで、再計算はできない（no-JS の再計算は対象外）。

```erb
<%# herb:state (plan: "team", seats: 5, annual: false, support: false) %>
<p data-herb-name="total"><%= number_to_currency(@total, unit: "¥", precision: 0) %></p>
```

## Settings（client モード、`/settings`）

設定フォームのタブ・依存フィールド・未保存状態を、すべてブラウザ内で扱う。保存はデモで、DB には書かない。
リロードすると初期値に戻る。

<div><img src="docs/media/settings-light.png" alt="Settings (light)" width="49%"/> <img src="docs/media/settings-dark.png" alt="Settings (dark)" width="49%"/></div>

### 機能⑰ タブ・依存フィールド・未保存状態

![タブ・依存フィールド・dirty/save/reset がすべて0往復](docs/media/17-settings.gif)

- 3つのタブは **hidden の presence パネル**だ。`hidden="<%= tab != "profile" %>"` で表示だけを切り替え、
  DOM からは外さない。トップレベルの parked 分岐にすると、分岐内の boolean バインディングと入れ子の分岐が
  初期値で materialize され、`digest: true` の switch が off、頻度フィールドが非表示になった（0.6.0 の実測）。
  パネルを残せば、入力値も switch の見た目もそのまま保たれる。
- 依存フィールドは3組ある。まとめ通知→頻度、公開プロフィール→ハンドル名、年払い→請求書の宛名。
  どれも `hidden` の presence で出し分ける。
- 未保存状態は明示する。パネルの
  `data-herb-set="input->dirty=true saved=false change->dirty=true saved=false"` が、自動バインドされた
  入力・switch の書き込みに合流する。タブ切替はパネルの外なので dirty にならない。
- 保存可否は派生 `can_save: dirty && form_ok`。`form_ok` は `name_ok` / `email_ok` / `bio_ok` / `handle_ok`
  の AND に分け、保存ボタンは `disabled="<%= !can_save %>"` の単一否定だけを読む。
- プランと頻度は `<select>` でなくボタン（literal の `data-herb-set`）。リセット後も `aria-pressed` が
  state から戻る。
- 保存は `dirty=false saved=true` のデモ。リセットは書き込み可能な state だけを初期値へ戻す
  （派生 state と `tab` は含めない）。
- ブラウザプローブで、タブ切替・依存フィールド・dirty/save/reset・タブの往復・リロードのすべてが
  **0 slots リクエスト**であることを確認した。GIF の後半では Billing のプラン切替とリセットも見せている。

## Client Lab（client モード、`/lab`）

この画面の未描画の分岐（タブの裏側・モーダル・hover の表示）は、初回 HTML に `<template data-herb-region>`
として格納済みだ。開閉・切替・カウントはすべてブラウザ内で完結する。`$refresh` だけが意図的にサーバーへ問い合わせ直す手段だ。

<div><img src="docs/media/lab-light.png" alt="Client Lab (light)" width="49%"/> <img src="docs/media/lab-dark.png" alt="Client Lab (dark)" width="49%"/></div>

### 機能④ 分岐の格納とセグメント切替

![タブの切替は往復ゼロ](docs/media/05-client-mode.gif)

- `tab` の両側（すべて / メンション）は、client モードでもサーバーが初回に両方を描画して格納する。
  切替はクライアントが格納済みの分岐を採用するだけだ。メンション側は
  `@notifications.select { |n| n[:kind] == "mention" }` の行データとして別に格納してある。
- `aria-pressed="<%= tab == "all" %>"` は文字列 "true"/"false" の属性補間として出る
  （checked/selected の boolean 属性バインディングとは別物）。client モードでは状態の比較だけだから、
  クライアント側で評価でき、往復はない。CSS は `[aria-pressed="true"]` で引く。

### 機能⑤・⑥ カウンタとコマンドパレット

![カウンタ・hoverプレビュー・⌘Kパレットが往復ゼロ](docs/media/06-palette.gif)

- `data-herb-increment / decrement / reset` でカウンタを操作する。`data-herb-by="2"` を付けると一度に ±2 動く。
- ⌘K（Ctrl+K）またはクリックで開く palette 型モーダル。Esc と backdrop のクリックで閉じる。入力の文字数は即時に表示される。
- ホバーは `data-herb-set="mouseenter->preview=true mouseleave->preview=false"` と `if preview` の分岐で、
  プレビュー pill が 0往復で出る。`data-herb-reset`（引数なし）は「全部戻す」で、全 states を既定値へ戻す。
- 画面のタグは ⑤ がカウンタ、⑥ が palette。GIF は両方を1本にまとめている。

### 機能⑦ switch バインディングと派生状態

![switchと派生のready](docs/media/07-derived.gif)

- `checked="<%= mute %>"` の switch は presence バインディングだ。🔕/🔔 の文言も両方置いて CSS で切り替える（機能②と同じ理屈）。
- `<%# herb:state (draft: "", ready: draft != "") %>` が **派生宣言**だ。`draft` が空でなければ `ready` が真になり、
  文字数表示の即時化と `disabled="<%= !ready %>"` の送信ボタンの有効化がクライアント内で完結する。

### 機能⑪ 多段ウィザード（step状態と派生の有効化）

![入力が済むと派生状態が次へを有効にする。切替は往復ゼロ](docs/media/11-wizard.gif)

- `step`（Integer state）の三つ分岐は `<% if step == 1 %>` の別タグに展開した三ブロック
  （case+when を1タグに詰めると Herb がパース不能になるという教訓の if 版）。
- 「次へ」は `data-herb-increment="step"`。押せるかどうかは派生状態 `name_ok: name != ""` を presence バインドした
  `disabled` で決まる。ステップごとに入力が置ける（未描画のステップの input も格納してある）。
- 完了の分岐は `data-herb-reset="step name email"` で、複数 state を空白で並べて一気に戻せる。

### 機能⑫ 入力バリデーション（length変換＋順序比較＋コンボ派生）

![60字を超えると警告ピルの表示が差し替わり、保存が無効になる](docs/media/12-validate.gif)

- 派生宣言 `over: bio.length > 60` に `.length` 変換と順序比較が書ける。オーバー時は警告ピルの表示が差し替わる。
- 送信の有効化はコンボ派生 `ready_bio: bio != "" && bio.length <= 60` だ。manifest には
  `{"all" => [["bio","","!="], ["bio",60,"<=","length"]]}` として現れる。
- 演算（20 - length など）は不可能（変換は `.length` / `.to_s` のみ）。だから表示は「N/60字」の形。
- textarea は `<textarea><%= bio %></textarea>` の raw_text ではなく **`value="<%= bio %>"` でバインドする**。
  raw_text は textContent しか書かないので、一度でも打つと reset が表示に追従しなくなる（実測）。
  `value=` 形式なら textarea も双方向に結び付けられ、クリアで表示の値まで空になる。

### 機能⑬ 数量ステッパー（行ごとの数量＋カウントfold）

![数量は行ごとに動き、バッジのfoldが即時追従する](docs/media/13-qty.gif)

- `qty` は行ごとの Integer state。減ボタンは `disabled="<%= qty == 0 %>"` で、順序比較の presence バインディングにより
  0 のときは押せなくなる（見た目の即時性は CSS、数値は read スロットという分担は hub と同じ）。
- `<%= in_cart %>` 件の合計は**カウントfold**（`<% if qty > 0 %><% in_cart += 1 %><% end %>`）。
  fold の when に順序比較が書ける。counted state をループの**前**で読むとコンパイルエラー
  （「count is complete 前」）になるので、統計行はリストの後に置く。
- 金額合計は作れない: fold の増分は整数リテラルのみ（`total += price * qty` は不可）。

### 機能⑭ アコーディオン（行ごとの open 状態と hidden の presence バインディング）

![行ごとに独立して開閉する。答えは初回からDOMに載っている](docs/media/14-accordion.gif)

- `open` は行ごとの boolean state。ヘッダーは `data-herb-toggle="open"`。
- **答えのテキストを分岐の中に置かない**: 行ごとの分岐は materialize できても、分岐の中に置いた
  サーバー読みの値は空で届く（0.6.0 の実測。ワイヤは item ごとの `{branch, slots}` を返しているのに、
  クライアントが materialize 済みの item の分岐に値を当てはめられない）。代わりに本文は平常の item part として
  初回から DOM に載せ、`hidden="<%= !open %>"` の presence バインディングで表示を切り替える。マーカーの＋/－は
  静的テキストなので分岐の切替で差し替わる。
- `hidden` は `checked/selected/disabled` に加わる presence の仲間（falsy 読みとして manifest に現れる）。
  CSS は `[hidden] { display: none !important; }` のガードで表示規則に勝たせない。

## UI Kit（client モード、`/ui`）

shadcn/ui のモデル（ソース配布 + トークン + variant API）を ERB で再現した検証キット。9コンポーネントは
Button / Badge / Card / Switch / Stepper / Field / Accordion / Tabs / Dialog。ソースを
`lib/reactionview_ui/` に置き、ジェネレータ（`reactionview_ui:install` / `reactionview_ui:component`）で
`app/views/components/ui/` にコピーして使う。断片は `herb:state` 宣言を内蔵する。ページ側の wiring は不要。
UI Kit のトークンと CSS は `reactionview_ui.css` にまとまり、`app.css` とは別に読み込む。
headless Chromium で操作できるコンポーネントをすべて動かした結果、スロット往復は 0 だった。

![9コンポーネントのデモ。操作はすべて0往復](docs/media/26-ui-kit.gif)

Button / Badge / Card は state を持たず、manifest で `"states": null` になる。Switch は同一断片の2 instance が
occurrence index で独立し、Stepper は行ごとの qty とカウントfold、Field は派生 `ready` / `over`、
Accordion は per-item の `open`、Tabs は literal 比較のパネル切替、Dialog はトリガ + state + 背景を
1断片で持つ。コンポーネントの一覧と実測の詳細は [docs/ui-kit.md](docs/ui-kit.md)。

## 実務検証: サーバー検証フォーム（`/forms`、ナビ外）

標準の `form_with` と 422 の全画面再描画を、client mode のカテゴリ絞り込みと同じページに置いた検証。フォームは `data-herb-into` を使わず、成功はリダイレクト、失敗は 422 の HTML でエラーと入力値を保持する。絞り込みは 0 往復で、入力途中のフォーム値を壊さない。詳細と実測は [docs/forms.md](docs/forms.md)。

<div><img src="docs/media/forms-light.png" alt="サーバー検証フォーム (light)" width="49%"/> <img src="docs/media/forms-dark.png" alt="サーバー検証フォーム (dark)" width="49%"/></div>

![無効な送信は422でエラーと入力値を保持し、修正後の送信は一覧に反映される](docs/media/19-forms.gif)

編集と削除も標準フォームです。編集の失敗は 422 で入力値を保持し、削除は確認ページと `button_to` の DELETE で行います。

![一覧から編集し、422 を直して更新、確認して削除する](docs/media/21-forms-crud.gif)

## 実務検証: 共有 URL の検索（`/catalog`、ナビ外）

検索・カテゴリ・ページを URL に載せ、ブックマーク・共有・戻る・進む・リロードが成立する検索画面。検索とページ送りは標準の GET フォームとリンク、概要の開閉だけを client mode の `compact` state（0往復）にした。URL は Rails、ページ内は ReactionView という分担の実測。詳細は [docs/url-state.md](docs/url-state.md)。

<div><img src="docs/media/catalog-light.png" alt="Talk Catalog (light)" width="49%"/> <img src="docs/media/catalog-dark.png" alt="Talk Catalog (dark)" width="49%"/></div>

![カテゴリとページが URL に載り、概要の開閉だけが 0 往復で動く](docs/media/20-catalog.gif)

## 実務検証: 検証つきウィザード（`/apply`、ナビ外）

3ステップの応募フォーム。各ステップは標準フォームでサーバー検証し、失敗は 422 でエラーと入力値を保持する。下書きはセッションに紐づき、戻る・リロード・no-JS でも同じ状態に戻る。最後の確認で Proposal を作成する。詳細は [docs/wizard.md](docs/wizard.md)。

<div><img src="docs/media/apply-light.png" alt="Apply wizard (light)" width="49%"/> <img src="docs/media/apply-dark.png" alt="Apply wizard (dark)" width="49%"/></div>

![ステップ1の422、ステップ2、確認、送信成功まで](docs/media/22-apply.gif)

## 実務検証: 失敗する送信（`/outbox`、ナビ外）

楽観的追加（`data-herb-into`）の 500 失敗を、`failed` 行・再試行・破棄で扱う検証。`failed` の表示は ERB、再試行/破棄は outbox の JS API を呼ぶ小さなアダプタ。no-JS の失敗は flash alert。詳細は [docs/outbox-failure.md](docs/outbox-failure.md)。

<div><img src="docs/media/outbox-light.png" alt="Outbox failure (light)" width="49%"/> <img src="docs/media/outbox-dark.png" alt="Outbox failure (dark)" width="49%"/></div>

![失敗した行が failed になり、再試行で確定する](docs/media/23-outbox.gif)

## 実務検証: 入れ子スレッド（`/thread`、ナビ外）

投稿と返信を入れ子のキー付きコレクションで描く検証。`$refresh` の slots 応答に nested collection が載り、外側の投稿行を再構築せず内側の返信だけを差分適用できる。返信は標準フォーム。入れ子の outbox は静かな no-op だったため採用しない。詳細は [docs/thread.md](docs/thread.md)。

<div><img src="docs/media/thread-light.png" alt="Thread (light)" width="49%"/> <img src="docs/media/thread-dark.png" alt="Thread (dark)" width="49%"/></div>

![返信を追加し、最新を取得しても外側の投稿は再構築されない](docs/media/24-thread.gif)

## 実務検証: 深いツリー（`/tree`、ナビ外）

4階層のファイルツリー。フォルダの開閉は client mode の per-node state で 0 往復、`最新を取得` の slots 1回で `loaded_at` とツリーのキー付き差分が返る。深さ2以上では、partial の state 共有・state の partial 渡し・同名 state の衝突という3つの制約に当たり、レベル別テンプレートと `open_root` / `open_l2` / `open_l3` で回避した。詳細は [docs/tree.md](docs/tree.md)。

<div><img src="docs/media/tree-light.png" alt="Tree (light)" width="49%"/> <img src="docs/media/tree-dark.png" alt="Tree (dark)" width="49%"/></div>

![レベル1/2/3の開閉は0往復、最新を取得しても開閉状態が残る](docs/media/25-tree.gif)

## 検証の進め方

- **テスト: `bin/rails test`**。controller 14本、model 7本、generator 1本を実行する。
  controller tests は HTML レンダ / `herb_state` による並び替え・絞り込み / 料金計算と READ slot /
  slots 応答の形状（items+order / 分岐 / スカラー混在）/ 201 splice / 422 の HTML と入力値保持 /
  no-JS の POST フォールバック / fold が manifest に現れることを検証する。model tests は下書き・提案・投稿・
  ツリーなどのドメイン、generator test は `reactionview_ui` のコピー生成を見る。テストは What を、
  コードは How を、コミットログは Why を書く約束。
- **フルゲート: `bin/ci`**。`bin/setup --skip-server`、Rubocop、bundler-audit、importmap audit、Brakeman、
  `bin/rails test`、seed の再投入を順に実行する。
- 初期 HTML には `<template data-herb-manifests>` として、クライアントへの命令書が載る
  （`states.declarations` / `reads` / `conditionals` / `presence` / `computed` / `server`）。DevTools で覗くと
  「何が往復せず動くか」が読める。
- dev モードでは右上に Herb バッジが出る。テンプレートタグをわざと壊すと、ファイル名＋行番号付きの
  エラーオーバーレイが出る（各 footer に案内あり）。tests + curl + ブラウザでも説明がつかない局面では、
  `docs/debug-mcp-runbook.md`（debug-mcp の adopt-on-demand 手順）を参照する。
- 0往復/1往復は headless Chromium のプローブで計測する。撮影スクリプトとプローブはリポジトリ外の
  録画環境（`/tmp/opencode/capture`）にあり、アプリの Node 依存にはしない。再実行の手順は AGENTS.md と
  各 docs の実測節に記録している。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/hotwire-comparison.md](docs/hotwire-comparison.md) | Hotwire の役割と ReActionView の置き換えを11の局面で対比する |
| [docs/forms.md](docs/forms.md) | 標準フォームの 422 と client mode 絞り込みの共存 |
| [docs/url-state.md](docs/url-state.md) | 共有 URL の検索。URL は Rails、ページ内は slots |
| [docs/wizard.md](docs/wizard.md) | セッション下書き付きの3ステップフォーム |
| [docs/outbox-failure.md](docs/outbox-failure.md) | 楽観的追加の失敗・再試行・破棄 |
| [docs/thread.md](docs/thread.md) | 入れ子キー付きコレクションの差分 |
| [docs/tree.md](docs/tree.md) | 深さ4のツリーと per-node state の制約 |
| [docs/ui-kit.md](docs/ui-kit.md) | reactionview-ui の9コンポーネントと0往復の実測 |
| [docs/debug-mcp-runbook.md](docs/debug-mcp-runbook.md) | debug-mcp の adopt-on-demand 手順 |

## テンプレートの実測メモ

この検証で判明したエンジンの事実（fold の決まった形、server モードと client モードの制約、slots ワイヤの形、
`<%# herb:state %>` を controller でも宣言する必要性など）は、[AGENTS.md](AGENTS.md) に随時記録している。
テンプレートを改変する前には必ずそこを当たること（境界を意図的に押して壊した記録が多い）。
