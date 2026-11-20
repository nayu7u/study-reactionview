require "test_helper"

# What is covered here: the shell every page shares — the browser title and
# the nav's current-page marker. Both are easy to lose when a screen is
# added by copying another view.
class NavigationTest < ActionDispatch::IntegrationTest
  test "the nav marks only the current page" do
    get root_path

    assert_select ".site-nav a[aria-current='page']", count: 1
    assert_select ".site-nav a[aria-current='page']", text: "Sprint Hub"

    get root_path(query: "sprint")

    assert_select ".site-nav a[aria-current='page']", count: 1,
      message: "a query string must not clear the current-page marker"

    get dashboard_path

    assert_select ".site-nav a[aria-current='page']", count: 1
    assert_select ".site-nav a[aria-current='page']", text: "Dashboard"

    get catalog_path

    assert_select ".site-nav a[aria-current='page']", count: 0,
      message: "off-nav screens must not claim a nav location"
  end

  test "each page names itself in the browser title" do
    get root_path
    assert_select "title", text: "Sprint Hub | Study ReActionView"

    get catalog_path
    assert_select "title", text: "Talk Catalog | Study ReActionView"

    get ui_path
    assert_select "title", text: "UI Kit | Study ReActionView"
  end
end
