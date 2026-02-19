# frozen_string_literal: true

require "spec_helper"

# FileAnalysis specs with explicit backend testing
#
# This spec file tests FileAnalysis behavior across both available backends:
# - :rbs (via RBS gem, tagged :rbs_backend)
# - :tree_sitter (via tree-sitter-rbs grammar, tagged :rbs_grammar)
#
# We define shared examples that are parameterized, then include them in
# backend-specific contexts that use TreeHaver.with_backend to explicitly
# select the backend under test.

RSpec.describe Rbs::Merge::FileAnalysis do
  # ============================================================
  # Shared examples for backend-agnostic behavior
  # These examples take the expected backend symbol as a parameter
  # The backend is determined by the TreeHaver context (via with_backend or env var)
  # ============================================================

  shared_examples "valid RBS parsing" do |expected_backend:|
    describe "with valid RBS source" do
      subject(:analysis) { described_class.new(valid_source) }

      let(:valid_source) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end

      it "parses successfully" do
        expect(analysis).to be_a(described_class)
      end

      it "is valid" do
        expect(analysis.valid?).to be true
      end

      it "has no errors" do
        expect(analysis.errors).to be_empty
      end

      it "uses the #{expected_backend} backend" do
        expect(analysis.backend).to eq(expected_backend)
      end

      it "returns a NodeWrapper for statements" do
        statements = analysis.statements
        expect(statements).to be_an(Array)
        expect(statements.first).to be_a(Rbs::Merge::NodeWrapper)
      end

      it "returns source lines" do
        expect(analysis.lines).to be_an(Array)
        expect(analysis.lines.first).to eq("class Foo")
      end

      it "extracts declarations" do
        expect(analysis.declarations).not_to be_empty
      end
    end
  end

  # Note: Strict error detection depends on the parser - RBS gem
  # reports errors more strictly than some tree-sitter backends
  shared_examples "invalid RBS detection" do
    describe "with invalid RBS", :rbs_backend do
      subject(:analysis) { described_class.new(invalid_source) }

      let(:invalid_source) do
        <<~RBS
          class Foo
            def bar: (
          end
        RBS
      end

      it "is not valid" do
        expect(analysis.valid?).to be false
      end

      it "has errors" do
        expect(analysis.errors).not_to be_empty
      end
    end
  end

  shared_examples "multiple declarations" do
    describe "with multiple declarations" do
      subject(:analysis) { described_class.new(multi_decl_source) }

      let(:multi_decl_source) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          module Bar
            def bar: () -> void
          end

          interface _Baz
            def baz: () -> void
          end

          type my_type = String | Integer

          CONST: String
        RBS
      end

      it "extracts all declaration types" do
        expect(analysis.declarations.size).to eq(5)
      end

      it "has statements for all declarations" do
        expect(analysis.statements.size).to eq(5)
      end

      it "can generate signatures for all statements" do
        analysis.statements.each do |stmt|
          sig = analysis.generate_signature(stmt)
          expect(sig).to be_an(Array)
          expect(sig).not_to be_empty
        end
      end
    end
  end

  shared_examples "signature generation" do
    describe "#generate_signature" do
      subject(:analysis) { described_class.new(source_for_signature) }

      let(:source_for_signature) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it "generates signature for a class" do
        stmt = analysis.statements.first
        sig = analysis.generate_signature(stmt)
        expect(sig).to be_an(Array)
        expect(sig.first).to eq(:class)
        expect(sig[1]).to include("Foo")
      end

      it "returns nil for nil input" do
        sig = analysis.generate_signature(nil)
        expect(sig).to be_nil
      end
    end
  end

  shared_examples "freeze blocks" do
    describe "with freeze blocks" do
      subject(:analysis) { described_class.new(source_with_freeze) }

      let(:source_with_freeze) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze

          class Bar
            def bar: () -> void
          end
        RBS
      end

      it "detects freeze blocks" do
        expect(analysis.freeze_blocks.size).to eq(1)
      end

      it "extracts freeze block content" do
        freeze_block = analysis.freeze_blocks.first
        expect(freeze_block.start_line).to eq(5)
        expect(freeze_block.end_line).to eq(7)
      end

      it "includes freeze blocks in statements" do
        # Should have: Foo class, freeze block, Bar class
        freeze_nodes = analysis.statements.select { |s| s.is_a?(Rbs::Merge::FreezeNode) }
        expect(freeze_nodes.size).to eq(1)
      end
    end
  end

  shared_examples "custom freeze token" do
    describe "with custom freeze token" do
      subject(:analysis) { described_class.new(source_with_custom_token, freeze_token: "my-token") }

      let(:source_with_custom_token) do
        <<~RBS
          # my-token:freeze
          class Foo
            def foo: () -> void
          end
          # my-token:unfreeze
        RBS
      end

      it "recognizes the custom token" do
        expect(analysis.freeze_blocks.size).to eq(1)
      end
    end
  end

  shared_examples "fallthrough_node? behavior" do
    describe "#fallthrough_node?" do
      subject(:analysis) { described_class.new(valid_source) }

      let(:valid_source) { "class Foo\nend" }

      it "returns true for NodeWrapper instances" do
        wrapper = analysis.statements.first
        expect(analysis.fallthrough_node?(wrapper)).to be true
      end

      it "returns false for other objects" do
        expect(analysis.fallthrough_node?("string")).to be false
        expect(analysis.fallthrough_node?(123)).to be false
      end
    end
  end

  shared_examples "line_at access" do
    describe "#line_at" do
      subject(:analysis) { described_class.new(multiline_source) }

      let(:multiline_source) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it "returns line at valid index (1-based)" do
        line = analysis.line_at(1)
        expect(line).to eq("class Foo")
      end

      it "returns nil for invalid index" do
        line = analysis.line_at(100)
        expect(line).to be_nil
      end

      it "returns nil for zero index" do
        line = analysis.line_at(0)
        expect(line).to be_nil
      end
    end
  end

  # ============================================================
  # :auto backend tests (uses whatever is available)
  # This tests the default behavior most users will experience
  # ============================================================

  context "with :auto backend", :rbs_parsing do
    # With :auto, we don't know which backend will be used, so we can't
    # assert the specific backend. We test that it works regardless.
    describe "with valid RBS" do
      subject(:analysis) { described_class.new(valid_source) }

      let(:valid_source) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end

      it "parses successfully" do
        expect(analysis).to be_a(described_class)
      end

      it "is valid" do
        expect(analysis.valid?).to be true
      end

      it "has no errors" do
        expect(analysis.errors).to be_empty
      end

      it "uses either :rbs or :tree_sitter backend" do
        expect(analysis.backend).to eq(:rbs).or eq(:tree_sitter)
      end
    end

    it_behaves_like "invalid RBS detection"
    it_behaves_like "multiple declarations"
    it_behaves_like "signature generation"
    it_behaves_like "freeze blocks"
    it_behaves_like "custom freeze token"
    it_behaves_like "fallthrough_node? behavior"
    it_behaves_like "line_at access"
  end

  # ============================================================
  # Explicit RBS gem backend tests (MRI only)
  # ============================================================

  context "with explicit RBS gem backend", :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like "valid RBS parsing", expected_backend: :rbs
    it_behaves_like "invalid RBS detection"
    it_behaves_like "multiple declarations"
    it_behaves_like "signature generation"
    it_behaves_like "freeze blocks"
    it_behaves_like "custom freeze token"
    it_behaves_like "fallthrough_node? behavior"
    it_behaves_like "line_at access"

    # RBS gem specific tests
    describe "RBS gem specific features" do
      subject(:analysis) { described_class.new(source_with_comments) }

      let(:source_with_comments) do
        <<~RBS
          # A sample class
          class Foo
            # A method
            def bar: (String) -> Integer
          end
        RBS
      end

      it "has directives array (even if empty)" do
        expect(analysis.directives).to be_an(Array)
      end
    end
  end

  # ============================================================
  # Explicit tree-sitter backend tests (MRI with tree-sitter-rbs)
  # Uses :mri_backend tag because this context uses tree-sitter on the MRI platform
  # ============================================================

  context "with explicit tree-sitter backend via MRI", :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like "valid RBS parsing", expected_backend: :tree_sitter
    it_behaves_like "invalid RBS detection"
    it_behaves_like "multiple declarations"
    it_behaves_like "signature generation"
    it_behaves_like "freeze blocks"
    it_behaves_like "custom freeze token"
    it_behaves_like "fallthrough_node? behavior"
    it_behaves_like "line_at access"
  end

  # ============================================================
  # Explicit Java backend tests (JRuby with tree-sitter-rbs )
  # ============================================================

  context "with explicit Java backend", :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like "valid RBS parsing", expected_backend: :tree_sitter
    it_behaves_like "invalid RBS detection"
    it_behaves_like "multiple declarations"
    it_behaves_like "signature generation"
    it_behaves_like "freeze blocks"
    it_behaves_like "custom freeze token"
    it_behaves_like "fallthrough_node? behavior"
    it_behaves_like "line_at access"
  end

  # ============================================================
  # Explicit Rust backend tests (tree-sitter via rust bindings)
  # ============================================================

  context "with explicit Rust backend", :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like "valid RBS parsing", expected_backend: :tree_sitter
    it_behaves_like "invalid RBS detection"
    it_behaves_like "multiple declarations"
    it_behaves_like "signature generation"
    it_behaves_like "freeze blocks"
    it_behaves_like "custom freeze token"
    it_behaves_like "fallthrough_node? behavior"
    it_behaves_like "line_at access"
  end

  # ============================================================
  # Explicit FFI backend tests (tree-sitter via FFI)
  # ============================================================

  context "with explicit FFI backend", :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like "valid RBS parsing", expected_backend: :tree_sitter
    it_behaves_like "invalid RBS detection"
    it_behaves_like "multiple declarations"
    it_behaves_like "signature generation"
    it_behaves_like "freeze blocks"
    it_behaves_like "custom freeze token"
    it_behaves_like "fallthrough_node? behavior"
    it_behaves_like "line_at access"
  end
end
