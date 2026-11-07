# README・メディア整合修正 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** README の網羅性と正確性を上げ、画面タグ・GIF・説明の機能番号と内容を一致させる。

**Architecture:** 画面内の検証番号を正とする。①〜⑮ は現行の画面タグを維持し、②にピン/星（⑯）、⑨にもっと見る、⑰に Settings、⑱〜㉑に Dashboard のタグを足す。README はその番号に合わせて再構成する。GIF は既存の撮影スクリプトを更新して再撮影し、UI Kit と Lab のカウンタ／パレットだけ新規に撮る。

**Tech Stack:** Rails 8.1.4 / Ruby 4.0.9 / ReActionView 0.6.0 / Herb 0.11.1 / Playwright + gifenc（リポジトリ外の録画環境）

**Spec:** この計画は 2026-11-07 の README レビュー結果を仕様とする。

## Global Constraints

- Node/yarn はアプリに導入しない。撮影スクリプトは `/tmp/opencode/capture` に置く。
- 画像は `docs/media` に置き、README から参照する。
- 日本語フォントは `Noto Sans CJK JP` を実フォントとして確認する。
- GIF は全フレーム同一寸法にする。固定 clip を使う。
- 0往復/1往復の数値はブラウザプローブで確認する。
- 日本語の README は yomiyasu の基準で推敲する。

---

### Task 1: 機能番号の正を画面側に固定する

**Files:**
- Modify: `app/views/tasks/index.html.erb`
- Modify: `app/views/patterns/index.html.erb`
- Modify: `app/views/settings/index.html.erb`
- Modify: `app/views/dashboard/index.html.erb`
- Modify: `app/assets/stylesheets/app.css`

**Interfaces:**
- Produces: 画面タグの番号（①〜㉑）と README の見出し番号を一致させる。
- Produces: ②のタグに「ピン/星は機能⑯」を明記する。
- Produces: ⑨、⑰、⑱〜㉑のタグを追加する。

- [x] **Step 1: Hub のタグを更新する**

`機能②` を「細粒度更新＋楽観的追加（ピン/星は機能⑯）」に、`機能③` を「ドロワーとフォームのバインディング（window句 / 楽観的追加の入口）」にする。

- [x] **Step 2: Patterns に ⑨ のタグを足す**

`もっと見る` の直前に `機能⑨ もっと見る（キー付き差分）` の `feature-tag` を置く。footer の「Sprint Hub機能③」を「Sprint Hub機能②」に直す。

- [x] **Step 3: Settings に ⑰ のタグを足す**

`.settings-layout` の先頭に `機能⑰ タブ・依存フィールド・未保存状態` を置き、`app.css` に `grid-column: 1 / -1` のクラスを足す。

- [x] **Step 4: Dashboard に ⑱〜㉑ のタグを足す**

Summary に ⑱、Activity に ⑲、Focus に ⑳、Heartbeat に ㉑ の `feature-tag` を置く。

- [x] **Step 5: 表示を確認する**

Run: `bin/rails test test/controllers/tasks_controller_test.rb test/controllers/patterns_controller_test.rb test/controllers/settings_controller_test.rb test/controllers/dashboard_controller_test.rb`
Expected: PASS

- [x] **Step 6: Commit**

```bash
git add app/views/tasks/index.html.erb app/views/patterns/index.html.erb app/views/settings/index.html.erb app/views/dashboard/index.html.erb app/assets/stylesheets/app.css
git commit -m "fix(ui): make the on-screen verification numbers canonical — README and GIFs will follow the same IDs"
```

---

### Task 2: Hub の 01〜04 と 16 を再撮影する

**Files:**
- Modify: `/tmp/opencode/capture/hub-capture.js`
- Modify: `/tmp/opencode/capture/pin-capture.js`
- Output: `docs/media/01-server-reads.gif`
- Output: `docs/media/02-row-state.gif`
- Output: `docs/media/03-optimistic-add.gif`
- Output: `docs/media/04-window-clauses.gif`
- Output: `docs/media/16-pin.gif`

**Interfaces:**
- Consumes: Task 1 のタグ。
- Produces: 01 は行が見える、03 は同期で 10→11、04 はキー操作オーバーレイ付き、16 は新しいタグ。

- [x] **Step 1: DB を seed に戻す**

Run: `bin/rails db:seed`
Expected: Task 10件。

- [x] **Step 2: hub-capture.js の 01 を固定 clip にする**

`load-more` で2行に絞り、`.feature-grid` の左上から幅 784 / 高さ 900 の clip を固定する。全フレームを `page.screenshot({ clip })` で撮る。

- [x] **Step 3: 03 に同期フレームを足す**

追加後、`🔄 同期` をクリックし、hero が `11 TASKS` になるまで待ってから最終フレームを撮る。

- [x] **Step 4: 04 にキー操作オーバーレイを足す**

`Ctrl+B` 前は「Ctrl+B で開く」、開いた後は「Esc で閉じる」、閉じた後は「閉じた（Esc）」を固定表示する。

- [x] **Step 5: 16 のタグを更新して再撮影する**

`pin-capture.js` を実行し、`機能② ... ピン/星は機能⑯` のタグで 16 を撮る。slots 0 を assert する。

- [x] **Step 6: 撮影して寸法を確認する**

Run:
```bash
cd /tmp/opencode/capture
node hub-capture.js
node pin-capture.js
```
Run:
```bash
for f in docs/media/01-server-reads.gif docs/media/02-row-state.gif docs/media/03-optimistic-add.gif docs/media/04-window-clauses.gif docs/media/16-pin.gif; do ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 "$f"; done
```
Expected: 各 GIF が生成され、フレーム寸法が全フレームで一定。

- [x] **Step 7: Commit**

```bash
git add docs/media/01-server-reads.gif docs/media/02-row-state.gif docs/media/03-optimistic-add.gif docs/media/04-window-clauses.gif docs/media/16-pin.gif
git commit -m "docs(hub): re-shoot the demo around the canonical feature IDs — rows, sync, key overlay, and the pin tag are now visible"
```

---

### Task 3: Patterns の 08 / 09 を再撮影する

**Files:**
- Modify: `/tmp/opencode/capture/capture.js`
- Output: `docs/media/08-chips.gif`
- Output: `docs/media/09-load-more.gif`
- Output: `docs/media/patterns-light.png`
- Output: `docs/media/patterns-dark.png`

- [x] **Step 1: 08 と 09 を再撮影する**

`capture.js` の 08/09 を実行し、⑨タグが入った状態にする。

- [x] **Step 2: 寸法とフレーム数を確認する**

Run: `ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 docs/media/08-chips.gif docs/media/09-load-more.gif`
Expected: 生成され、`09` に「全部読み込みました」が写る。

- [x] **Step 3: Commit**

```bash
git add docs/media/08-chips.gif docs/media/09-load-more.gif docs/media/patterns-light.png docs/media/patterns-dark.png
git commit -m "docs(patterns): show the load-more tag in the inbox demo — the ⑨ ID is now visible in the media"
```

---

### Task 4: Settings の 17 を再撮影する

**Files:**
- Modify: `/tmp/opencode/capture/settings-capture.js`
- Output: `docs/media/17-settings.gif`
- Output: `docs/media/settings-light.png`
- Output: `docs/media/settings-dark.png`

- [x] **Step 1: 17 の手順を増やす**

Profile → Notifications → digest off/on → Billing（Business を選択）→ Profile（名前変更）→ 保存 → リセット、の7フレームにする。

- [x] **Step 2: 0 slots を assert する**

既存の `slots.length !== 0` チェックを維持する。

- [x] **Step 3: 撮影する**

Run: `cd /tmp/opencode/capture && node settings-capture.js`
Expected: 7 frames、`Noto Sans CJK JP`、slots 0。

- [x] **Step 4: 寸法を確認する**

Run: `ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 docs/media/17-settings.gif`
Expected: 全フレーム同一寸法。

- [x] **Step 5: Commit**

```bash
git add docs/media/17-settings.gif docs/media/settings-light.png docs/media/settings-dark.png
git commit -m "docs(settings): include Billing and reset in the demo — the caption promises reset, so the GIF must show it"
```

---

### Task 5: Dashboard の 18 を再撮影する

**Files:**
- Modify: `/tmp/opencode/capture/dashboard-capture.js`
- Output: `docs/media/18-dashboard.gif`
- Output: `docs/media/dashboard-light.png`
- Output: `docs/media/dashboard-dark.png`

- [x] **Step 1: 18 を再撮影する**

⑱〜㉑ のタグが入った状態で、fallback → Async → focus → Lazy → poll の5フレームを撮る。

- [x] **Step 2: 確認する**

Run: `ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 docs/media/18-dashboard.gif`
Expected: 5 frames、同一寸法。

- [x] **Step 3: Commit**

```bash
git add docs/media/18-dashboard.gif docs/media/dashboard-light.png docs/media/dashboard-dark.png
git commit -m "docs(dashboard): keep the demo and the four feature tags in sync — Async, Lazy, Fragment, and poll are all visible"
```

---

### Task 6: Lab の 06 と UI Kit の 26 を新規撮影する

**Files:**
- Create: `/tmp/opencode/capture/lab-06-capture.js`
- Create: `/tmp/opencode/capture/ui-kit-capture.js`
- Output: `docs/media/06-palette.gif`
- Output: `docs/media/26-ui-kit.gif`

- [x] **Step 1: 06 を撮る**

Lab の counter と palette を1本にまとめる。+2 → リセット → ⌘K で開く → Esc で閉じる。固定 clip、0 slots。

- [x] **Step 2: 26 を撮る**

`/ui` で switch ×2 → field → stepper → accordion → tabs → dialog を操作する。viewport 固定で全フレーム同一寸法、0 slots。

- [x] **Step 3: 確認する**

Run:
```bash
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 docs/media/06-palette.gif docs/media/26-ui-kit.gif
```
Expected: 両方生成、同一寸法。

- [x] **Step 4: Commit**

```bash
git add docs/media/06-palette.gif docs/media/26-ui-kit.gif
git commit -m "docs(lab,ui): add the counter and UI Kit demos — the only zero-roundtrip screens without motion now have one"
```

---

### Task 7: README を全面修正する

**Files:**
- Modify: `README.md`
- Modify: `docs/ui-kit.md`
- Modify: `AGENTS.md`

- [x] **Step 1: 冒頭と全体像を直す**

7ナビ画面＋6ナビ外検証、server/client の比較表、セットアップ（Ruby 4.0.9 / Rails 8.1.4 / SQLite / `bin/setup` / `bin/ci`）、ドキュメント一覧を足す。

- [x] **Step 2: 事実誤認を直す**

`app.css` 1枚 → `app.css` + `reactionview_ui.css`。Stimulus/Turbo は import していないと明記。12行 → 16行。`meta+b`/`ctrl+b` は「1 binding では OR 不可」に直す。

- [x] **Step 3: 機能番号を画面に合わせる**

Hub ②/③/⑯、Lab ④/⑤・⑥/⑦、Patterns ⑧/⑨/⑩、Settings ⑰、Dashboard ⑱〜㉑ に揃える。README の並びは画面順で、番号は画面タグの通し番号だと明記する。

- [x] **Step 4: 各 GIF の説明を直す**

01 は行が見える、02 はピンも見える、03 は同期込み、04 はキーオーバーレイ、06 はカウンタ＋パレット、17 はリセット込み、18 は Async/poll/Fragment/Lazy に合わせる。

- [x] **Step 5: UI Kit と Lab の hover を補う**

9コンポーネント名、`reactionview_ui.css`、ジェネレータ、26 の GIF を追加。Lab ⑥に hover preview の説明を足す。

- [x] **Step 6: 検証の進め方を直す**

controller 14 + model 7 + generator 1、`bin/ci`、プローブがリポジトリ外にあることを書く。

- [x] **Step 7: yomiyasu の基準で読み直す**

比喩・冗長な予告・主述の曖昧さを削り、意味と条件を保つ。README の技術的主張は変えない。

- [x] **Step 8: リンク切れを確認する**

Run:
```bash
ruby -e 'text=File.read("README.md"); text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each { |p| next if p.start_with?("http"); abort "MISSING #{p}" unless File.exist?(p) }; puts "links OK"'
```
Expected: `links OK`

- [x] **Step 9: Commit**

```bash
git add README.md docs/ui-kit.md AGENTS.md
git commit -m "docs(readme): make the showcase complete and accurate — modes, UI Kit, setup, tests, and feature IDs now match the app and GIFs"
```

---

### Task 8: 全体検証と最終コミット

**Files:** なし（検証のみ）

- [x] **Step 1: テストを実行する**

Run: `bin/rails test`
Expected: PASS

- [x] **Step 2: フルゲートを実行する**

Run: `bin/ci`
Expected: PASS

- [x] **Step 3: 画像リンクと GIF を確認する**

Run:
```bash
for f in $(grep -oE 'docs/media/[^)" ]+\.(png|gif)' README.md | sort -u); do test -f "$f" || echo "MISSING $f"; done
for f in docs/media/*.gif; do printf '%s ' "$f"; ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 "$f"; done
```
Expected: 欠損なし、全 GIF が読める。

- [x] **Step 4: 作業ツリーを確認する**

Run: `git status --short`
Expected: 意図したファイルだけが変更されている。

- [x] **Step 5: 最終コミット（未コミットがあれば）**

```bash
git add -A
git commit -m "chore: finish the README and media consistency pass"
```
