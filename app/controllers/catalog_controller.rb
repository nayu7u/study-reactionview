class CatalogController < ApplicationController
  PER_PAGE = 5

  def index
    @query = params[:q].to_s.strip
    raw_category = params[:category].to_s
    @category = Talk::CATEGORIES.include?(raw_category) ? raw_category : "all"

    scope = filtered_scope
    @total = scope.count
    @pages = [ (@total.to_f / PER_PAGE).ceil, 1 ].max
    @page = normalized_page
    return redirect_to catalog_path(canonical_params(@page)) if redirect_to_canonical?(raw_category)

    @talks = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  private

  def filtered_scope
    scope = Talk.order(:title)

    if @query.present?
      # Why not interpolate the LIKE pattern raw: a literal % or _ would widen
      # the match beyond the query the user sees. Escape and bind the char.
      esc = "\\"
      term = @query.gsub(/[%_\\]/) { "#{esc}#{$&}" }
      scope = scope.where("title LIKE ? ESCAPE ? OR speaker LIKE ? ESCAPE ?", "%#{term}%", esc, "%#{term}%", esc)
    end

    scope = scope.where(category: @category) unless @category == "all"
    scope
  end

  def normalized_page
    page = params[:page].to_s
    return 1 if page.blank?

    value = page.to_i
    value = 1 if value < 1
    value = @pages if value > @pages
    value
  end

  def redirect_to_canonical?(raw_category)
    return true if raw_category.present? && raw_category != "all" && !Talk::CATEGORIES.include?(raw_category)
    return false if params[:page].blank?

    value = params[:page].to_s
    !value.match?(/\A\d+\z/) || value.to_i < 1 || value.to_i > @pages
  end

  def canonical_params(page)
    result = {}
    result[:q] = @query if @query.present?
    result[:category] = @category unless @category == "all"
    result[:page] = page if page > 1
    result
  end
end
