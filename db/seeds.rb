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
