# Settings 画面（6画面目）設計

- 日付: 2026-10-28
- 状態: 設計案（承認待ち）
- 対象: `/settings`
- 前提: ReActionView 0.6.0 / herb 0.11.1

## 目的

実務で定番の設定画面を client mode で作る。プロフィール・通知・請求の3タブ、依存フィールド、未保存状態、保存／リセットを、すべてブラウザ内で完結させる。保存は**デモ**で、DB には書かない（リロードで初期値に戻る）。

## なぜ Settings か

Client Lab はウィジェット単位の client mode、Pricing は server mode の計算画面だった。Settings は「画面全体がフォーム」の client mode で、タブ・依存フィールド・dirty 状態を1画面で見せられる。Hotwire なら Stimulus のフォームコントローラが担う領域を、state と presence だけで組む。

## 画面

- 6画面目。`/settings` を追加し、グローバルナビに Settings を入れる。
- 左にタブ（Profile / Notifications / Billing）、右に内容。モバイルでは縦積み。
- 内容の下に保存バー（未保存ピル、保存、リセット、保存済みピル）。
- ヒーローは「Settings / 設定」と「Client mode — 0往復」のバッジ。

## 状態

`app/views/settings/index.html.erb` は client mode で、1つの `herb:state` に次を宣言する（実装では1行）。

```erb
<%# herb:slots client %>
<%# herb:state (
  tab: "profile",
  name: "山田 太郎", email: "taro@example.com", bio: "",
  public_profile: false, handle: "",
  digest: true, frequency: "weekly", updates: true,
  plan: "team", annual: false, invoice_name: "",
  dirty: false, saved: false,
  name_ok: name != "", email_ok: email != "", bio_ok: bio.length <= 120,
  handle_ok: !public_profile || handle != "",
  form_ok: name_ok && email_ok && bio_ok && handle_ok,
  can_save: dirty && form_ok,
  over: bio.length > 120
) %>
```

- `tab` は String。3タブの分岐。
- `name` / `email` は必須。`bio` は任意で120字まで。`over` は警告、`bio_ok` は保存条件。
- `public_profile` が true のときだけ `handle` を表示し、`handle_ok` で必須にする。
- `digest` が true のときだけ `frequency` を表示する。
- `annual` が true のときだけ `invoice_name` を表示する。
- `dirty` は未保存の変更があるか。`saved` は直近の保存が成功したか（デモ）。
- `form_ok` は必須・文字数・ハンドルの合成。`can_save` は `dirty && form_ok`。保存ボタンの `disabled` は `!can_save` の単一否定にしておく（複合式の presence を避ける）。

## dirty の付け方

設定パネル全体を1つのラッパーで包み、入力イベントをまとめて拾う。

```erb
<div class="settings-panel"
  data-herb-set="input->dirty=true saved=false change->dirty=true saved=false">
  ... 現在のタブの内容 ...
</div>
```

- テキスト・textarea・switch は、`value=` / `checked=` の自動バインドで state を書き、ラッパーのイベントで `dirty` / `saved` を動かす。各入力に dirty の set を重ねない。
- プランと頻度はボタンなので、各ボタンに `data-herb-set="plan=starter dirty=true saved=false"` のようにリテラルを並べる。
- タブ切替はパネルの外なので dirty にしない。保存バーもパネルの外。
- 保存は `dirty=false saved=true`、リセットは初期値へ戻して `dirty` / `saved` も false。

## フィールド

### Profile

- 表示名（必須）: `value="<%= name %>"`。
- メール（必須）: `type="email"`、`value="<%= email %>"`。
- 自己紹介: `<textarea value="<%= bio %>" …>`（raw_text ではなく `value=`）、文字数と `over` の警告。
- 公開プロフィール: switch（`checked="<%= public_profile %>"`）。
  - `if public_profile` のときだけハンドル名を表示。`handle_ok` が false なら保存不可。

### Notifications

- まとめ通知: switch（`checked="<%= digest %>"`）。
  - `if digest` のときだけ頻度（毎日 / 毎週）を `.seg` で表示。各ボタンは `data-herb-set="frequency=daily dirty=true saved=false"`。
  - off のときは「まとめ通知はオフです」のヒント。
- プロダクト更新: switch（`checked="<%= updates %>"`）。

### Billing

- プラン: `<select>` は使わず、3つのボタン（Starter / Team / Business）を `.seg` で並べる。各ボタンは `data-herb-set="plan=starter dirty=true saved=false"`、`aria-pressed="<%= plan == "starter" %>"`。リセット後の表示も state から追随する。
- 年払い: switch（`checked="<%= annual %>"`）。
  - `if annual` のときだけ「請求書の宛名」を表示。`invoice_name` も dirty の対象。
  - 年払いの割引率や金額計算は Pricing に任せ、ここでは設定だけを扱う。

## タブ

- 左ナビは3つのボタン。`data-herb-set="tab=profile|notifications|billing"`、`aria-pressed="<%= tab == "profile" %>"`。
- 内容は `if tab == "profile"` / `elsif tab == "notifications"` / `else` の3分岐。
- タブ切替は dirty にしない。タブを移動しても未保存の変更は保持する。
- 未描画のタブは client mode の `<template data-herb-region>` に格納され、切替は0往復。
- 既存の Lab ウィザードで、step 分岐を往復しても入力値が保持され、slots リクエストが0であることを実測済み（ブラウザプローブ）。同じトップレベル分岐の形を使う。

## 保存とリセット

- 保存ボタン: `disabled="<%= !can_save %>"`、`data-herb-set="dirty=false saved=true"`。
- 未保存ピル: `if dirty` のとき「未保存の変更があります」。
- 保存済みピル: `if saved` のとき「保存しました（デモ）」。
- バリデーションのヒント:
  - `if !name_ok || !email_ok` →「表示名とメールは必須です」。
  - `if over` →「自己紹介は120字までです」。
  - `if public_profile && !handle_ok` →「公開プロフィールにはハンドル名が必要です」。
- リセット: `data-herb-reset="name email bio public_profile handle digest frequency updates plan annual invoice_name dirty saved"`。`tab` は含めない（今のタブに留まる）。派生状態（`name_ok` など）は含めない。
- 保存は state を変えるだけで、DB・API・メール送信はない。リロードで初期値に戻る。

## レイアウトと CSS

- `.settings-layout`: 2カラム（ナビ / 内容）。52rem 以下で1カラム。
- `.settings-nav`: 縦並びのタブ。選択中は `[aria-pressed="true"]`。
- `.settings-panel`: 内容カード。既存の `.feature` / `.field` / `.switch` / `.seg` / `.btn` / `.pill` を再利用。
- `.settings-save`: 保存バー。dirty/saved のピル、保存、リセット。
- 既存の `app.css` のデザイントークンだけで組み、Tailwind などは入れない。

## コントローラとルート

- `config/routes.rb` に `get "/settings", to: "settings#index"`。
- `SettingsController#index` は空。データはビューの state だけで完結する。
- `app/views/layouts/application.html.erb` のナビに Settings を追加。6項目になるので `.site-nav` の `flex-wrap` を確認する。

## テスト

- `test/controllers/settings_controller_test.rb`:
  - 初期表示が Profile タブで、3つのタブ、保存バー、Profile の入力がある。
  - manifest に `tab` / `name` / `email` / `bio` / `public_profile` / `handle` / `digest` / `frequency` / `updates` / `plan` / `annual` / `invoice_name` / `dirty` / `saved` / `name_ok` / `email_ok` / `bio_ok` / `handle_ok` / `form_ok` / `can_save` / `over` が宣言される。
  - `conditionals` に `tab` / `public_profile` / `digest` / `annual` / `dirty` / `saved` / `can_save` が現れる。
  - 保存ボタンの `disabled` が `can_save` の presence としてコンパイルされる。
  - 未描画のタブ・依存フィールドが `<template data-herb-region>` に格納される。
- ブラウザプローブ（`/tmp/opencode/capture`）:
  - タブ切替、Notifications の digest off/on、Profile の public_profile on/off、Billing の annual on/off が 0 slots リクエスト。
  - 入力を変えると未保存ピルと保存ボタンの有効化が即時に変わる。
  - 保存で保存済みピル、dirty が消え、保存ボタンが無効になる。
  - リセットで初期値に戻り、未保存/保存済みが消える。
  - リロードで初期値に戻る（デモ、永続化なし）。
  - 実際のプラットフォームフォントが `Noto Sans CJK JP` であること（CDP）。
- 既存の `tasks` / `patterns` / `pricing` / `showcase` / `ui` のテストが通る。

## メディア

- `docs/media/settings-light.png` / `settings-dark.png`（1000×900 @2x、sticky ヘッダが stitch されないクリップ）。
- `docs/media/17-settings.gif`: Profile → Notifications（digest off/on）→ Profile で名前編集（未保存）→ 保存（保存済み）。5〜6フレーム。
- 撮影は `app.css` の日本語フォントスタック（`Hiragino Sans` / `Noto Sans CJK JP` / `Meiryo` / `Yu Gothic`）で行い、実際のプラットフォームフォントを CDP で確認する。

## ドキュメント

- README: 6画面に更新。Settings の節と機能⑰、表の行、テスト一覧、ナビ。
- `docs/hotwire-comparison.md`: 証明マップに Settings（client / タブ・依存・dirty）を追加。§⑤に「全操作0往復」を追記。
- `AGENTS.md`: 設定画面の実測（タブ/依存フィールド/client mode、dirty/saved の明示、プランボタン、textarea の `value=`、0往復、フォント）。HTML twin は E で同期。
- 画像/GIF は README に追加する。

## 非ゴール

- DB への保存、認証、実メール送信、決済、請求書発行。
- メールアドレスの形式バリデーション（正規表現はクライアント評価外）。
- テーマ切替、i18n、no-JS の設定操作。
- パーシャル化。設定画面は1テンプレートで完結させる（パーシャル分岐の 0.6.0 ギャップを避ける）。

## 検討した案

1. **`/settings` の新画面（採用）**: 画面全体のフォームで、タブ・依存・dirty を1画面に収められる。
2. **Client Lab に追加**: Lab はウィジェット単位で既に長く、設定フォームを足すと主題が混ざる。
3. **server mode の設定画面**: 保存の往復を見せることはできるが、今回の主題は「フォーム全体を 0 往復で反応させる」ことなので client mode にする。
4. **dirty を derived にする**: 保存後に「保存済みの基準」を更新する必要があり、state のコピーが難しい。明示的な `dirty` Boolean を入力イベントで true にし、保存で false にする。
5. **依存フィールドを hidden の presence にする**: 入力ごと隠すだけなら可能だが、タブ/依存のまとまりは分岐の方が読みやすい。トップレベルの client mode 分岐は parked されるので、0往復で切り替えられる。

## リスクと確認事項

- ラッパーの `input` / `change` イベントで dirty を拾う形が、テキスト・textarea・switch の自動バインドと両立するか。実装後にブラウザプローブで確認する。不可なら各入力に `data-herb-set="dirty=true saved=false"` を足すか、switch を2ボタンにする。
- `handle_ok: !public_profile || handle != ""` と `form_ok` / `can_save` の `&&` コンボがコンパイルできるか。不可なら `name_ok` / `email_ok` / `bio_ok` / `handle_ok` の段階をさらに分ける。
- タブ分岐の往復で入力値が保持されるか。Lab ウィザードの step 往復で実測済み（値保持・slots 0）。
- プランボタンと頻度ボタンの `data-herb-set` 複数リテラルは Patterns の前例どおり。`$value` とリテラルの混在は避ける。
- 設定画面の高さ。stills/GIF で sticky ヘッダが stitch されないよう、クリップ/ビューポートを調整する。
- 6項目のナビがモバイルで折り返すか。

## 受け入れ条件

- `/settings` の全操作が **0 slots リクエスト**。
- タブ、依存フィールド、dirty、保存、リセットが即時に動く。
- リロードで初期値に戻る（デモ、DBなし）。
- 統合テストと `bin/ci` が green。
- README に 6画面目として Settings と GIF、ナビ、Hotwire 対比、AGENTS が更新されている。
