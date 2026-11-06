require "test_helper"

# What is covered here: the URL is the source of truth for the search.
# The form and links are standard GET; the compact switch is added in Task 3.
class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "index renders the search form, the first page and the share URL" do
    get catalog_path

    assert_response :success
    assert_select "h1", "Talk Catalog"
    assert_select "form[action='#{catalog_path}'][method='get']"
    assert_select "form[data-herb-into]", count: 0
    assert_select ".catalog-row", count: 5
    assert_select ".pagination a", text: "3"
    assert_select ".share-url code", text: "/catalog"
    assert_select "a[href='#{forms_path}']"
  end

  test "q filters by title and by speaker" do
    get catalog_path(q: "ReActionView")
    assert_response :success
    assert_select ".catalog-row", count: 1
    assert_select ".catalog-row h3", text: "ReActionViewのスロットを読む"
    assert_select "input[name='q'][value='ReActionView']"

    get catalog_path(q: "佐藤")
    assert_response :success
    assert_select ".catalog-row", count: 1
    assert_select ".catalog-row h3", text: "Stimulusを捨てた先のフォーム"
  end

  test "q escapes LIKE wildcards" do
    get catalog_path(q: "%")
    assert_response :success
    assert_select ".catalog-row", count: 0
    assert_select ".catalog-empty"

    get catalog_path(q: "_")
    assert_response :success
    assert_select ".catalog-row", count: 0
  end

  test "category rails has two pages and page 2 has one talk" do
    get catalog_path(category: "rails")
    assert_response :success
    assert_select ".catalog-row", count: 5
    assert_select "select[name='category'] option[selected][value='rails']"
    assert_select ".pagination a", text: "2"

    get catalog_path(category: "rails", page: 2)
    assert_response :success
    assert_select ".catalog-row", count: 1
    assert_select ".pagination a", text: "1"
  end

  test "page 3 of all talks has two rows" do
    get catalog_path(page: 3)

    assert_response :success
    assert_select ".catalog-row", count: 2
    assert_select ".pagination a", text: "1"
  end

  test "q, category and page combine" do
    get catalog_path(q: "山田", category: "rails", page: 1)

    assert_response :success
    assert_select ".catalog-row", count: 2
    assert_select "input[name='q'][value='山田']"
    assert_select "select[name='category'] option[selected][value='rails']"
  end

  test "pagination links preserve q and category" do
    get catalog_path(category: "rails")

    assert_response :success
    links = css_select(".pagination a").map { |a| a["href"] }
    assert links.any? { |href| href.include?("category=rails") && href.include?("page=2") }

    get catalog_path(q: "の")

    assert_response :success
    links = css_select(".pagination a").map { |a| a["href"] }
    assert links.any? { |href| href.include?("q=%E3%81%AE") && href.include?("page=2") }
  end

  test "invalid category and page redirect to the canonical URL" do
    get catalog_path(page: "abc")
    assert_redirected_to catalog_path

    get catalog_path(page: 0)
    assert_redirected_to catalog_path

    get catalog_path(page: 999)
    assert_redirected_to catalog_path(page: 3)

    get catalog_path(category: "unknown")
    assert_redirected_to catalog_path

    get catalog_path(q: "ReActionView", page: 999)
    assert_redirected_to catalog_path(q: "ReActionView")
  end

  test "default category and page are accepted without a redirect" do
    get catalog_path(category: "all")
    assert_response :success

    get catalog_path(page: 1)
    assert_response :success
  end

  test "filtered out-of-range page redirects to that filter's last page" do
    get catalog_path(category: "rails", page: 999)

    assert_redirected_to catalog_path(category: "rails", page: 2)
  end

  test "no matches render an empty state with one page" do
    get catalog_path(q: "nonexistent")

    assert_response :success
    assert_select ".catalog-row", count: 0
    assert_select ".catalog-empty"
    assert_select ".pagination", count: 0
  end

  test "the initial HTML shows abstracts without JavaScript" do
    get catalog_path

    assert_response :success
    assert_select ".catalog-abstract", count: 5
    assert_select ".catalog-abstract[hidden]", count: 0
  end

  test "the search form is a standard GET form" do
    get catalog_path

    assert_select "form[method='get'][action='#{catalog_path}']"
    assert_select "form[data-herb-set]", count: 0
    assert_select "form[data-herb-into]", count: 0
  end
end
