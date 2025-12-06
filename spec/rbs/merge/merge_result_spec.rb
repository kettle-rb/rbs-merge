# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Rbs::Merge::MergeResult do
  let(:template_source) do
    <<~RBS
      class Foo
        def bar: (String) -> Integer
      end

      type my_type = String
    RBS
  end

  let(:dest_source) do
    <<~RBS
      class Foo
        def bar: (Integer) -> String
      end

      type my_type = Integer
    RBS
  end

  let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
  let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }
  let(:result) { described_class.new(template_analysis, dest_analysis) }

  # Use shared examples - rbs-merge's MergeResult requires analysis args
  it_behaves_like "Ast::Merge::MergeResultBase" do
    let(:merge_result_class) { described_class }
    let(:build_merge_result) { -> { described_class.new(template_analysis, dest_analysis) } }
  end

  describe "#initialize" do
    it "initializes with empty content and decisions" do
      expect(result.content).to be_empty
      expect(result.decisions).to be_empty
    end

    it "stores template and dest analysis" do
      expect(result.template_analysis).to eq(template_analysis)
      expect(result.dest_analysis).to eq(dest_analysis)
    end
  end

  describe "#add_from_template" do
    it "adds content from template" do
      result.add_from_template(0)
      expect(result.to_s).to include("class Foo")
      expect(result.to_s).to include("(String) -> Integer")
    end

    it "records decision" do
      result.add_from_template(0, decision: described_class::DECISION_ADDED)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_ADDED)
      expect(result.decisions.first[:source]).to eq(:template)
    end

    it "handles nil statement gracefully" do
      result.add_from_template(999)
      expect(result.content).to be_empty
    end
  end

  describe "#add_from_destination" do
    it "adds content from destination" do
      result.add_from_destination(0)
      expect(result.to_s).to include("class Foo")
      expect(result.to_s).to include("(Integer) -> String")
    end

    it "records decision" do
      result.add_from_destination(0)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_DESTINATION)
      expect(result.decisions.first[:source]).to eq(:destination)
    end

    it "handles nil statement gracefully" do
      result.add_from_destination(999)
      expect(result.content).to be_empty
    end
  end

  describe "#add_freeze_block" do
    let(:dest_with_freeze) do
      <<~RBS
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
    end
    let(:dest_analysis_frozen) { Rbs::Merge::FileAnalysis.new(dest_with_freeze) }
    let(:result_frozen) { described_class.new(template_analysis, dest_analysis_frozen) }

    it "adds freeze block content" do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      expect(result_frozen.to_s).to include("rbs-merge:freeze")
      expect(result_frozen.to_s).to include("type frozen")
      expect(result_frozen.to_s).to include("rbs-merge:unfreeze")
    end

    it "records freeze block decision" do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      expect(result_frozen.decisions.first[:decision]).to eq(described_class::DECISION_FREEZE_BLOCK)
    end
  end

  describe "#add_recursive_merge" do
    it "adds merged content" do
      merged = "class Merged\n  def foo: () -> void\nend\n"
      result.add_recursive_merge(merged, template_index: 0, dest_index: 0)
      expect(result.to_s).to include("class Merged")
      expect(result.to_s).to include("def foo")
    end

    it "records recursive decision" do
      merged = "class Merged\nend\n"
      result.add_recursive_merge(merged, template_index: 0, dest_index: 0)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_RECURSIVE)
      expect(result.decisions.first[:source]).to eq(:merged)
    end
  end

  describe "#add_raw" do
    it "adds raw lines" do
      result.add_raw(["# Custom content", "type raw = String"], decision: :custom)
      expect(result.to_s).to include("# Custom content")
      expect(result.to_s).to include("type raw = String")
    end

    it "records raw decision" do
      result.add_raw(["# line"], decision: :custom)
      expect(result.decisions.first[:decision]).to eq(:custom)
      expect(result.decisions.first[:source]).to eq(:raw)
    end
  end

  describe "#to_s" do
    it "returns empty string for empty result" do
      expect(result.to_s).to eq("")
    end

    it "joins content with newlines" do
      result.add_from_template(1) # type my_type = String
      output = result.to_s
      expect(output).to end_with("\n")
    end
  end

  describe "#empty?" do
    it "returns true when no content" do
      expect(result.empty?).to be true
    end

    it "returns false when content exists" do
      result.add_from_template(0)
      expect(result.empty?).to be false
    end
  end

  describe "#summary" do
    it "returns summary hash" do
      result.add_from_template(0, decision: described_class::DECISION_TEMPLATE)
      result.add_from_destination(1, decision: described_class::DECISION_DESTINATION)

      summary = result.summary
      expect(summary[:total_decisions]).to eq(2)
      expect(summary[:by_decision]).to include(described_class::DECISION_TEMPLATE => 1)
      expect(summary[:by_decision]).to include(described_class::DECISION_DESTINATION => 1)
    end
  end

  describe "decision constants" do
    it "defines DECISION_FREEZE_BLOCK" do
      expect(described_class::DECISION_FREEZE_BLOCK).to eq(:freeze_block)
    end

    it "defines DECISION_TEMPLATE" do
      expect(described_class::DECISION_TEMPLATE).to eq(:template)
    end

    it "defines DECISION_DESTINATION" do
      expect(described_class::DECISION_DESTINATION).to eq(:destination)
    end

    it "defines DECISION_ADDED" do
      expect(described_class::DECISION_ADDED).to eq(:added)
    end

    it "defines DECISION_RECURSIVE" do
      expect(described_class::DECISION_RECURSIVE).to eq(:recursive)
    end
  end

  describe "extract_lines with comments" do
    let(:source_with_comments) do
      <<~RBS
        # This is a comment for the class
        class CommentedClass
          def bar: () -> void
        end
      RBS
    end
    let(:analysis_with_comments) { Rbs::Merge::FileAnalysis.new(source_with_comments) }
    let(:result_with_comments) { described_class.new(analysis_with_comments, analysis_with_comments) }

    it "includes leading comments when extracting lines" do
      result_with_comments.add_from_template(0)
      output = result_with_comments.to_s
      expect(output).to include("# This is a comment for the class")
      expect(output).to include("class CommentedClass")
    end
  end
end
