require "test_helper"

class DocumentationLinksTest < ActiveSupport::TestCase
  DOCUMENTS = Rails.root.glob("{README.md,AGENTS.md,docs/**/*.md}").freeze

  test "relative documentation links point at files that exist" do
    missing = DOCUMENTS.flat_map do |document|
      document.read.scan(/!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/).filter_map do |(href)|
        next if href.match?(/\A(?:https?:|mailto:|#)/)

        target = document.dirname.join(href.split("#").first).cleanpath
        "#{document.relative_path_from(Rails.root)}: #{href}" unless target.exist?
      end
    end

    assert_empty missing
  end
end
