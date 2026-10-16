# debug-mcp 接続ランブック(オンデマンド採用 / OpenCode × Rails 開発環境)

rira100000000/debug-mcp(Kaigi on Rails 2026 発表)は、debug gem 経由で稼働中の
Ruby/Rails プロセスに MCP で接続する gem(現行 0.3.0、Ruby >= 3.2、旧名 girb-mcp)。
恒久導入はしない。テスト+curl+ブラウザのブラックボックス調査で切り分けられない
実行時状態バグの時だけ、採用 → 検証 → リバートする。

## いつ採用するか(実行時状態バグの症状)
- [ ] テスト・curl・ブラウザで再現/分離できない(スレッド・Gem 内部・メモリ内状態が疑える)
- [ ] 「DB には値があるのに画面に出ない」等、プロセス内の中間状態が怪しい
- [ ] 例外が rescue され握りつぶされてスタックが残らない
- [ ] binding.pry / ログ差し込みだと再現挙動がずれる
2 個以上該当 → 採用。1 個なら通常手法をもう一度。

## 前提チェック(読み取り専用)
```bash
gem list debug          # debug 1.11.1 … 本リポジトリは dev/test で require: "debug/prelude" 済み
rdbg --version          # 1.11.1
ruby --version          # mise 管理環境。debug-mcp は Ruby >= 3.2
```

## インストール
gem は `debug-mcp` 1 本。MCP サーバ本体 `debug-mcp` と Rails 起動ラッパ
`debug-rails` の両 exe を同梱する。Gemfile の :development に 1 行追加して bundle:
```ruby
gem "debug-mcp", require: false   # MCP プロセス側から bundle exec で動かすのでアプリからは require しない
```
```bash
bundle install        # 代案: gem install debug-mcp(グローバル、Bundler 外)
```

## OpenCode への登録(stdio)
プロジェクトルートの `opencode.json` を新規作成(このリポジトリには現存しない)。
プロジェクト設定はグローバル ~/.config/opencode/opencode.json より優先、JSONC 可。
```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "debug-mcp": {
      "type": "local",
      "command": ["bundle", "exec", "debug-mcp"],
      "enabled": true,
      "timeout": 15000
    }
  }
}
```
- MCP 設定は opencode 起動時に読む → 追加後は opencode 再起動(新セッション)が必要
- 疎通確認: CLI で `opencode mcp list`。セッション内では `debug-mcp_*` のツールが見え、
  接続前でも `debug-mcp_list_debug_sessions` が空リストを返せば stdio サーバは生きている
- 注意: `list_mcp_resources`(opencode)は MCP resources 探索ツール。debug-mcp は
  resources を公開しないので、空結果 = 失敗ではない
- 文脈消費を抑えるなら常時無効 + 特定 agent のみ有効も可:
  `"tools": { "debug-mcp*": false }` + agent 設定の `tools: { "debug-mcp*": true }`

## Rails を rdbg 下で起動する
まず既存 bin/rails server(3000、ReActionView slot 用開発サーバも一緒に上がる)を
Ctrl-C で止める。アセット追加・リネーム後の再起動規約(AGENTS.md)は rdbg 下でも同じ。
```bash
# 本命: 素起動 + env 直接(このコンテナ /.dockerenv ありなので bind 先を 127.0.0.1 に明示)
RUBY_DEBUG_HOST=127.0.0.1 RUBY_DEBUG_PORT=12345 RUBY_DEBUG_OPEN=true bin/rails server  # TCP
RUBY_DEBUG_OPEN=true RUBY_DEBUG_SOCK_PATH=tmp/rdbg.sock bin/rails server               # Unix ソケット

# ラッパ: RUBY_DEBUG_OPEN=true bin/rails server 相当。
# Docker 判定(/.dockerenv)で RUBY_DEBUG_HOST=0.0.0.0 + RUBY_DEBUG_PORT=12321 を開けるため
# 本 devcontainer では bind が広がるので非推奨。判定外(ホスト直接)なら第一候補
debug-rails                       # = RUBY_DEBUG_OPEN=true bin/rails server
debug-rails s -p 3001             # ポートをずらす場合
debug-rails --debug-port 3333     # TCP debug ポートを明示(Docker 内等)

# rdbg 直接
rdbg --open --port=12345 bin/rails server
```
`--open` の既定は Unix ドメインソケット(/tmp/rdbg-<uid>/rdbg-<pid> 系)。
env 変数は RUBY_DEBUG_OPEN / _PORT / _PORT_RANGE / _HOST(既定 127.0.0.1)/
_SOCK_PATH / _SOCK_DIR / _SESSION_NAME ほか(debug README 1.11.1 確認済)。

## 冒煙テスト(接続確認)
OpenCode セッションの中で依頼する。ツール列は `debug-mcp_` 接頭辞付き:
```text
1. list_debug_sessions → 対象ソケット/ポートを確認して connect
2. set_breakpoint(file: "app/controllers/tasks_controller.rb", line: 3)  # index の @tasks 代入
3. trigger_request(method: "GET", url: "http://localhost:3000/")        # 起動ポートに合わせる
   → Rails Events(SQL / render / cache / job)付き応答。BP で停止する
4. get_context → locals(@tasks)・params・コールスタック・BP 一覧
   evaluate_code("Task.count") / evaluate_code("@tasks.first.attributes")
5. remove_breakpoint → continue_execution(終了は disconnect でなく後述)
```
一連が通れば採用完了。trigger_request は AS::Notifications を初回利用時に
プロセスへ注入して構造化イベントを返す(gem の追加インストール不要)。

## 安全規則(発表の安全設計を踏襲)
- 開発環境のみ。debug gem に認証はない → debug ポートに届く者は任意コード実行が可能。
  RUBY_DEBUG_OPEN / PORT の開放を本番・共有環境・外部公開に対して行わない
- 不可逆操作(DB 破壊系、migrate、ファイル/git 変更、プロセス停止)の実行判断は人間が持つ。
  `evaluate_code` / `run_debug_command` は任意 Ruby 実行であり、同梱の安全チェックは
  助言に留まり強制しない
- runtime data(DB 行・レスポンス・変数値)は prompt injection の経路になりうる。
  信頼できない入力を処理するプロセスには向けない
- `disconnect` は切断と同時に debuggee を terminate する。終了は BP 除去 +
  continue の後、rdbg 下サーバを Ctrl-C するのが無難
- MCP セッションは既定 30 分の無活動でタイムアウト(`--session-timeout <秒>`)
- rdbg 下の Puma は breakpoint 停止がリクエストを凍結させるため通常起動と挙動が変わる。
  UI スクリーンショット / ブラウザ検証フェーズは rdbg 起動をやめ、通常起動に戻してから行う

## リバート(通常の開発環境へ)
```bash
# 1. rdbg 下サーバを Ctrl-C → bin/rails server(通常起動)へ戻す
# 2. Gemfile の debug-mcp 1 行を削除 → bundle install(git restore Gemfile Gemfile.lock でも可)
# 3. opencode.json の "mcp"."debug-mcp" を削除(enabled: false にして残す方法もある)→ opencode 再起動
# 4. RUBY_DEBUG_SOCK_PATH で出したソケットファイル等は削除可
```
補足: rails_jobs スナップショットツールは未収録(job enqueue は trigger_request /
rails_recent_events の AS::Notifications で見える)。`run_debug_command` は raw rdbg
コマンドの逃げ口で、常用しない。
