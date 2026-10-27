class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # herb_state returns the raw JSON value from the header untyped (the real
  # client type-checks literals against the declaration kind, but a crafted
  # header may send "12" as a string), so browser-supplied numbers are cast
  # defensively instead of calling Integer-only methods on them.
  def integer_state(name, default)
    Integer(herb_state(name, default))
  rescue TypeError, ArgumentError
    default
  end

  # A crafted header can send "true"/"false" as strings; only the Boolean
  # literal and its string form mean true.
  def boolean_state(name, default)
    value = herb_state(name, default)
    value == true || value == "true"
  end
end
