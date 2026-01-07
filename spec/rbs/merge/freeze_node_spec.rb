# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

# FreezeNode specs - works with any RBS parser backend
# Tagged with :rbs_parsing since FileAnalysis supports both RBS gem and tree-sitter-rbs
RSpec.describe Rbs::Merge::FreezeNode, :rbs_parsing do
  # Use shared examples to validate base FreezeNodeBase integration
  it_behaves_like "Ast::Merge::FreezeNodeBase" do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      # RBS FreezeNode requires an analysis object
      source = <<~RBS
        # rbs-merge:freeze
        type example = String
        # rbs-merge:unfreeze
      RBS
      analysis = Rbs::Merge::FileAnalysis.new(source)
      ->(start_line:, end_line:, **opts) {
        # For the shared examples, we create a simple freeze node
        # using the analysis from the source above
        described_class.new(
          start_line: start_line,
          end_line: end_line,
          analysis: analysis,
          **opts,
        )
      }
    end
  end

  # RBS-specific tests below
  let(:source) do
    <<~RBS
      class Before
      end

      # rbs-merge:freeze Custom reason
      type custom = String
      # rbs-merge:unfreeze

      class After
      end
    RBS
  end
  let(:analysis) { Rbs::Merge::FileAnalysis.new(source) }

  describe "inheritance" do
    it "inherits from Ast::Merge::FreezeNodeBase" do
      expect(described_class.superclass).to eq(Ast::Merge::FreezeNodeBase)
    end

    it "has InvalidStructureError" do
      expect(described_class::InvalidStructureError).to eq(Ast::Merge::FreezeNodeBase::InvalidStructureError)
    end

    it "has Location" do
      expect(described_class::Location).to eq(Ast::Merge::FreezeNodeBase::Location)
    end
  end

  describe "freeze block detection" do
    it "detects freeze blocks in analysis" do
      expect(analysis.freeze_blocks.size).to eq(1)
    end

    it "has correct line numbers" do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.start_line).to eq(4)
      expect(freeze_node.end_line).to eq(6)
    end
  end

  describe "#nodes" do
    it "contains declarations within the freeze block", :rbs_backend do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.nodes.size).to eq(1)
      expect(freeze_node.nodes.first).to be_a(RBS::AST::Declarations::TypeAlias)
    end
  end

  describe "#content" do
    it "returns the content of the freeze block" do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.content).to include("rbs-merge:freeze")
      expect(freeze_node.content).to include("type custom")
      expect(freeze_node.content).to include("rbs-merge:unfreeze")
    end
  end

  describe "#signature" do
    it "returns a FreezeNode signature with normalized content" do
      freeze_node = analysis.freeze_blocks.first
      sig = freeze_node.signature
      expect(sig.first).to eq(:FreezeNode)
      expect(sig.last).to be_a(String)
      expect(sig.last).to include("type custom")
    end
  end

  describe "#location" do
    it "returns a Location struct" do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      expect(location).to be_a(described_class::Location)
      expect(location.start_line).to eq(4)
      expect(location.end_line).to eq(6)
    end

    it "supports cover? method" do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      expect(location.cover?(4)).to be true
      expect(location.cover?(5)).to be true
      expect(location.cover?(6)).to be true
      expect(location.cover?(3)).to be false
      expect(location.cover?(7)).to be false
    end
  end

  describe "#reason" do
    it "extracts reason from freeze marker" do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.reason).to eq("Custom reason")
    end

    context "without reason" do
      let(:source) do
        <<~RBS
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze
        RBS
      end

      it "returns nil when no reason provided" do
        freeze_node = analysis.freeze_blocks.first
        expect(freeze_node.reason).to be_nil
      end
    end
  end

  describe "#inspect" do
    it "returns a descriptive string" do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.inspect).to match(/Rbs::Merge::FreezeNode/)
      expect(freeze_node.inspect).to match(/lines=4\.\.6/)
      expect(freeze_node.inspect).to match(/nodes=1/)
    end
  end

  describe "validation" do
    context "with partial overlap" do
      let(:invalid_source) do
        <<~RBS
          # rbs-merge:freeze
          class Foo
            def bar: () -> void
          # rbs-merge:unfreeze
          end
        RBS
      end

      it "raises InvalidStructureError" do
        expect { Rbs::Merge::FileAnalysis.new(invalid_source) }
          .to raise_error(described_class::InvalidStructureError)
      end

      it "includes node names in error message" do
        expect { Rbs::Merge::FileAnalysis.new(invalid_source) }
          .to raise_error(described_class::InvalidStructureError, /Foo.*lines/)
      end
    end

    context "with partial overlap and node without name method" do
      # Test the else branch in validate_structure! (line 103)
      # where node.respond_to?(:name) is false
      it "uses class name when node doesn't respond to :name" do
        # Create a freeze node with a mock node that doesn't have :name
        source = <<~RBS
          class Foo
          end
        RBS
        analysis = Rbs::Merge::FileAnalysis.new(source)

        # Create a mock node without :name method that partially overlaps
        # Freeze block: lines 2-4, Node: lines 1-3 (partial overlap)
        nameless_node = double("NamelessNode")
        # Default to false for all respond_to? calls
        allow(nameless_node).to receive(:respond_to?).and_return(false)
        # Override specific ones we need
        allow(nameless_node).to receive(:respond_to?).with(:location).and_return(true)
        allow(nameless_node).to receive(:location).and_return(double(start_line: 1, end_line: 3))

        # Validation happens during initialize, so the error is raised there
        # Freeze block lines 2-4, node lines 1-3 creates partial overlap:
        # - NOT fully_contained (node starts before freeze block)
        # - NOT encompasses (node doesn't end after freeze block)
        # - NOT fully_outside (overlaps at lines 2-3)
        expect {
          described_class.new(
            start_line: 2,
            end_line: 4,
            analysis: analysis,
            nodes: [],
            overlapping_nodes: [nameless_node],
          )
        }.to raise_error(described_class::InvalidStructureError, /Double/)
      end
    end

    context "with fully contained declaration" do
      let(:valid_source) do
        <<~RBS
          # rbs-merge:freeze
          class Foo
            def bar: () -> void
          end
          # rbs-merge:unfreeze
        RBS
      end

      it "does not raise" do
        expect { Rbs::Merge::FileAnalysis.new(valid_source) }.not_to raise_error
      end
    end

    context "with freeze block inside class" do
      let(:nested_source) do
        <<~RBS
          class Foo
            # rbs-merge:freeze
            def custom: () -> void
            # rbs-merge:unfreeze
          end
        RBS
      end

      # This is actually valid - the class encompasses the freeze block
      it "allows freeze blocks inside container declarations" do
        expect { Rbs::Merge::FileAnalysis.new(nested_source) }.not_to raise_error
      end
    end
  end
end
