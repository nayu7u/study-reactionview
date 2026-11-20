module ApplicationHelper
  def nav_link(label, path)
    link_to label, path, aria: { current: ("page" if current_page?(path)) }
  end

  def catalog_params(page: nil)
    result = {}
    result[:q] = @query if @query.present?
    result[:category] = @category unless @category == "all"
    result[:page] = page if page && page > 1
    result
  end
end
