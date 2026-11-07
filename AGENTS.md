# AGENTS.md

## 目的

このリポジトリは ReActionView の検証アプリ。Kaigi on Rails 2026（Marco Roth: "Herb in Rails 8.2"）の
主張 — **ERB のみで Phoenix LiveView 的な細粒度リアクティビティ** — を、実用的なアプリ風の
機能別ショーケースで実演・検証している。ReActionView 0.6.0 + herb 0.11.1
（0.11.0 から 0.11.1 への更新は bin/ci 全ゲートで再検証済み。ワイヤ形式の実測メモは変らず通用）。

2画面構成から3画面へ: `Sprint Hub`（`/`, server mode: 検索/ソート/ピン/星/ドロワー/楽観的追加）、
`Patterns`（`/patterns`, server mode: フィルタチップ/もっと見る/詳細連動 — 実務から拾ったパターン集）、
`Client Lab`（`/lab`, client mode: 分岐のparked保管・派生状態・palette・ウィザード/バリデーション/数量/アコーディオン）。
さらに4画面目 `UI Kit`（`/ui`）: shadcn/ui モデルの検証キット reactionview-ui —
ソース配布ジェネレータ + 9コンポーネント、全操作スロット往復0（docs/ui-kit.md）。
5画面目 `Pricing`（`/pricing`）: server mode の SaaS 見積もり。プラン・席数・年払い・サポートの4 state、
サーバー計算、金額は READ slot、表示は state の表示属性（`data-active` / `hidden` の presence）
（docs/hotwire-comparison.md の対比5）。
6画面目 `Settings`（`/settings`）: client mode の設定フォーム。3タブ・依存フィールド・明示 dirty・
デモ保存を、全操作 0 往復で扱う（下の実測メモ）。
7画面目 `Dashboard`（`/dashboard`）: client mode の遅延ダッシュボード。Async 2本・Lazy・Fragment・
poll を1画面に載せ、0.6.0 で動く範囲と動かない範囲を実測して記録する。
ナビ外に実務検証 `/forms`（サーバー検証フォーム）: 標準の `form_with` + 422 の全画面再描画と、
同じページの client mode 絞り込み（0往復）の共存を測る（docs/forms.md）。
ナビ外に実務検証 `/catalog`（共有 URL の検索）: 標準 GET の検索・ページ送りと、client mode の
概要開閉（0往復）の共存を測る（docs/url-state.md）。
ナビ外に実測 `/tree`（深いツリー）: レベル別テンプレートと per-node の open state で、深さ2以上の
開閉が 0 往復になるか、`$refresh` で状態が残るかを測る（docs/tree.md）。

## 作業規約（必ず守る）

- コード: How を表現する
- テストコード: What を表現する
- コミットログ: Why を記録する（コミット単位は作業の区切りごと、経緯が追跡できるように）
- コードコメント: Why not を書く（なぜ別のやり方をしないのかを明示。前提の再説明はしない）
- こまめにコミットする
- 記事、ドキュメント、PR の説明文、コミットメッセージなどの日本語の文章を書いたり直したりするときは、
  常に yomiyasu スキルで推敲する（グローバル導入済み: `~/.config/opencode/skills/yomiyasu`）。
  コードを直したあとの作業の報告には使わなくてかまわない

## ReActionView メモ（調査済み事実）

- 設定は `ReActionView.configure` のブロック引数 `config` を使う。`ReActionView.configuration`
  というアクセサは **存在しない**（bin/rails runner での検証用コードは `ReActionView.config` を見ること）
- `config.slots = true|false|:server|:client`。`true` のとき `default_slot_mode` は `:server`
  （ブラウザ所有の state 変化でもサーバーに問いに行くモード）
- importmap-rails 環境では JS クライアントは gem が自動で pin する。`config/importmap.rb` に手書きは不要
  （`app/javascript/application.js` への `import "reactionview"` のみでよい）
- Node/yarn が無い環境。ビルドステップなし importmap を使う（これは ReActionView の売りとも一致）
- slots リクエストの形: `GET /messages?format=slots` + `Accept: application/vnd.herb.slots+json`
  + `Herb-State: {"<テンプレートパス>": {"<state>": "<値>"}}`。応答は HTML でなく値の JSON
- `herb_state(name, default)` がコントローラ・ビュー両方で使える（`config.slots` 有効時のみ）
- ループ行は `<%# herb:key message.id %>`。無いと行再構築＋コンパイル時ワーニング

## 動作確認コマンド

- サーバー: `bin/rails server`（dev でスロット用開発サーバーが内蔵起動し、アドレスを表示。
  アセットを追加・リネームしたら再起動すること — Propshaft は起動時にロードパスを確定させ、
  実測では旧プロセスが app.css を見失い 500 を返し続けた）
- 設定出力: `bin/rails runner 'c = ReActionView.config; puts [c.intercept_erb, c.slots, c.default_slot_mode, c.dev_server_enabled?].inspect'`
- seed: `bin/rails db:setup`（schema 缶詰後は `bin/rails db:seed`）
- 統合テスト: `bin/rails test`（reactive 振る舞い = HTML レンダ / herb_state による並び替え / slots 応答 / no-JS フォールバック）

## 実測済みのスロット・ワイヤ形式（0.6.0）

- 応答ヘッダ: `content-type: application/vnd.herb.slots+json; charset=utf-8`、`Cache-Control: no-store`
- 本体: `{"template": "...", "version": "...", "occurrence": 0, "slots": {<番号>: {...}}}`
  - 分岐は `{"branch": 0|1|…|null, "statics": "<マークアップ>", "slots": {...}}`
  - コレクションは `{"items": {"<実ID>": {"<パート番号>": "<値>"}}, "order": ["<ID>", …], "statics": "<行テンプレート>"}`
    — React流のキー付き照合で、クライアントは行を再構築せず移動・差し替えする
- `POST …?format=slots` は **201** で新規行のみを返す（楽観的追加の差し替え用）
- `herb:slots server` 時、textarea は `data-herb-slot="N:raw_text"`、補間属性は `…:attribute:name` として分岐外のスロットへ載る
- client mode では未描画ブランチが `<template data-herb-region="app/views/<テンプレート>:<version>">` に
  `<!--herb-branch:<番号>:<現在の分岐>-->` 付きで格納され、`<template data-herb-manifests>` に**クライアントへの命令書**がJSONで載る:
  `states.declarations`（kind/derived/scope）、`reads`、`conditionals`（条件分岐）、`presence`（boolean属性バインディング）、
  `computed`（`.length` 等の変換）、`server`
- `server` マップ（`server.branches` / `server.reads`）: 平常時（GET初期描画・全client-evaluable）は
  serverモード・client mode の**両方**で空。埋まるのは「分岐の各ケースに server-read（任意のRuby/ループデータ）が
  混ざったとき」— client mode でメンション側の分岐に `.select` ループを置いたら `branches` に node_path が列挙された。
  「serverモードで埋まる」説は撤回（モード判別には使えない）

## テストにまつわる実測の教訓

- `response.media_type` は charset を含まない（パラメータは別途）
- スロット/パート番号はテンプレートの変更で**再番号付けされる**。アサートはインデックス番号でなく
  「items を持つスロットを探す」等の形で引くこと
- JSON本文中のstaticsはエスケープされる（`\"`）。文字マッチはpayloadをparseして読む
- fixtureはテストごとに自動ロードされる。生成デフォルト（one/two）が漏れていると比較が形骸化や着火するので、
  fixtureを明示的データで書き換えるのが早い
- test環境では debug span（`data-herb-debug-*`）が付かない（debug_mode = development?）ため、
  マーカー正規表現は開発環境と別形になる

## テンプレートにまつわる実測の教訓

- **`case` + `when` を1つのERBタグに詰めない**: Herb はパース不能として ErrorInTemplate。
  `<% case x %><% when "a" %>…<% when "b" %>…<% else %>…<% end %>` と各々別タグにする
- **コレクションを `<% if @tasks.any? %>` 等の分岐で包むな**: slots応答が items/order 形式ではなく
  分岐の statics として全体が返り、キー付き差分適用が壊れる。コレクションは必ずレベルを保つ
- **行クラスの状態補間（`class="<%= … if done %>"` など）を書かない**: `attribute_interpolation` スロット =
  サーバー読み＝チェックのたびに往復。presence バインディング（`checked`）+ CSS `:has(input:checked)` で即時描画に寄せる
- **カウントfoldの決まった形は3タグ**: `<% if done %><% done_count += 1 %><% end %>` をキー付きitem body内に。
  `done_count += 1 if done`（修飾子if）は fold_increment が1文としてパースできず、
  「client never sees a server-side write」という紛らわしいエラーになる。
  counted state は **ループより前で読むな**（heroの統計文はリスト直下へ移動した）。
  マニフェストには declarations[i].count = {collection, when, by} として現れる
- **aria-pressedはpresenceバインディングでなく文字列補間**: `aria-pressed="<%= tab == "all" %>"` は
  "true"/"false" の文字列属性として出る（checked/selected/disabled の boolean属性バインディングとは別物）。
  client mode では純状態比較なのでクライアント評価＝往復なし。CSSは `[aria-pressed="true"]` で引く
- **serverモードでは行ごとのブラウザ所有statesを条件にした分岐を書くな**: 分岐先がparkedされずクライアントに
  materializeできず → switchBranch失敗 → refetch が追加されるが、steeringにitem状態(done)や
  counted(done_count)は載らないのでサーバー回答が常に行禁化→要求storm。見た目は presence＋CSSで、
  数値はREAD slot（`<%= done_count %>`）で置く。行の文言ピルも同様（両方の文言をDOMに置き
  `:has(input:checked)` で切替）。トップレベルの state 分岐（Pricing の plan / annual）は
  サーバー応答の statics で切り替わり、1往復で済む（実測）
- **POST 201 の応答で適用されるのは collection のspliceのみ**: region級のサーバー読み（`Task.count` 等）は
  GET応答でしか適用されない（検索の往復ではバッジが動くのに、追加直後には動かない — 実測）。
  追加直後は `$refresh`（または次のGET）でheroが追いつく。GIF／レポートではこの手順を見せる
- **create応答のspliceはquery/filter状態を無視して入る**（コントローラーのcreateスコープに
  フィルターが無いため）。検索中に追加すると絞り込まれていない行が差し込まれる
- slots応答の slots 値は**スカラー（数値/真偽/文字列）が混ざる**。Hashと決め打ちしない
  （hero の合計はスカラー、presenceバインディングは真偽値、分岐は Hash{branch, statics, slots}）
- create 応答はコントローラーが絞ったスコープで一式を再計算する。
  「全件の合計」を `@tasks.size` で出すと一瞬 1件表示になるため、合計は `Task.count` のように独立に取る
- `herb_state` をコントローラーから呼ばないと、ビュー側だけ state を読んでいてもフィルターは効かない
 （Toolbarが様になってにもかかわらず、起きた）。ビューとコントローラー両方が設計側物として読む必要がある
- `herb_state` はヘッダJSONの値を**型変換なしで**返す（`Herb-State` の生値）。クライアントは
  宣言kindに対して literal を検査するが、手作りヘッダは任意型を通す。Integer state は
  `Integer(...)` の防御的キャストを挟む（`integer_state` ヘルパーを patterns 参照）

## Patterns 画面で新たに実測した事実（0.6.0 / herb 0.11.1）

- **state 比較は literal のみ**: `aria-pressed="<%= priority == value.to_s %>"` のような
  式との比較は ErrorInTemplate（「The client resolves a comparison by looking the state up」）。
  ループデータとの比較（`task.id == selected_id`）も不可 → コントローラーから ivar
  （`@selected_id`）を渡して ivar 同士で比較し、per-item の属性スロットとして往復させる
- **`data-herb-set` の複数代入**: 属性内の空白区切り token は別 binding として各々実行される。
  `data-herb-set="priority=all page=1"` は 1 クリックで 2 state 動く。`data-herb-reset` の
  複数 state（`palette_open draft`）と同じ形。なお set の1 binding が受け付けるのは
  1 組の `state=value` のみ（カンマ区切りは無視される）
- **literal の型検査**: set の値は宣言kindに対して検査される。integer 宣言に
  `selected_id=<%= task.id %>`（数値に見える文字列）はOK、非数値はクライアントがエラー表示
- **派生宣言のコンボと順序比較**: `ready_bio: bio != "" && bio.length <= 60` は
  `{"all" => [...]}` のコンボ派生として、`over: bio.length > 60` は length変換＋順序比較として
  manifest に現れる。変換テーブルは `.length` / `.size` / `.to_s` のみ（演算は不可）
- **fold の when に順序比較が書ける**: `<% if qty > 0 %><% in_cart += 1 %><% end %>` は
  `count: {when: ["qty", 0, ">"], by: 1}` としてコンパイルされる。truthy 判定（`<% if qty %>`）は
  使わず明示比較が安全
- **presenceバインディングのHTML表現**: `disabled="<%= state %>"` は裸属性＋
  `data-herb-slot="N:boolean_attribute:disabled"` マーカーとして出る。`disabled="false"` という
  値付き文字列は**出ない** → assert は `[disabled]`（属性の有無）で引く。aria-pressed などの
  文字列補間（"true"/"false" が出る）とは別物
- **item内の属性補間は wire に載る**: キー付き item の中の `aria-current="<%= ... %>"` や
  `class="prio prio-<%= task.priority %>"` は per-item parts として応答に乗り、クライアントが
  当てはめる。既存行の内容がサーバー側で変わる場合も同じ経路で追随する
- **ivar 条件分岐は wire に載る**: `<% if @remaining > 0 %>` のような state を使わない条件でも、
  dynamics コンパイラは全 if を conditional として追跡し、応答に `branch` 値と分岐の statics を乗せる。
  初期 HTML には現在の分岐先が `<!--herb-branch:N:x-->` マーカーで載る。クライアントは
  branch 値が変わったときだけ switchBranch（statics は応答から hold して materialize）。
  応答の slots 値は**毎回適用**されるので、分岐の中の値は data-herb-name スロットで乗せるのが定石
  （statics は初回固定でも値は毎往復差し替わる）
- **stale 選択の退避**: `selected_id` が実在しない行を指したままの応答は then 側を空値で返す。
  詳細パネルの条件は `selected_id > 0` ではなく `@selected`（コントローラーで実在確認済み）に
  すると、server 側の分岐選択とクライアントの見た目が常に一致する
- **counted state をループ前で読むな**は再確認された（lab の数量ステッパーで再現）:
  `in_cart` を feature-head で読むと「read before its count is complete」のコンパイルエラー。
  統計行はリストの後に置く
- **アコーディオン（per-item 分岐 + サーバー読みの値）**: 行ごとの `open` 状態＋`data-herb-toggle`、
  本文の分岐先は parked（`<!--herb-branch:46:-->` スロット格納）。分岐の中の `faq[:a]` はサーバー読みなので
  `server.branches` に node_path が列挙され、クライアントの `requestBranchRefetch` 機構が
  分岐 materialize 時に値を取りに行く設計（メンション側と同型）。**ブラウザでの materialize 実確認は
  録画時（Playwright 撮影）に要確認** — manifest/parked/refetch までの実測は済
- **fold で金額合計は作れない**: fold の増分は整数リテラルのみ（`fold_increment` が
  `Prism::IntegerNode` を要求）。`total += price * qty` 系は設計段階で諦める

## Pricing 画面で実測した事実（0.6.0 / herb 0.11.1）

- **`plan` はトップレベルの state 分岐**: 分岐の反転が1往復を運ぶ。応答の statics が
  切り替わり、金額は READ slot で差し替わる。行ごとの分岐とは挙動が違う（上の「行ごと」の注意は
  そのまま）。
- **`seats` / `annual` / `support` は常に真の条件を steering 用に読ませ、`$refresh` で1往復**:
  `seats > 0`、`annual == true || annual == false`、`support == true || support == false` は
  値が変わっても分岐が反転しない。`data-herb-action="$refresh"` を同じ要素に合成し、ヘッダの state を
  1リクエストに載せる。条件を消すと state が steering に載らず、合計が古いままになる。
- **可視の金額と選択表示は正規化した ivar、生の state は hidden の steering 条件と表示属性**:
  範囲外の席数や文字列 boolean を表示に漏らさないため、金額と選択表示は `@plan_key` / `@seats` /
  `@annual` / `@support` で作り、生の state は hidden の条件分岐と `data-active` / `hidden` に読ませる。
  手作りヘッダの 999 席や "false" が画面に出ない（テスト済み）。可視値はサーバー読みなので、
  往復後に更新される。
- **`hidden` を ivar で書くと表示が追随しない**: `hidden="<%= !@annual %>"` は boolean attribute の
  サーバー読みになり、クライアントは値を書き換えない。state の `data-active="<%= annual %>"` と
  CSS `[data-active="false"]` にすると、state の変化で行が追随する（Pricing の GIF 撮影で発見）。
- **分岐の中のサーバー読みは branch refetch をもう1回呼ぶ**: `annual_discount` / `support_fee` /
  `volume_discount` を分岐の中に置くと、分岐の切替後に値スロットを取りに行き、年払い・サポートの
  切替が2リクエストになった（headless Chromium 実測）。金額を分岐の外へ出し、行の表示だけ
  state の表示属性（年払い・サポートは `data-active`、ボリュームは `hidden` の presence）で
  切り替えると1リクエストに収まる。分岐は static な文言の切替に使う。
- **サポートのチェックボックスは2リクエスト**: `checked` のバインドは `input` と `change` の両方で
  state を書くため、条件分岐の反転と合わせて2回飛んだ。`data-herb-set` の2ボタン（`support=false` /
  `support=true`）＋`$refresh` に変えると1回になる。
- **年払いの条件を2つに分けると2リクエスト**: 小計ラベルと割引ノートが別々に annual を読むと、
  それぞれが refetch を予約して2回飛ぶ。可視の小計ラベルは `@annual` の三項で出し分け、
  steering 用の常真条件を1つだけ置き、`$refresh` を合成すると1回になる。
- **ボリューム割引の10席しきい値は分岐でなく presence**: `hidden="<%= seats < 10 %>"` と
  `hidden="<%= seats >= 10 %>"` で行を出し分け、金額は分岐外の READ slot。`seats > 0` の常真条件が
  steering を担い、`$refresh` が往復を運ぶ。しきい値の分岐を置くと9→10で2リクエストになる。
- **Boolean / Integer の防御的キャスト**: `boolean_state` は `true` / `"true"` だけを真にし、
  `integer_state` は `Integer(...)` でキャストする。PricingController は席数を 1..50 に clamp する。
- **no-JS の再計算は対象外**: state の初期値が literal なので、URL パラメータからの種付けは別設計。
  初期表示だけは通常の HTML として読める。
- **1操作1リクエストをブラウザで確認**: plan / seats / annual / support の各操作で `?format=slots` が
  1回、document request は1回のまま、URL は `/pricing` のまま（headless Chromium）。

## Hub ピン/星で実測した事実（0.6.0 / herb 0.11.1）

- **per-row `pinned` + `pinned_count` fold**: 行の星は presence バインディング
  （`checked="<%= pinned %>"`）、行の見た目は CSS `:has(.task-pin input:checked)`。カウントは
  リスト直後で読み、星の切替は **0 slots リクエスト**（headless Chromium で確認）。
- **done の `:has(input:checked)` は `.task-check` にスコープ**: ピンのチェックボックスを足すと、
  スコープしない既存ルールが pin にも当たり、done の取り消し線/背景が星で発火する。
- **done と pin は独立**: ピンを2つ点けても done_count は動かず、done を1つ点けても
  pinned_count は 2 のまま（プローブで確認）。リロードで pin は消える（クライアント所有）。
- **Hub と Settings の静止画/GIF は日本語フォントスタック**: `app.css` の `"Hiragino Sans"` /
  `"Noto Sans CJK JP"` / Meiryo / `"Yu Gothic"` を先に置き、キャプチャ側で `system-ui` だけの
  fallback に戻さない。

## Settings 画面で実測した事実（0.6.0 / herb 0.11.1）

- **トップレベルの parked タブ分岐は、分岐内の boolean バインディングと入れ子の分岐を初期値で
  materialize する**: Settings のタブを `<% if tab == ... %>` で組むと、Notifications タブを開いても
  `digest: true` の switch が unchecked、`if digest` の頻度フィールドが false 側で出た（headless Chromium）。
  `hidden="<%= tab != ... %>"` の3パネルを常に DOM に置くと、switch の見た目も入力値も正しく保たれ、
  タブ切替は 0 slots リクエストになる。依存フィールドも同じ `hidden` の presence で出し分ける。
- **パネル単位の input/change ラッパーで dirty を合成できる**: パネルの
  `data-herb-set="input->dirty=true saved=false change->dirty=true saved=false"` は、
  自動バインドされた value / checked の書き込みと同居する。switch だけを切り替えても dirty が立ち、
  保存が有効になることをプローブで確認した。タブ切替はラッパーの外なので dirty にならない。
- **`can_save: dirty && form_ok` を分割する**: `form_ok` は `name_ok` / `email_ok` / `bio_ok` / `handle_ok`
  の AND、`handle_ok` は `!public_profile || handle != ""` の OR。保存ボタンは
  `disabled="<%= !can_save %>"` の単一否定だけを読む。空の表示名・公開プロフィールで空のハンドル・
  121字の自己紹介が、それぞれ保存を無効にすることをプローブで確認した。
- **プランと頻度は literal set のボタン**: `data-herb-set="frequency=daily dirty=true saved=false"` は
  空白区切りの別 binding として1クリックで両方動く。`data-herb-reset` の後も `aria-pressed` が
  state から戻る（Team と毎週に戻ることをプローブで確認）。`<select>` は使わない — リセット後の
  選択表示を state の読みで保証するため。
- **保存はデモ**: `dirty=false saved=true` にするだけで、DB には書かない。リセットは書き込み可能な
  state だけを初期値へ戻す（派生 state と `tab` は含めない）。リロードで全 state が初期値に戻る。
  タブ切替・依存フィールド・dirty/save/reset・タブの往復・リロードは、すべて 0 slots リクエスト
  （`/tmp/opencode/capture/settings-probe.js`）。
- **6リンクナビに合わせて既存メディアを撮り直した**: Settings をグローバルナビに足したため、
  Hub / Patterns / Client Lab / Pricing の stills と Hub の 03 / 04 GIF を再撮影した。
  Settings の静止画/GIF は日本語フォントスタックで撮り、CDP の `CSS.getPlatformFontsForNode` で
  実フォントが `Noto Sans CJK JP` であることを確認した。

## Dashboard 画面で実測した事実（0.6.0 / herb 0.11.1）

- **`<Async>` のブロック内容は inline で書く**: ブロック応答は partial の statics を運ばず、初期ページの
  `data-herb-dependencies` も空になるため、`render` した partial は描画されない（実測）。サマリーと
  ハートビートは inline にした。`<Async>` はマウント直後に `Herb-Block` 付きの slots 要求を送る。
- **`<Lazy>` は初期表示の位置では block 1 で内容が届き、下段では 0**: 初期 viewport 内なら block 1
  （slow 2703ms / fast 6ms）で Fallback の「読み込み中…」と最新3件が本文に置き換わる。カードを
  初期 viewport の外に置くと、スクロールしても slots 要求は0で Fallback のまま（0.6.0 の配置依存ギャップ）。
  カードは初期表示の位置に置く。Lazy の中のコレクションはブロック応答で `items` が空になるため、
  明示的な行で描画する。
- **`<Fragment>` の Fallback は観測されなかった**: `focus: focus`、`on="focus"`、`server.reads` は
  manifest に載り、focus 変更は slots 1回（910ms）で集計を 10→3 に更新する。ただし Fallback は
  表示されない（実測）。状態読みと集計更新は動くが、Fallback の見た目は制約として扱う。
- **`poll` は 3秒間隔**: `<Async poll="3000">` のブロックが応答後3秒で再要求される。`?slow=1` では
  各907ms、実効約3.9秒。クライアントは `document.hidden` の間、poll を止める（実装済み）。
- **`?slow=1` は slots だけを900ms遅らせる**: `slow_slots` を1リクエスト1回にメモ化する。初回HTMLは
  約30ms、Async 2本は 907ms / 1812ms（サーバーが直列）、focus 910ms、poll 907ms、Lazy は
  初期表示で2703ms（直列）/ 下段は0。`slow=0` は Async 11/13ms、focus 8ms、Lazy 6ms。
- **7リンクナビは 800px / 1000px で1行**: `@media (max-width: 56rem)` で header の padding、
  nav の gap、link の padding / font-size を詰める。プローブで link の `top` が1種類であることを確認。
  Hub / Patterns / Client Lab / Pricing / Settings の stills、Hub 03 / 04、`ui-dialog.png` を
  7リンクで撮り直した。Dashboard の stills / GIF も日本語フォントで撮り、CDP で
  `Noto Sans CJK JP` を確認した。

## Forms 画面で実測した事実（0.6.0 / herb 0.11.1）

- **`data-herb-into` の outbox は 422 の本文を適用しない**: クライアントは `!response.ok` で
  `SlotsRequestError` を投げ、outbox の `fail()` は楽観行に `failed` を立てるだけ。送信は
  `preventDefault` 済みなのでブラウザも遷移せず、`render :new, status: :unprocessable_entity` の
  HTML は画面に出ない。サーバー検証が主役のフォームは outbox に載せない。
- **サーバー検証フォームは `data-herb-into` なしの `form_with`**: 成功は 302、失敗は 422 の
  `text/html` 全画面再描画。エラー要約・項目別エラー・入力値（email / title / abstract）が残る。
  `/forms` の統合テストで固定した。
- **`html: { novalidate: true }` が必要**: `form.email_field` の `type=email` はブラウザが送信前に
  形式を検証するため、`not-an-email` では 422 のリクエスト自体が飛ばない（ブラウザプローブで発見）。
  サーバーを唯一の検証者にするため、ネイティブ検証は切る。
- **`POST ?format=slots` の 422 は slots 本文で返る**: status 422、media type
  `application/vnd.herb.slots+json`、本文は slots payload。クライアントは `!response.ok` で捨てる。
  アプリのフォームは slots を送らない。境界は統合テストで記録した。
- **client mode の絞り込みは同じページのフォーム値を壊さない**: `filter_category` の4チップは
  slots 0。フォームの値は server-read なので、絞り込みでサーバーに問いに行かず上書きもされない。
  422 の全画面再描画後は `filter_category` が `"all"` に戻る（仕様）。
- **`hidden` の `&&` コンボは presence としてコンパイルされる**: 3セクションの
  `filter_category != "all" && filter_category != "<category>"` は `states.presence` に3つ載り、
  `states.declarations` は `filter_category` 1つ。チップの `aria-pressed` は state 比較。
- **`filter_category` の4 literal 以外はサポート外**: `HerbRuntime.state.set` で `unknown` を直接入れると
  0.6.0 の refetch が走り、表示が一時的に不整合になる（UI は生成しない）。
- **テスト環境の media type**: 422 の HTML は `text/html`、slots の 422 は
  `application/vnd.herb.slots+json`。`response.media_type` で比較する。
- **`/forms` はナビ外**: 8リンク目にはしない。Patterns の footer と README / docs からリンクする。
- **編集・削除も標準フォーム**: 編集は `_form` パーシャル + `form_path(@proposal)` + `_method=patch`。更新失敗は 422 の HTML でエラーと入力値を保持。削除は `GET /forms/:id/delete` の確認ページ + `button_to` の DELETE。`button_to` は Rails 8 で `<button type="submit">` を出す。一覧・編集・確認・更新・削除で slots 0、no-JS も同じ経路（プローブ: document 10）。メディアは `21-forms-crud.gif`、`19-forms.gif` と stills を再撮影。
- **メディア**: `forms-light.png` / `forms-dark.png`（fullPage @2x）と `19-forms.gif`（無効送信 → 422 → 修正 → 成功、5フレーム）。クリップは `.forms-layout` の初期 box を固定し、422 のエラー要約が入る高さを先に測ってから撮る（実測 919px）。全フレームの寸法一致を assert。日本語フォントは CDP で `Noto Sans CJK JP` を確認した。

## Catalog 画面で実測した事実（0.6.0 / herb 0.11.1）

- **URL 状態は標準 GET**: `q` / `category` / `page` をサーバーが読み、検索・ページ送りは document GET。`/catalog` の初期・概要開閉・検索・カテゴリ・ページで slots 0（headless Chromium、document GET 6）。
- **既定値は 302 しない**: `category=all` / `page=1` は 200。不明カテゴリ、非整数/範囲外ページだけ、正規 URL へ 302。不明カテゴリは `all` として検索してから寄せる。
- **検索は `%` / `_` / `\` をエスケープ**: `q=%` や `q=_` が全件に広がらないことをテストで固定。
- **`compact` の 0.6.0 ギャップ**: サーバー描画の `@talks.each` 内に置いた `hidden="<%= compact %>"` の presence は最後の1件にしか当たらなかった。概要は CSS `.catalog:has(.catalog-compact input:checked) .catalog-abstract { display: none; }` で閉じ、checkbox の `checked` は state の presence として残す。0 slots、URL 不変。
- **マニフェストの presence は1つ**: `compact` の宣言、checkbox の presence 1つ。コレクション内の presence は1エントリに畳まれる。
- **no-JS**: 検索フォーム・ページリンクは動き、概要は既定で見える。チェックボックスは state を持たないが CSS は効く。
- **bfcache**: ページ2から戻ると `compact` のチェックが復元された（GIF の最後のフレーム）。新規 GET/リロードでは既定に戻る。
- **`form.submit` は `commit=検索` を URL に足す**: 検索ボタンは名前なし `<button type="submit">` にする。共有 URL 行は `request.fullpath` で、実際のリクエストを見せる。
- **空の pagination ラッパー**: `if @pages > 1` が false でも、client mode の ivar 条件で空の `<nav class="pagination">` が残る。テストは `.pagination a` を見る。
- **seed**: rails 6 / frontend 3 / infra 3。rails は2ページで `?category=rails&page=2` が実在。
- **メディア**: `catalog-light/dark.png` と `20-catalog.gif`（初期 → rails → compact → page 2 → back）。日本語フォントとフレーム寸法を確認。
- **ナビ外**: Patterns footer、README、docs からリンクする。

## Wizard 画面で実測した事実（0.6.0 / herb 0.11.1）

- **ステップは `?step=` の GET/PATCH**: 1..3 に clamp。`ApplicationDraft` の仮想 `step` でステップ別 validation。無効は 422 の HTML で同じステップに戻る。
- **下書きはセッション**: `session[:application_draft_id]`。URL に id は出さない。2セッションは別の下書き。
- **最後はトランザクション**: `Proposal.create!` + 下書き削除 + セッション削除 → `/forms` に flash。
- **飛ばし URL は最後の検証で弾く**: `?step=3` が空なら 422、Proposal は作らない。
- **slots 0 / no-JS**: プローブは document 12、全ステップで slots 0。no-JS でも 3ステップが動く。
- **テスト環境の `aria-current`**: ステップインジケータは明示的な静的な `<li aria-current="step">` にする。コレクション内の動的属性はテスト環境で slot 化され、属性が落ちた（ブラウザでは動く）。テスト環境とブラウザの差として記録。
- **メディア**: `apply-light/dark.png` と `22-apply.gif`（ステップ1 → 422 → ステップ2 → 確認 → 成功）。`/forms` のメディアは変えない。
- **ナビ外**: Patterns footer、README、docs からリンク。

## Outbox 画面で実測した事実（0.6.0 / herb 0.11.1）

- **500 は failed**: outbox は `!response.ok` で `failed` を立てる。楽観行は pending → failed になり、`hidden` の presence で失敗ピルと操作が出る。`head :internal_server_error` で確認。
- **retry/discard は JS API**: `HerbRuntime.outbox.retry/discard` しかなく、属性からは呼べない。`app/javascript/outbox_retry.js` の小さなアダプタが `data-outbox-retry` / `data-outbox-discard` を拾う。runtime 以外の最初のアプリ JS。
- **one-shot の失敗**: `session[:outbox_failed_once]`。最初の slots POST は 500、同じ FormData の再試行は 201。no-JS の失敗は flash alert。
- **楽観行の title は `data-herb-name` が要る**: 無いと outbox の `text: true` がタイトルを埋められず、空の行になる。ビューで `data-herb-name="title"` を付ける。
- **`data-herb-into` の属性**: `data: { "herb-into" => "submissions" }` と直接指定する。`data: { herb: { into: ... } }` では属性が出なかった（テストで確認）。
- **no-JS**: fail_once の HTML POST は redirect + alert。レイアウトに `alert` の flash を追加した。
- **プローブ**: failed/retry/discard/noJS、slots 3、documents 1。
- **メディア**: `outbox-light/dark.png` と `23-outbox.gif`（失敗 → failed → 再試行 → 成功）。`/forms` / `/apply` のメディアは変えない。
- **ナビ外**: Patterns footer、README、docs からリンク。

## Thread 画面で実測した事実（0.6.0 / herb 0.11.1）

- **入れ子の `herb:key` は wire に載る**: 外側の collection item のパートに、内側の collection が `items` / `order` / `statics` として入る。`$refresh` の slots 応答で確認。
- **クライアントは外側の行を保つ**: `$refresh` の前後で外側の `.thread-post` に付けた `data-probe-preserved` が残り、内側の返信だけが差分適用された（プローブ: `outerPreserved: "yes"`、`refreshSlots: 1`）。
- **入れ子の outbox は no-op**: `data-herb-into="replies"` を付けた返信フォームは、返信を追加せず、ページエラーも出なかった。本実装は標準フォーム + 全画面。
- **返信は標準フォーム**: POST → redirect + flash。no-JS でも追加できる。
- **返信数はサーバー読み**: `post.replies.size`（`includes`）。nested の count fold は未検証。
- **`data-herb-name="replies"` は重複**: 今回の `$refresh` は nested の位置で解決されたが、outbox の名前解決には使えない。
- **メディア**: `thread-light/dark.png` と `24-thread.gif`（返信 → 最新を取得 → 入れ子の差分）。既存メディアは変えない。
- **ナビ外**: Patterns footer、README、docs からリンク。

## Tree 画面で実測した事実（0.6.0 / herb 0.11.1）

- **再帰 partial では per-node state が成立しない**。3つの制約が重なる:
  - partial に置いた `herb:state` は、その partial の全インスタンスで共有される。`_folder` の先頭に `open` を宣言して再帰させると、`views` をクリックしても `app` が閉じた。
  - per-item state を partial のローカルとして渡せない。`render "folder", open: open` は `computes with the state open, which lives on an item. The server cannot be asked for an item's answer yet` で `ActionView::SyntaxErrorInTemplate`。
  - 同名 state はテンプレートをまたいで衝突する。`open` を root / level2 / level3 で宣言すると、どのトグルも root の state を動かした。
- **採用形はレベル別テンプレート**。`index.html.erb`（root）/ `_level2.html.erb` / `_level3.html.erb` / `_file.html.erb` に分け、`herb:key` と `herb:state (open_root / open_l2 / open_l3)` を各ループで宣言する。state を使うボタンと `hidden` も同じテンプレートに置き、partial には渡さない。子の `<ul>` は `if node.kind == "folder"` の外に置く（コレクションを分岐で包まない）。4階層で止まる。
- **0往復**: レベル1/2/3の開閉・再開はすべて 0 slots。状態は独立（`trees` を閉じても `tasks`、`views` を閉じても `models` は開いたまま）。
- **`$refresh`**: slots 1回。`loaded_at` が更新され、閉じていた `trees` は閉じたまま（`refreshKeptState: true`）。`child.kind` の分岐は行だけなので branch refetch は増えない。
- **テスト環境の `aria-expanded`**: コレクション内の動的属性で、`data-herb-slot="…:attribute:aria-expanded"` のマーカーが付く。初期値はテスト環境でも出るので統合テストで assert し、開閉後の追随はブラウザプローブで確認する。`assert_select` は parked template の中のボタンも数えるため、トグル数は `.tree-root` にスコープする。
- **no-JS**: 初期 HTML は全開で読める。開閉は動かない。
- **データ**: `TreeNode` の自己参照 + `@children_by_parent`。seed は20ノード / 8フォルダ / 12ファイル、fixture は10ノード / 4階層。
- **メディア**: `tree-light/dark.png` と `25-tree.gif`（レベル1/2/3の開閉 → 最新を取得、6フレーム、clip 784x928、`Noto Sans CJK JP`）。既存メディアは変えない。
- **ナビ外**: Patterns footer、README、docs からリンク。

## ブラウザ実測（headless Chromium・録画環境）で確定した事実

録画のために Playwright + Chromium をリポジトリ外（`/tmp/opencode/capture`）に導入して実測した。
ツールはリポジトリに入れない（「Node/yarn を導入しない」はアプリの前提で、録画道具は別物）。

- **server mode の基本の往復トリガは「state条件分岐の答えの切替」**。state を書いても、
  その state を読む分岐の答えが反転しない限り GET slots は飛ばない（ソートの select 単体は
  リクエスト0で実測。hub の検索が動くのはノートの「全件表示↔絞り込み中」反転がトリガだから）。
  `$refresh` を合成した操作は、分岐が反転しなくても1回飛ぶ（Pricing の席数・年払い・サポート）。
  さらに**連続タイピングで分岐が反転しない間は行が古いまま**（ノートの文字だけ client 評価で更新され、
  行は初回の絞り込み結果で止まる — 実測）
- **steering ヘッダ（Herb-State）に載る state も「分岐の条件が読んでいる state」に限る**
  （クライアントの `steering()` が conditionals + server.reads から収集。server-mode ページの
  `server.reads` は常に空）。**だから往復させたい state は、必ずどこかの state 条件分岐に読ませる**。
  Patterns 画面では ① ノートを priority の if/elsif 連鎖に（全遷移でどこかの分岐が反転）②
  ページインジケータを `page > 1` の if に ③ 詳細の条件を `selected_id > 0` に、の3本で賄う。
  Pricing の `seats > 0`、`annual == true || annual == false`、`support == true || support == false` は、
  常に真の条件を steering に載せる例（分岐は反転しない）
- **反転しない反復操作（行→行、2→3ページ目、Pricing の席数・年払い・サポート）は
  `data-herb-action="$refresh"` を合成する**。
  同一要素に action と set が併置できる。action が先に評価されて `request(0)` を予約するが、
  実際のヘッダは timer 発火時に組み立てられるので、同 dispatch 中に書いた state が載る（1リクエストに合流）
- **per-item 分岐の実測**: 静的テキスト（＋/－マーカー）は materialize されるが、
  **分岐の中に置いたサーバー読みの値は空で届く**。ワイヤ自体は完全（応答は item ごとに
  `{branch: 0, slots: {"47": "答え"}}` を返している）で、refetch も発火する — クライアントが
  materialize 済みの item の分岐に値を当てはめられていないだけ。0.6.0 のギャップ
- **対処パターン: 答えを分岐の中に置かず presence バインディングで表示を切り替える**。`hidden="<%= !open %>"`
  は falsy 読みの presence としてコンパイルされ（manifest: `["open", nil, "falsy"]`）、
  答えは平常の item part として初回から DOM に乗る。`checked/selected/disabled` に加えて
  `hidden` も presence の仲間。CSS には `[hidden] { display: none !important; }` のガードを足す
- **textarea は raw_text ではなく `value="<%= state %>"` でバインドする**。raw_text の適用は
  `textContent` 書き込みのみで、ユーザーが一度でも打つと表示値（`value` プロパティ）と乖離し、
  reset しても表示が空にならない（hint は「0 文字」なのに中身が残る — 機能⑦でも発生していた実測）。
  `value=` 形式なら BINDABLE_ELEMENTS（textarea 第一次級）として双方向に結び付けられ、reset が表示まで追従する
- **録画の細部**: 要素クリップの高さがビューポートを超えると stitch され、sticky ヘッダが
  画像の途中に混入する。GIF はクリップが収まる高さのビューポートで撮る（patterns は
  split が横並びになる 1000px 幅も必要 — 832px 未満はメディアクエリで縦積みになる）。
  **要素の高さがフレームごとに変わるとフレーム寸法も変わる**: Settings の `.settings-layout` は
  Profile 456px / Notifications 234px で、要素スクリーンショットの GIF に前フレームの残像と
  保存バーの二重写りが出た。初期レイアウトの bounding box を固定 clip にして撮り、
  全フレームの寸法一致を assert する（`settings-capture.js`）

## reactionview-ui キットで実測した事実（0.6.0 / herb 0.11.1）

shadcn/ui モデル（ソース配布+トークン+variant API）を ERB で再現する検証。ソースは
`lib/reactionview_ui/`、導入は `reactionview_ui:install` / `reactionview_ui:component`（copy_file
で運ぶ — Thor の `template` は herb ディレクティブを評価して壊す）。docs/ui-kit.md に全文。

- **`herb:state` はパーシャル内でも manifest に出る**: パーシャルごとに
  `<template data-herb-manifests>` にエントリが増える（キーは `テンプレートパス:バージョンハッシュ`）。
  トップレベル state の scope は文字列 `"region"`、ループ内は数値 0。shadcn の「コンポーネントが
  内部stateを持つ」相当が断片単位で成立し、ページ側 wiring は不要
- 静的コンポーネント（state無し）は `"states": null` にコンパイルされる = ワイヤ不参加
- **同一パーシャルの複数 instance は occurrence index で独立**: region は
  `<!--herb-region:...:0-->` / `:1` とコメントマーカーで区切られ、2個の switch の state は
  別インスタンス（ブラウザ実測 [true,false]）
- **test環境の client mode は region をコメントマーカーで出す**: `<template data-herb-region>`
  は dev のみ（debug span と同じ env 差分）。test のアサートはコメントマーカーで引く
- **パーシャル内の分岐は materialize されない（0.6.0 最大のギャップ）**: client mode でも分岐先は
  parked されない（manifest の `fragments: {}`、region テンプレート自体が出ない）。set/toggle は
  サーバー refetch にフォールバックするが、応答の分岐スロットは `{"branch": null}` で statics 空丸 —
  per-item 分岐ギャップの拡大版で、トップレベル条件分岐でも同じ
  → **パーシャルでは分岐でなく presence（hidden）+ CSS で切替する**。そうすれば全操作 0 往復
- **パーシャル内の render-with-block は slots 再レンダで TypeError**（"no implicit conversion of
  Hash into String"、GET 初回描画は成功するので発見が遅れる）→ 本文は `content:` ローカルで渡す
- カウントfoldはパーシャル内でも動く: `in_cart: 0` をパーシャル先頭で宣言、分岐でなく
  `<% if qty > 0 %><% in_cart += 1 %><% end %>` の3タグ形、統計読みはリスト直後
- equality の presence バインディング（`hidden="<%= tab == "activity" %>"`）はコンパイルされクライアント評価
  される — 「パネルの切替」も分岐なしで書ける（stepper の `disabled="<%= qty == 0 %>"` と同型）
- ブラウザ実測（`/tmp/opencode/capture/ui-probe.js`）: 9コンポーネント全操作で
  **slot 往復 0**。herb dev tools の浮きメニューがポインタを吸うので、プローブは
  `[class*="herb-dev-tools"]` への恒久CSS + `force: true` クリックで回避

## README・メディア整合（2026-11-07）

- **機能番号は画面タグを正とした**。① server reads / ② 細粒度更新＋楽観的追加（ピン/星は⑯）/ ③ ドロワーと
  フォームのバインディング（window句を含む）/ ④ Lab の分岐格納 / ⑤ カウンタ / ⑥ パレット（hover を含む）/
  ⑦ switch と派生 / ⑧ チップ / ⑨ もっと見る / ⑩ 詳細 / ⑪ ウィザード / ⑫ バリデーション / ⑬ 数量 / ⑭ アコーディオン /
  ⑮ Pricing / ⑯ ピン・星（②のリスト内）/ ⑰ Settings / ⑱〜㉑ Dashboard。README の並びは画面順で、番号は画面タグに対応する。
- **01-server-reads.gif は行が見える**。`load-more` で2行に絞り、`.feature-grid` の固定 clip（784x800 CSS）で
  検索→新しい順→古い順→クリアを撮る。`02-row-state.gif` は②のタグに⑯を併記し、ピン/星も同じクリップで見せる。
- **03-optimistic-add.gif は同期まで撮る**。追加後の hero は10のままで、🔄同期で11になる。検索中に追加した行は
  201 splice で入り、同期で検索結果に戻る。POST 201 の応答は region の `Task.count` を適用しない（実測どおり）。
- **04-window-clauses.gif はキー操作をオーバーレイ表示**する。`Ctrl+B で開く` → `Esc で閉じる` → `閉じた（Esc）`。
- **06-palette.gif は⑤⑥を1本にまとめた**。カウンタ +2 → リセット → hover プレビュー → ⌘K → Esc。0 slots。
- **09-load-more.gif は固定 clip 916x2362（2x）**。カードが伸びるため locator screenshot では「全部読み込みました」が
  切れる。2ページ目→全件読み込み済みの2フレームにした。
- **17-settings.gif は8フレーム**。Billing の Business 選択 → Profile の名前変更 → 保存 → リセットまで撮る。
- **18-dashboard.gif は⑱〜㉑のタグ入り**。Async / Lazy / Fragment / poll の4タグが画面に出る。
- **26-ui-kit.gif を追加**。`/ui` の Switch×2、Field、Stepper、Accordion、Tabs、Dialog を1本にし、全操作 0 slots。
- README の前提は Ruby 4.0.9 / Rails 8.1.4 / SQLite。`bin/setup --skip-server`、`bin/ci`、`bin/rails test`
  （controller 14 / model 7 / generator 1）を明記した。
- README のスタイル説明は **`app.css` + `reactionview_ui.css` の2枚**に直した。Rails 標準の `turbo-rails` /
  `stimulus-rails` は Gemfile と importmap に残るが、`application.js` から import していない。
- **Hub の no-JS は controller の POST フォールバックだけ**。初期 HTML にドロワーのフォームは無く、
  `data-herb-toggle` も JS 前提なので、ブラウザで JS を切ると作成フォームには到達しない。
  no-JS のフォーム操作は `/forms` などの標準フォームで確認する。
- 録画スクリプトはリポジトリ外（`/tmp/opencode/capture`）。`hub-capture.js` / `pin-capture.js` /
  `settings-capture.js` / `dashboard-capture.js` / `patterns-09-capture.js` / `lab-06-capture.js` /
  `ui-kit-capture.js` が今回の再撮影に対応する。

## 調査ツール

- debug-mcp（Kaigi on Rails 2026・riraさんの講演）は **adopt-on-demand**: 実行時状態に依存するバグで
  tests+curl+ブラウザで説明がつかない局面で導入する。手順は `docs/debug-mcp-runbook.md`
  （stdio MCP・opencode.json に local 登録・`RUBY_DEBUG_OPEN=true bin/rails server` で attach）

## やらないこと（Why not 付き）

- Rails 8.2 / `config.action_view.html_erb_implementation` には手を出さない
  → rubygems 上の最新リリースは 8.1.4 であり、8.1 では intercept_erb が Herb 経由化の正攻法だから
- Node/yarn の導入をしない → importmap で完結する。追加ツールはこの検証の主題と無関係な摩擦を増やすだけ
- Tailwind / PostCSS / あらゆるビルドパイプラインをスタイルで導入しない
  → ビルドステップゼロがデモの前提。app.css に素のCSS（デザイントークン含む）で書く
- 行クラスのstate補間（`class="<%= … if done %>"` のようなもの）を戻さない
  → 属性補間はサーバー読みスロットになりチェックごとに往復する。
  見た目の状態は presence バインディング（`checked`）+ CSS `:has(input:checked)` で即時追随させる
- 金額計算をクライアントに写さない → fold は整数リテラルの加算のみで、掛け算・税率・割引を表現できない。
  料金式を二重管理せず、サーバーの READ slot に置く（Pricing の実装）
- モーダルフォームを `board_path` にPOSTさせない → board はGETルートのみ。CRUDの入口は
  `tasks_path`（正攻法の分離）。`data-herb-into` は差し込み先コレクションの名前指定に過ぎない
