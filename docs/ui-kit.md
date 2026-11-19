# reactionview-ui — shadcn/ui モデルの ReActionView 検証キット

「shadcn/ui のようなコンポーネントライブラリは ReActionView で作れるか?」への実測の答え。
9コンポーネントを `lib/reactionview_ui/` にソース・オブ・トゥルースとして置き、ジェネレータで
アプリにコピーする — shadcn と同じ**ソース配布モデル**を ERB + 素の CSS + ビルドステップゼロで再現した。

本文の実測は 0.6.0 / herb 0.11.1 で記録し、0.6.1 / herb 0.11.2 でも presence 系は同じプローブで
再確認しています。パーシャル内の分岐は 2026-11-18 に分岐入りの probe で再測し、ギャップが残ることを
確認しました（下の「0.6.1 再検証」）。

デモ: `/ui`(client mode)。テスト: `test/controllers/ui_controller_test.rb`。
操作を1本にまとめたGIF: [media/26-ui-kit.gif](media/26-ui-kit.gif)。

## 検証結果(ブラウザ実測)

headless Chromium で入力・開閉・切替をした結果、**スロット往復 0**。
60字超えの over 警告も `hidden` の presence で表示され、0往復する（0.6.1 再測）:

| コンポーネント | 実測した操作 | 往復 |
|---|---|---|
| Switch ×2 | 片方だけクリック → `checked` が `[true, false]`（インスタンス分離） | 0 |
| Stepper | +1 ×3 → 行ごとの数量と fold 合計が即時更新、0の行の − は disabled | 0 |
| Field | 入力 → 文字数・over判定・送信ゲート・60字超え警告が即時追随（0.6.1 再測） | 0 |
| Accordion | 開閉 → 本文と ＋/－ マーカーが切替 | 0 |
| Tabs | パネル切替 → 選択強調(aria-pressed)とパネル表示 | 0 |
| Dialog | 開く / Esc / 外側クリック / 閉じる | 0 |

コンポーネントは Stimirulus も独自 JS も書かない。挙動は `herb:state` 宣言 + presence バインディング +
`data-herb-*` 属性だけで、Herb のコンパイラが manifest に落とす。

## 導入(shadcn の init / add に対応)

```console
$ bin/rails g reactionview_ui:install     # トークン+全CSSを reactionview_ui.css に集約、レイアウト配線
$ bin/rails g reactionview_ui:component switch tabs
      force  app/views/components/ui/_tabs.html.erb
```

- 断片は `app/views/components/ui/` に**そのままコピー**(copy_file — `template` だと Thor が
  herb ディレクティブを評価して壊す)。コピー後はアプリ側の所有物なので自由に編集してよい
- gem更新後は `--force` で再生成が update フロー(壊れたら手で直すのが前提のモデル)
- 断片は `herb:state` 宣言を内蔵する。**ページ側の wiring は不要** —

```erb
<%= render "components/ui/switch", label: "通知をミュート" %>
```

## コンポーネント

### Button / Badge / Card(静的)

variant マッピングは cva 相当の素の Hash。state を持たないコンポーネントは
manifest で `"states": null` にコンパイルされ、ワイヤに一切参加しない。

```erb
<%= render "components/ui/button", label: "保存する" %>
<%= render "components/ui/button", label: "削除", variant: "danger" %>
<%= render "components/ui/card", title: "見出し", content: "本文はローカル変数で渡す" %>
```

![buttons](media/ui-buttons.png)

### Switch

boolean の presence バインディング + CSS `:has(input:checked)`。同一断片を2個貼ると
occurrence index(`<!--herb-region:...:0-->` / `:1`)ごとに state が独立する実測済み。

```erb
<%= render "components/ui/switch", label: "通知をミュート" %>
```

![switch](media/ui-switch.png)

### Stepper

行ごとの `qty`(scope: 0)+ カウントfold `in_cart`(整数リテラル増分のみ)。fold の読み取りは
リストの後(ループ前で読むとコンパイルエラー)。

```erb
<%= render "components/ui/stepper", items: [{id: 1, name: "マグカップ", price: 1200}] %>
```

![stepper](media/ui-stepper.png)

### Field

派生状態(`ready: draft != ""` / `over: draft.length > 60`)+ presence ゲート。
textarea は `value=` でバインド(BINDABLE_ELEMENTS、reset が表示まで追従)。
60字超えの警告は `hidden="<%= !over %>"` の presence バインディング。
`bin/verify-reactionview run --feature ui-field-warning` で 61字の表示と 0 往復を確認する。

```erb
<%= render "components/ui/field", label: "自己紹介", placeholder: "60字以内で…" %>
```

![field](media/ui-field.png)

### Accordion

本文も ＋/－ マーカーも**全部 presence バインディング**(2つの span を貼って hidden で切替)。
per-item の `open`(scope: 0)。

```erb
<%= render "components/ui/accordion", items: [{id: 1, q: "質問", a: "答え"}] %>
```

![accordion](media/ui-accordion.png)

### Tabs

トリガは `aria-pressed` の文字列補間(CSS は `[aria-pressed="true"]` で引く)、
パネルは `hidden = tab == 相手` の presence。パネルidは断片内の**リテラル** —
クライアント比較は literal のみなので、拡張は断片を編集する(copy-source 流儀)。

```erb
<%= render "components/ui/tabs", overview: @rows_a, activity: @rows_b %>
```

![tabs](media/ui-tabs.png)

### Dialog

トリガ + state + 背景を1断片で。開閉は `hidden = !shown` の presence、
Esc / 外側クリックは `data-herb-set="keydown.esc@window->shown=false ..."` の
イベント修飾子(lab の palette パターン)。

```erb
<%= render "components/ui/dialog", cta: "詳細を開く", label: "詳細", content: "本文" %>
```

![dialog](media/ui-dialog.png)

## 0.6.1 再検証(2026-11-18)

`/ui` の Field に direct state の分岐とサーバー読みを足した probe を headless Chrome で操作した。

- 分岐の state はヘッダに載り、サーバーは `{"branch": 0, "slots": {"8": "<note>"}}` を返した。
- それでもクライアントは分岐先を DOM に materialize しなかった(`.partial-branch-probe` は不在)。
- 分岐の切替は slots 1 回。61字入力でもう1回（合計2、`partial_slots_delta` は1）。
  dev でもパーシャルに `<template data-herb-region>` は出ず、parked statics がない。
- probe 時点の `_field` は `over` 分岐で、61/60 でも警告が表示されなかった(derived state は
  ヘッダに載らず、応答は `{"branch": null}`)。修正後は `hidden` の presence で表示され、0往復。

証拠は `tmp/verify-reactionview/20261118T172712Z-26696-branch-probe/`(probe)と
`tmp/verify-reactionview/20261118T182312Z-63357/`(修正後の `ui-field-warning`)。per-item 分岐の
再測は AGENTS.md の「クライアント分岐の materialize」を参照。キットは分岐でなく presence で切り替える。

## 0.6.0 / 0.6.1 で実測した制約(このキットの設計規約)

1. **パーシャル内の分岐は materialize されない(0.6.1 でも)**: client mode でも分岐先は parked されず
   (manifest の `fragments: {}`、dev でも `<template data-herb-region>` は出ない)、
   サーバーが `{"branch": 0, "slots": {...}}` を返してもクライアントは DOM に置けない。
   derived state を条件にするとヘッダにも載らず `{"branch": null}`。
   → パーシャルでは分岐でなく **presence(hidden)+ CSS で切替**する
2. **パーシャル内の render-with-block は slots 再レンダで壊れる**
   (`TypeError: no implicit conversion of Hash into String`)→ 本文は `content:` ローカルで渡す
3. **クライアント比較は literal のみ** → ループデータとの比較(`t[:id] == …`)は不可。
   パネルid等は断片内リテラルにする
4. カウントfold・派生状態・presence・キー付きコレクションはパーシャル構成でも**完全に動く**
   (manifest はパーシャルごとに出る:`herb:state` は断片自身が所有する)
