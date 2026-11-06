module ApplicationHelper
  def catalog_params(page: nil)
    result = {}
    result[:q] = @query if @query.present?
    result[:category] = @category unless @category == "all"
    result[:page] = page if page && page > 1
    result
  end
end
