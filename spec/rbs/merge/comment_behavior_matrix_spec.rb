# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Rbs::Merge::SmartMerger, "comment behavior matrix" do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like "Ast::Merge::CommentBehaviorMatrix" do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Rbs::Merge::FileAnalysis,
      merger_class: Rbs::Merge::SmartMerger,
      structural_owners_reader: ->(analysis) { analysis.statements.grep(Rbs::Merge::NodeWrapper) },
      owner_value_reader: ->(owner) { owner.text[%r{\Atype\s+[a-z_]\w*\s+=\s+(.+)\z}, 1] },
      line_builder: lambda do |name, value, inline: nil|
        "type #{name} = #{value}"
      end,
      capabilities: {
        inline_comments: "inline hash comments are not part of RBS syntax",
        quoted_hash_inline_literals: "quoted values with trailing inline comments are not part of RBS syntax",
      },
    )
  end
end
