class Task < ApplicationRecord
  # Why not validates :title, presence: true: the 0.6.0 client only handles
  # the 201 splice; a crafted blank POST would then answer 422 with no
  # client path. The UI already disables the submit when the title is
  # blank, and the no-JS branch redirects with a flash.
end
