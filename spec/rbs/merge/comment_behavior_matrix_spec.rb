# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe "rbs comment behavior matrix" do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  include_examples "Ast::Merge::CommentBehaviorMatrix" do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Rbs::Merge::FileAnalysis,
      merger_class: Rbs::Merge::SmartMerger,
      structural_owners_reader: ->(analysis) { analysis.statements.grep(Rbs::Merge::NodeWrapper) },
      owner_value_reader: ->(owner) { owner.text[%r{\Atype\s+[a-z_]\w*\s+=\s+(.+)\z}, 1] },
      line_builder: lambda do |name, value, inline: nil|
        "type #{name} = #{value}"
      end,
      capabilities: {
        floating_leading_regions: "gap-separated leading docs are not yet surfaced as floating attachment regions",
        inline_comments: "inline hash comments are not part of RBS syntax",
        quoted_hash_inline_literals: "quoted values with trailing inline comments are not part of RBS syntax",
        prefix_anchor_additions: "template-only declarations are currently emitted after the first matched anchor",
        template_only_trailing_comment_additions: "template-only declaration emission does not yet append trailing full-line docs",
      },
    )
  end
end
