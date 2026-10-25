# frozen_string_literal: true

require "rails/generators"

module ReactionviewUi
  # Copies the design tokens plus every component stylesheet into one
  # aggregate asset and wires it into the layout — the `init` step of the
  # shadcn model: tokens and plumbing land once, components are added
  # individually afterwards with reactionview_ui:component.
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("../../../reactionview_ui", __dir__)

    class_option :force, type: :boolean, default: false, desc: "Overwrite existing files"

    def copy_aggregate_stylesheet
      component_css = Dir[File.join(self.class.source_root, "components", "*.css")].sort
                       .map { |file| "/* ---- #{File.basename(file)} ---- */\n" + File.read(file) }
                       .join("\n")

      create_file "app/assets/stylesheets/reactionview_ui.css",
        File.read(File.join(self.class.source_root, "tokens.css")) + "\n" + component_css,
        force: options[:force]
    end

    def wire_layout
      layout = "app/views/layouts/application.html.erb"
      return say "layout not found, link reactionview_ui.css by hand" unless File.exist?(layout)
      return say "layout already links reactionview_ui.css" if File.read(layout).include?("reactionview_ui")

      insert_into_file layout, after: /stylesheet_link_tag :app.*\n/ do
        %(    <%= stylesheet_link_tag "reactionview_ui", "data-turbo-track": "reload" %>\n)
      end
    end

    def show_next_step
      say <<~TEXT, :green
        Next, copy the components you want — they land in app/views/components/ui/:

          bin/rails g reactionview_ui:component switch
          bin/rails g reactionview_ui:component tabs

        Render them like any partial:  render "components/ui/switch", label: "通知"
        Each fragment carries its own herb:state declarations, so a pasted
        component owns its state — no page wiring needed.
      TEXT
    end
  end
end
