# Why destroy_all first: this study app re-runs `bin/rails db:seed` between
# recording sessions, and appended runs would stack duplicate rows on the
# board (db:seed:replant already truncates, dev reruns do not).
Task.destroy_all

# Priorities give the Patterns screen's filter chips a closed set to facet
# on (1=low, 2=mid, 3=high) and vary row pills without any state wiring.
# Ten rows on purpose: the Patterns screen pages six at a time, so the
# load-more button has a second page to reveal right after db:seed.
[
  [ 3, "Read the ReActionView quick start" ],
  [ 2, "Open the composer without a page load" ],
  [ 2, "Sort the board and watch rows move, not rebuild" ],
  [ 1, "Try to break a template and meet the overlay" ],
  [ 3, "Wire the detail drawer to the selected row" ],
  [ 1, "Measure the slots payload for a load-more click" ],
  [ 2, "Facet the inbox by priority chips" ],
  [ 1, "Check the no-JS fallback on every form" ],
  [ 3, "Record the load-more keyed diff as a GIF" ],
  [ 1, "Compare presence bindings against attribute interpolation" ]
].each { |priority, title| Task.create!(title: title, priority: priority) }

# The /forms page is a server-validation experiment, so its list needs a few
# rows in each category to make the client-side filter visible on first load.
Proposal.destroy_all

[
  [ "山田 太郎", "taro@example.com", "ERBだけで作るリアクティブUI",
    "ReActionViewのスロットとクライアント状態を使い、ビルドなしで細粒度の更新を組み立てる話です。", "rails" ],
  [ "佐藤 花子", "hanako@example.com", "フォームのバリデーションをサーバーに残す",
    "クライアント検証とサーバー検証の役割を分け、422の応答をどう扱うかを整理します。", "frontend" ],
  [ "鈴木 一郎", "ichiro@example.com", "小さなRailsアプリの運用",
    "依存を増やさずに運用するための構成と、障害時の切り分けを紹介します。", "infra" ]
].each do |speaker_name, email, title, abstract, category|
  Proposal.create!(speaker_name: speaker_name, email: email, title: title, abstract: abstract, category: category)
end

# The catalog is a read-only search dataset. rails intentionally has six rows
# so ?category=rails&page=2 is a real page, not a redirect.
Talk.destroy_all

[
  [ "ReActionViewのスロットを読む", "山田 太郎", "rails",
    "スロットのwire形式を実際の応答から読み、キー付き差分がどこで起きるかを追います。" ],
  [ "Hotwireなしでどこまで行けるか", "山田 太郎", "rails",
    "TurboとStimulusを外したときに、どのUIが残り、どこに標準のRailsが必要かを整理します。" ],
  [ "フォームのバリデーションをサーバーに残す", "高橋 美咲", "rails",
    "422の全画面再描画と入力値保持を、実際のフォームで確かめた結果を共有します。" ],
  [ "スロットのペイロードを小さく保つ", "小林 悠", "rails",
    "何をREAD slotにし、何を分岐のstaticsに置くかで、往復の大きさがどう変わるかを測ります。" ],
  [ "Rails 8の認証を最小で組む", "加藤 誠", "rails",
    "認証を足すときに増えるstateと、サーバーに残すべき判断を最小構成で整理します。" ],
  [ "リリースを小さく保つ", "松本 彩", "rails",
    "変更を小さく出し続けるためのブランチ運用と、検証の自動化について話します。" ],
  [ "Stimulusを捨てた先のフォーム", "佐藤 花子", "frontend",
    "入力の派生状態と表示の切替を、宣言とpresenceだけでどこまで組めるかを紹介します。" ],
  [ "ゼロビルドのCSS設計", "渡辺 さくら", "frontend",
    "デザイントークンと素のCSSで、ビルドなしの画面を破綻させない方法を整理します。" ],
  [ "フロントエンドの負債を減らす", "吉田 葵", "frontend",
    "依存とビルドを増やさずに、画面の変更を追いやすくするための判断を共有します。" ],
  [ "小さなRailsアプリの運用", "鈴木 一郎", "infra",
    "依存を増やさずに運用するための構成と、障害時の切り分けを紹介します。" ],
  [ "SQLiteで始める小さなSaaS", "中村 大地", "infra",
    "SQLiteを前提にしたときのバックアップ、移行、監視の最小構成を話します。" ],
  [ "監視のない運用から始める", "山本 修", "infra",
    "最初から監視を揃えない代わりに、どこを先に見るかを決めておく運用を紹介します。" ]
].each do |title, speaker, category, abstract|
  Talk.create!(title: title, speaker: speaker, category: category, abstract: abstract)
end

Submission.destroy_all

[ "最初の提出", "2番目の提出", "3番目の提出" ].each do |title|
  Submission.create!(title: title)
end

Post.destroy_all

first = Post.create!(title: "スロットの質問")
first.replies.create!(body: "キー付き差分は入れ子でも効きますか？")
first.replies.create!(body: "まずは外側のキーから確認します。")

second = Post.create!(title: "返信の順序")
second.replies.create!(body: "作成順で並んでいます。")
second.replies.create!(body: "追加すると末尾に入ります。")

Post.create!(title: "no-JSの返信")

# The tree screen needs real depth. The roots are destroyed so dependent:
# :destroy removes the whole tree without deleting a parent before its
# children (a flat delete_all would violate the self-referential FK).
TreeNode.where(parent_id: nil).destroy_all

tree = lambda do |name, kind, parent: nil, position: 0|
  TreeNode.create!(name: name, kind: kind, parent: parent, position: position)
end

app = tree.call("app", "folder", position: 1)
app_controllers = tree.call("controllers", "folder", parent: app, position: 1)
tree.call("trees_controller.rb", "file", parent: app_controllers, position: 1)
tree.call("tasks_controller.rb", "file", parent: app_controllers, position: 2)
app_models = tree.call("models", "folder", parent: app, position: 2)
tree.call("tree_node.rb", "file", parent: app_models, position: 1)
tree.call("task.rb", "file", parent: app_models, position: 2)
app_views = tree.call("views", "folder", parent: app, position: 3)
views_trees = tree.call("trees", "folder", parent: app_views, position: 1)
tree.call("index.html.erb", "file", parent: views_trees, position: 1)
tree.call("_level2.html.erb", "file", parent: views_trees, position: 2)
tree.call("_level3.html.erb", "file", parent: views_trees, position: 3)
tree.call("_file.html.erb", "file", parent: views_trees, position: 4)
views_tasks = tree.call("tasks", "folder", parent: app_views, position: 2)
tree.call("index.html.erb", "file", parent: views_tasks, position: 1)
config = tree.call("config", "folder", position: 2)
tree.call("routes.rb", "file", parent: config, position: 1)
tree.call("importmap.rb", "file", parent: config, position: 2)
test = tree.call("test", "folder", position: 3)
tree.call("trees_controller_test.rb", "file", parent: test, position: 1)
