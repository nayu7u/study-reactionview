# frozen_string_literal: true

require "rails/generators"

module ReactionviewUi
  # Copies one component fragment into the app. copy_file, never template:
  # the sources contain herb directives and ERB output tags that Thor's
  # template pass would happily evaluate and mangle.
  class ComponentGenerator < Rails::Generators::NamedBase
    source_root File.expand_path("../../../reactionview_ui/components", __dir__)

    argument :name, desc: "component name under lib/reactionview_ui/components (e.g. switch)"

    def validate_name
      return if File.exist?(File.join(self.class.source_root, "#{name}.html.erb"))

      available = Dir[File.join(self.class.source_root, "*.html.erb")].map { |f| File.basename(f, ".html.erb") }
      raise Thor::Error, "Unknown component: #{name}. Available: #{available.join(', ')}"
    end

    def copy_fragment
      copy_file "#{name}.html.erb", "app/views/components/ui/_#{name}.html.erb"
    end

    def remind_css
      say <<~TEXT, :green
        Copied app/views/components/ui/_#{name}.html.erb
        Render it:  render "components/ui/#{name}", …
        Stylesheet missing? Run reactionview_ui:install once — component CSS
        ships with the aggregate asset, not per component.
      TEXT
    end
  end
end
