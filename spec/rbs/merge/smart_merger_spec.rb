# frozen_string_literal: true

# SmartMerger specs with explicit backend testing
#
# This spec file tests SmartMerger behavior across both available backends:
# - :rbs (via RBS gem, tagged :rbs_backend)
# - :tree_sitter (via tree-sitter-rbs grammar, tagged :rbs_grammar)
#
# We define shared examples that are parameterized, then include them in
# backend-specific contexts.

RSpec.describe Rbs::Merge::SmartMerger do
  let(:template_content) do
    <<~RBS
      class Foo
        def bar: (String) -> Integer
      end
    RBS
  end

  let(:dest_content) do
    <<~RBS
      class Foo
        def bar: (Integer) -> String
        def baz: () -> void
      end
    RBS
  end

  # ============================================================
  # Shared examples for error detection
  # ============================================================

  # ============================================================
  # Shared examples for parse error handling
  # Note: Strict error detection depends on the parser - RBS gem
  # reports errors more strictly than some tree-sitter backends
  # ============================================================

  shared_examples "invalid template detection" do
    let(:invalid_template) do
      <<~RBS
        class Foo
          def bar: (
        end
      RBS
    end

    it "raises TemplateParseError", :rbs_backend do
      expect {
        described_class.new(invalid_template, dest_content)
      }.to raise_error(Rbs::Merge::TemplateParseError)
    end
  end

  shared_examples "invalid destination detection" do
    let(:invalid_dest) do
      <<~RBS
        class Bar
          def baz: (
        end
      RBS
    end

    it "raises DestinationParseError", :rbs_backend do
      expect {
        described_class.new(template_content, invalid_dest)
      }.to raise_error(Rbs::Merge::DestinationParseError)
    end
  end

  # ============================================================
  # Shared examples for basic functionality
  # ============================================================

  shared_examples "basic initialization" do
    it "accepts template and destination content" do
      merger = described_class.new(template_content, dest_content)
      expect(merger).to be_a(described_class)
    end

    it "has template_analysis" do
      merger = described_class.new(template_content, dest_content)
      expect(merger.template_analysis).to be_a(Rbs::Merge::FileAnalysis)
    end

    it "has dest_analysis" do
      merger = described_class.new(template_content, dest_content)
      expect(merger.dest_analysis).to be_a(Rbs::Merge::FileAnalysis)
    end

    it "accepts optional preference" do
      merger = described_class.new(template_content, dest_content, preference: :template)
      expect(merger.preference).to eq(:template)
    end
  end

  shared_examples "merge with identical files" do
    context "with identical files" do
      let(:identical_content) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it "returns content unchanged" do
        merger = described_class.new(identical_content, identical_content)
        result = merger.merge
        expect(result).to eq(identical_content)
      end
    end
  end

  shared_examples "merge with added declarations" do
    context "when destination has additional declarations" do
      let(:template_simple) do
        <<~RBS
          class Foo
            def foo: () -> void
          end
        RBS
      end

      let(:dest_with_extra) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          class Bar
            def bar: () -> void
          end
        RBS
      end

      it "preserves destination additions" do
        merger = described_class.new(template_simple, dest_with_extra)
        result = merger.merge
        expect(result).to include("class Bar")
        expect(result).to include("def bar")
      end
    end
  end

  shared_examples "merge with freeze blocks" do
    context "with freeze blocks" do
      let(:template_with_freeze) do
        <<~RBS
          # rbs-merge:freeze
          class Frozen
            def frozen_method: () -> void
          end
          # rbs-merge:unfreeze

          class Normal
            def normal_method: () -> void
          end
        RBS
      end

      let(:dest_modified) do
        <<~RBS
          class Frozen
            def modified_method: () -> void
          end

          class Normal
            def other_method: () -> void
          end
        RBS
      end

      it "preserves frozen content from template" do
        merger = described_class.new(template_with_freeze, dest_modified)
        result = merger.merge
        expect(result).to include("frozen_method")
      end
    end
  end

  # ============================================================
  # :auto backend tests (uses whatever is available)
  # ============================================================

  context "with :auto backend", :rbs_parsing do
    describe "#initialize" do
      it_behaves_like "basic initialization"

      context "with invalid template" do
        it_behaves_like "invalid template detection"
      end

      context "with invalid destination" do
        it_behaves_like "invalid destination detection"
      end
    end

    describe "#merge" do
      it_behaves_like "merge with identical files"
      it_behaves_like "merge with added declarations"
      it_behaves_like "merge with freeze blocks"
    end
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

    describe "#initialize" do
      it_behaves_like "basic initialization"

      context "with invalid template" do
        it_behaves_like "invalid template detection"
      end

      context "with invalid destination" do
        it_behaves_like "invalid destination detection"
      end
    end

    describe "#merge" do
      it_behaves_like "merge with identical files"
      it_behaves_like "merge with added declarations"
      it_behaves_like "merge with freeze blocks"
    end
  end

  # ============================================================
  # Explicit tree-sitter backend tests via MRI
  # ============================================================

  context "with explicit tree-sitter backend via MRI", :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    describe "#initialize" do
      it_behaves_like "basic initialization"

      context "with invalid template" do
        it_behaves_like "invalid template detection"
      end

      context "with invalid destination" do
        it_behaves_like "invalid destination detection"
      end
    end

    describe "#merge" do
      it_behaves_like "merge with identical files"
      it_behaves_like "merge with added declarations"
      it_behaves_like "merge with freeze blocks"
    end
  end

  # ============================================================
  # Explicit Java backend tests (JRuby)
  # ============================================================

  context "with explicit Java backend", :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    describe "#initialize" do
      it_behaves_like "basic initialization"

      context "with invalid template" do
        it_behaves_like "invalid template detection"
      end

      context "with invalid destination" do
        it_behaves_like "invalid destination detection"
      end
    end

    describe "#merge" do
      it_behaves_like "merge with identical files"
      it_behaves_like "merge with added declarations"
      it_behaves_like "merge with freeze blocks"
    end
  end

  # ============================================================
  # Explicit Rust backend tests
  # ============================================================

  context "with explicit Rust backend", :rust_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    describe "#initialize" do
      it_behaves_like "basic initialization"

      context "with invalid template" do
        it_behaves_like "invalid template detection"
      end

      context "with invalid destination" do
        it_behaves_like "invalid destination detection"
      end
    end

    describe "#merge" do
      it_behaves_like "merge with identical files"
      it_behaves_like "merge with added declarations"
      it_behaves_like "merge with freeze blocks"
    end
  end

  # ============================================================
  # Explicit FFI backend tests
  # ============================================================

  context "with explicit FFI backend", :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    describe "#initialize" do
      it_behaves_like "basic initialization"

      context "with invalid template" do
        it_behaves_like "invalid template detection"
      end

      context "with invalid destination" do
        it_behaves_like "invalid destination detection"
      end
    end

    describe "#merge" do
      it_behaves_like "merge with identical files"
      it_behaves_like "merge with added declarations"
      it_behaves_like "merge with freeze blocks"
    end
  end
end
