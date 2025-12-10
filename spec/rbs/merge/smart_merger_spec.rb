# frozen_string_literal: true

RSpec.describe Rbs::Merge::SmartMerger do
  describe "#initialize" do
    let(:template) { "class Foo\nend\n" }
    let(:destination) { "class Bar\nend\n" }

    it "creates a merger" do
      merger = described_class.new(template, destination)
      expect(merger).to be_a(described_class)
    end

    it "has template_analysis" do
      merger = described_class.new(template, destination)
      expect(merger.template_analysis).to be_a(Rbs::Merge::FileAnalysis)
    end

    it "has dest_analysis" do
      merger = described_class.new(template, destination)
      expect(merger.dest_analysis).to be_a(Rbs::Merge::FileAnalysis)
    end

    context "with invalid template" do
      let(:invalid_template) { "class Foo\n  def bar: (\nend\n" }

      it "raises TemplateParseError" do
        expect { described_class.new(invalid_template, destination) }
          .to raise_error(Rbs::Merge::TemplateParseError)
      end
    end

    context "with invalid destination" do
      let(:invalid_destination) { "class Bar\n  invalid syntax\nend\n" }

      it "raises DestinationParseError" do
        expect { described_class.new(template, invalid_destination) }
          .to raise_error(Rbs::Merge::DestinationParseError)
      end
    end
  end

  describe "#merge" do
    context "with identical files" do
      let(:content) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it "returns destination content" do
        merger = described_class.new(content, content)
        result = merger.merge_result
        expect(result.to_s).to eq(content)
      end
    end

    context "with destination-only declarations" do
      let(:template) { "class Foo\nend\n" }
      let(:destination) do
        <<~RBS
          class Foo
          end

          class Bar
          end
        RBS
      end

      it "preserves destination-only declarations" do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include("class Bar")
      end
    end

    context "with template-only declarations" do
      let(:template) do
        <<~RBS
          class Foo
          end

          class NewClass
          end
        RBS
      end
      let(:destination) { "class Foo\nend\n" }

      context "when add_template_only_nodes is false (default)" do
        it "does not add template-only declarations" do
          merger = described_class.new(template, destination)
          result = merger.merge_result
          expect(result.to_s).not_to include("NewClass")
        end
      end

      context "when add_template_only_nodes is true" do
        it "adds template-only declarations" do
          merger = described_class.new(template, destination, add_template_only_nodes: true)
          result = merger.merge_result
          expect(result.to_s).to include("NewClass")
        end
      end
    end

    context "with matching declarations (different content)" do
      let(:template) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end
      let(:destination) do
        <<~RBS
          class Foo
            def bar: (Integer) -> String
          end
        RBS
      end

      context "when preference is :destination (default)" do
        it "uses destination version" do
          merger = described_class.new(template, destination)
          result = merger.merge_result
          expect(result.to_s).to include("(Integer) -> String")
          expect(result.to_s).not_to include("(String) -> Integer")
        end
      end

      context "when preference is :template" do
        it "uses template version" do
          merger = described_class.new(template, destination, preference: :template)
          result = merger.merge_result
          expect(result.to_s).to include("(String) -> Integer")
          expect(result.to_s).not_to include("(Integer) -> String")
        end
      end
    end

    context "with freeze blocks" do
      let(:template) do
        <<~RBS
          class Foo
            def bar: (String) -> void
          end

          type my_type = Integer
        RBS
      end
      let(:destination) do
        <<~RBS
          class Foo
            def bar: (Integer) -> void
          end

          # rbs-merge:freeze
          type my_type = String | Symbol
          # rbs-merge:unfreeze
        RBS
      end

      it "preserves freeze block content" do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include("type my_type = String | Symbol")
        expect(result.to_s).to include("rbs-merge:freeze")
      end

      it "respects destination preference for matched declarations" do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include("(Integer) -> void")
      end
    end

    context "with custom freeze token" do
      let(:template) { "type foo = String\n" }
      let(:destination) do
        <<~RBS
          # custom:freeze
          type foo = Integer
          # custom:unfreeze
        RBS
      end

      it "recognizes custom freeze token" do
        merger = described_class.new(template, destination, freeze_token: "custom")
        result = merger.merge_result
        expect(result.to_s).to include("type foo = Integer")
        expect(result.to_s).to include("custom:freeze")
      end
    end

    context "with multiple declaration types" do
      let(:template) do
        <<~RBS
          class MyClass
            VERSION: String
          end

          module MyModule
            def foo: () -> void
          end

          interface _MyInterface
            def bar: () -> void
          end

          type my_type = String

          CONST: Integer
        RBS
      end
      let(:destination) do
        <<~RBS
          class MyClass
            VERSION: String
            CUSTOM: Integer
          end

          module MyModule
            def foo: () -> void
            def custom: () -> void
          end

          interface _MyInterface
            def bar: () -> void
          end

          type my_type = String | Integer

          CONST: Integer
        RBS
      end

      it "preserves destination customizations" do
        merger = described_class.new(template, destination)
        result = merger.merge_result

        # Destination additions preserved
        expect(result.to_s).to include("CUSTOM: Integer")
        expect(result.to_s).to include("def custom:")

        # Modified type preserved
        expect(result.to_s).to include("type my_type = String | Integer")
      end
    end
  end

  describe "MergeResult" do
    let(:template) { "class Foo\nend\n" }
    let(:destination) { "class Bar\nend\n" }

    it "tracks decisions" do
      merger = described_class.new(template, destination, add_template_only_nodes: true)
      result = merger.merge_result
      expect(result.decisions).not_to be_empty
    end

    it "provides summary" do
      merger = described_class.new(template, destination, add_template_only_nodes: true)
      result = merger.merge_result
      summary = result.summary
      expect(summary).to have_key(:total_decisions)
      expect(summary).to have_key(:total_lines)
      expect(summary).to have_key(:by_decision)
    end
  end

  describe "custom signature generator" do
    let(:template) do
      <<~RBS
        class Foo
          def method_a: () -> void
        end
      RBS
    end
    let(:destination) do
      <<~RBS
        class Foo
          def method_b: () -> void
        end
      RBS
    end

    it "uses custom generator for matching" do
      # Match by class name only, ignoring members
      custom_gen = lambda do |node|
        case node
        when RBS::AST::Declarations::Class
          [:class, node.name.to_s]
        else
          node
        end
      end

      merger = described_class.new(template, destination, signature_generator: custom_gen)
      result = merger.merge_result

      # Classes match by name, destination wins
      expect(result.to_s).to include("method_b")
    end
  end

  describe "add_template_only_nodes option" do
    let(:template) do
      <<~RBS
        class Foo
        end

        class NewFromTemplate
        end
      RBS
    end
    let(:destination) do
      <<~RBS
        class Foo
        end
      RBS
    end

    context "when add_template_only_nodes is false" do
      it "does not add template-only declarations" do
        merger = described_class.new(template, destination, add_template_only_nodes: false)
        result = merger.merge_result
        expect(result.to_s).not_to include("NewFromTemplate")
      end
    end

    context "when add_template_only_nodes is true" do
      it "adds template-only declarations" do
        merger = described_class.new(template, destination, add_template_only_nodes: true)
        result = merger.merge_result
        expect(result.to_s).to include("NewFromTemplate")
      end
    end
  end

  describe "destination-only freeze blocks" do
    let(:template) { "type my_type = String\n" }
    let(:destination) do
      <<~RBS
        # rbs-merge:freeze
        type my_type = Integer
        # rbs-merge:unfreeze
      RBS
    end

    it "preserves freeze block even when template has matching declaration" do
      merger = described_class.new(template, destination)
      result = merger.merge_result
      expect(result.to_s).to include("rbs-merge:freeze")
      expect(result.to_s).to include("type my_type = Integer")
      expect(result.to_s).to include("rbs-merge:unfreeze")
    end
  end

  describe "process_match with :template resolution" do
    let(:template) { "type my_type = String\n" }
    let(:destination) { "type my_type = Integer\n" }

    it "uses template version when preference is :template" do
      merger = described_class.new(template, destination, preference: :template)
      result = merger.merge_result
      expect(result.to_s).to include("type my_type = String")
      expect(result.to_s).not_to include("type my_type = Integer")
    end
  end

  describe "freeze blocks in dest_only entries" do
    let(:template) { "class Foo\nend\n" }
    let(:destination) do
      <<~RBS
        class Foo
        end

        # rbs-merge:freeze
        type custom = String
        # rbs-merge:unfreeze
      RBS
    end

    it "adds freeze blocks from destination" do
      merger = described_class.new(template, destination)
      result = merger.merge_result
      expect(result.to_s).to include("rbs-merge:freeze")
      expect(result.to_s).to include("type custom = String")
    end
  end

  describe "process_match with freeze block in destination" do
    let(:template) do
      <<~RBS
        type custom = Integer
      RBS
    end
    let(:destination) do
      <<~RBS
        # rbs-merge:freeze
        type custom = String
        # rbs-merge:unfreeze
      RBS
    end

    it "preserves freeze block content over template" do
      merger = described_class.new(template, destination)
      result = merger.merge_result
      expect(result.to_s).to include("rbs-merge:freeze")
      expect(result.to_s).to include("type custom = String")
      expect(result.to_s).not_to include("type custom = Integer")
    end
  end

  describe "reconstruction with comments" do
    let(:template) do
      <<~RBS
        # Template comment
        class Foo
          def bar: () -> void
        end
      RBS
    end
    let(:destination) do
      <<~RBS
        # Destination comment
        class Foo
          def baz: () -> void
        end
      RBS
    end

    it "preserves comments when using template preference" do
      merger = described_class.new(template, destination, preference: :template)
      result = merger.merge_result
      expect(result.to_s).to include("# Template comment")
    end

    it "preserves comments when using destination preference" do
      merger = described_class.new(template, destination, preference: :destination)
      result = merger.merge_result
      expect(result.to_s).to include("# Destination comment")
    end
  end

  describe "merge_result caching" do
    let(:template) { "class Foo\nend\n" }
    let(:destination) { "class Bar\nend\n" }

    it "caches the merge_result on subsequent calls" do
      merger = described_class.new(template, destination)
      result1 = merger.merge_result
      result2 = merger.merge_result
      expect(result1).to be(result2) # Same object identity
    end
  end

  describe "process_match with :template source resolution" do
    let(:template) do
      <<~RBS
        type my_alias = String
      RBS
    end
    let(:destination) do
      <<~RBS
        type my_alias = Integer
      RBS
    end

    it "uses template content when preference is :template" do
      merger = described_class.new(template, destination, preference: :template)
      result = merger.merge_result
      expect(result.to_s).to include("type my_alias = String")
      expect(result.to_s).not_to include("Integer")
    end
  end

  describe "process_match with FreezeNode in matched entry" do
    let(:template) do
      <<~RBS
        type frozen_type = String
      RBS
    end
    let(:destination) do
      <<~RBS
        # rbs-merge:freeze
        type frozen_type = Integer | Symbol
        # rbs-merge:unfreeze
      RBS
    end

    it "uses freeze block content even when template has matching declaration" do
      merger = described_class.new(template, destination)
      result = merger.merge_result
      expect(result.to_s).to include("type frozen_type = Integer | Symbol")
      expect(result.to_s).to include("rbs-merge:freeze")
    end
  end
end
