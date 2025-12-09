# frozen_string_literal: true

RSpec.describe Rbs::Merge::FileAnalysis do
  describe "#initialize" do
    context "with valid RBS source" do
      let(:source) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end

      it "parses successfully" do
        analysis = described_class.new(source)
        expect(analysis.valid?).to be true
      end

      it "extracts declarations" do
        analysis = described_class.new(source)
        expect(analysis.declarations.size).to eq(1)
        expect(analysis.declarations.first).to be_a(RBS::AST::Declarations::Class)
      end

      it "stores source lines" do
        analysis = described_class.new(source)
        expect(analysis.lines.size).to eq(4)
      end
    end

    context "with comments" do
      let(:source) do
        <<~RBS
          # A sample class
          class Foo
            # A method
            def bar: (String) -> Integer
          end
        RBS
      end

      it "attaches comments to declarations" do
        analysis = described_class.new(source)
        decl = analysis.declarations.first
        expect(decl.comment).not_to be_nil
        expect(decl.comment.string).to include("sample class")
      end

      it "attaches comments to members" do
        analysis = described_class.new(source)
        decl = analysis.declarations.first
        method_def = decl.members.first
        expect(method_def.comment).not_to be_nil
        expect(method_def.comment.string).to include("method")
      end
    end

    context "with multiple declarations" do
      let(:source) do
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
        analysis = described_class.new(source)
        expect(analysis.declarations.size).to eq(5)

        classes = analysis.declarations.select { |d| d.is_a?(RBS::AST::Declarations::Class) }
        modules = analysis.declarations.select { |d| d.is_a?(RBS::AST::Declarations::Module) }
        interfaces = analysis.declarations.select { |d| d.is_a?(RBS::AST::Declarations::Interface) }
        type_aliases = analysis.declarations.select { |d| d.is_a?(RBS::AST::Declarations::TypeAlias) }
        constants = analysis.declarations.select { |d| d.is_a?(RBS::AST::Declarations::Constant) }

        expect(classes.size).to eq(1)
        expect(modules.size).to eq(1)
        expect(interfaces.size).to eq(1)
        expect(type_aliases.size).to eq(1)
        expect(constants.size).to eq(1)
      end
    end

    context "with freeze blocks" do
      let(:source) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          # rbs-merge:freeze
          # Custom type
          type custom = String
          # rbs-merge:unfreeze

          class Bar
            def bar: () -> void
          end
        RBS
      end

      it "detects freeze blocks" do
        analysis = described_class.new(source)
        expect(analysis.freeze_blocks.size).to eq(1)
      end

      it "extracts freeze block content" do
        analysis = described_class.new(source)
        freeze_block = analysis.freeze_blocks.first
        expect(freeze_block.start_line).to eq(5)
        expect(freeze_block.end_line).to eq(8)
      end

      it "includes freeze blocks in statements" do
        analysis = described_class.new(source)
        # Should have: Foo class, freeze block, Bar class
        expect(analysis.statements.size).to eq(3)
        expect(analysis.statements[1]).to be_a(Rbs::Merge::FreezeNode)
      end

      it "removes frozen declarations from regular statements" do
        analysis = described_class.new(source)
        # The type alias is inside the freeze block, so it should only appear there
        type_aliases = analysis.statements.select { |s| s.is_a?(RBS::AST::Declarations::TypeAlias) }
        expect(type_aliases).to be_empty
      end
    end

    context "with custom freeze token" do
      let(:source) do
        <<~RBS
          # my-token:freeze
          class Foo
            def foo: () -> void
          end
          # my-token:unfreeze
        RBS
      end

      it "detects custom freeze tokens" do
        analysis = described_class.new(source, freeze_token: "my-token")
        expect(analysis.freeze_blocks.size).to eq(1)
      end

      it "ignores mismatched freeze tokens" do
        analysis = described_class.new(source, freeze_token: "other-token")
        expect(analysis.freeze_blocks).to be_empty
      end
    end
  end

  describe "#line_at" do
    let(:source) { "class Foo\nend\n" }
    let(:analysis) { described_class.new(source) }

    it "returns the correct line (1-indexed)" do
      expect(analysis.line_at(1)).to eq("class Foo")
      expect(analysis.line_at(2)).to eq("end")
    end

    it "returns nil for out of range" do
      expect(analysis.line_at(0)).to be_nil
      expect(analysis.line_at(100)).to be_nil
    end
  end

  describe "#normalized_line" do
    let(:source) { "  class Foo  \nend\n" }
    let(:analysis) { described_class.new(source) }

    it "returns stripped line" do
      expect(analysis.normalized_line(1)).to eq("class Foo")
    end
  end

  describe "#signature_at" do
    let(:source) do
      <<~RBS
        class Foo
          def bar: () -> void
        end

        module Baz
        end
      RBS
    end
    let(:analysis) { described_class.new(source) }

    it "returns class signature" do
      expect(analysis.signature_at(0)).to eq([:class, "Foo"])
    end

    it "returns module signature" do
      expect(analysis.signature_at(1)).to eq([:module, "Baz"])
    end

    it "returns nil for out of range" do
      expect(analysis.signature_at(-1)).to be_nil
      expect(analysis.signature_at(100)).to be_nil
    end
  end

  describe "#compute_node_signature" do
    let(:source) do
      <<~RBS
        class MyClass
        end

        module MyModule
        end

        interface _MyInterface
        end

        type my_alias = String

        CONST: Integer

        $global: String
      RBS
    end
    let(:analysis) { described_class.new(source) }

    it "computes class signature" do
      decl = analysis.declarations.find { |d| d.is_a?(RBS::AST::Declarations::Class) }
      expect(analysis.compute_node_signature(decl)).to eq([:class, "MyClass"])
    end

    it "computes module signature" do
      decl = analysis.declarations.find { |d| d.is_a?(RBS::AST::Declarations::Module) }
      expect(analysis.compute_node_signature(decl)).to eq([:module, "MyModule"])
    end

    it "computes interface signature" do
      decl = analysis.declarations.find { |d| d.is_a?(RBS::AST::Declarations::Interface) }
      expect(analysis.compute_node_signature(decl)).to eq([:interface, "_MyInterface"])
    end

    it "computes type alias signature" do
      decl = analysis.declarations.find { |d| d.is_a?(RBS::AST::Declarations::TypeAlias) }
      expect(analysis.compute_node_signature(decl)).to eq([:type_alias, "my_alias"])
    end

    it "computes constant signature" do
      decl = analysis.declarations.find { |d| d.is_a?(RBS::AST::Declarations::Constant) }
      expect(analysis.compute_node_signature(decl)).to eq([:constant, "CONST"])
    end

    it "computes global signature" do
      decl = analysis.declarations.find { |d| d.is_a?(RBS::AST::Declarations::Global) }
      expect(analysis.compute_node_signature(decl)).to eq([:global, "$global"])
    end
  end

  describe "#generate_signature with custom generator" do
    let(:source) do
      <<~RBS
        class Foo
        end

        class Bar
        end
      RBS
    end

    it "uses custom generator when provided" do
      custom_generator = ->(node) { [:custom, node.name.to_s.upcase] }
      analysis = described_class.new(source, signature_generator: custom_generator)

      expect(analysis.signature_at(0)).to eq([:custom, "FOO"])
      expect(analysis.signature_at(1)).to eq([:custom, "BAR"])
    end

    it "falls through to default when generator returns node" do
      custom_generator = ->(node) { node }
      analysis = described_class.new(source, signature_generator: custom_generator)

      expect(analysis.signature_at(0)).to eq([:class, "Foo"])
    end

    it "returns nil when generator returns nil" do
      custom_generator = ->(_node) { nil }
      analysis = described_class.new(source, signature_generator: custom_generator)

      expect(analysis.signature_at(0)).to be_nil
    end
  end

  describe "#compute_node_signature for members" do
    context "with method definitions" do
      let(:source) do
        <<~RBS
          class Foo
            def bar: () -> void
            def self.baz: () -> void
          end
        RBS
      end
      let(:analysis) { described_class.new(source) }

      it "computes instance method signature" do
        decl = analysis.declarations.first
        method_def = decl.members.find { |m| m.is_a?(RBS::AST::Members::MethodDefinition) && m.kind == :instance }
        expect(analysis.compute_node_signature(method_def)).to eq([:method, "bar", :instance])
      end

      it "computes singleton method signature" do
        decl = analysis.declarations.first
        method_def = decl.members.find { |m| m.is_a?(RBS::AST::Members::MethodDefinition) && m.kind == :singleton }
        expect(analysis.compute_node_signature(method_def)).to eq([:method, "baz", :singleton])
      end
    end

    context "with alias members" do
      let(:source) do
        <<~RBS
          class Foo
            def bar: () -> void
            alias baz bar
          end
        RBS
      end
      let(:analysis) { described_class.new(source) }

      it "computes alias signature" do
        decl = analysis.declarations.first
        alias_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::Alias) }
        expect(analysis.compute_node_signature(alias_member)).to eq([:alias, "baz", "bar"])
      end
    end

    context "with attr members" do
      let(:source) do
        <<~RBS
          class Foo
            attr_reader name: String
            attr_writer age: Integer
            attr_accessor value: Float
          end
        RBS
      end
      let(:analysis) { described_class.new(source) }

      it "computes attr_reader signature" do
        decl = analysis.declarations.first
        attr_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::AttrReader) }
        expect(analysis.compute_node_signature(attr_member)).to eq([:attr_reader, "name"])
      end

      it "computes attr_writer signature" do
        decl = analysis.declarations.first
        attr_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::AttrWriter) }
        expect(analysis.compute_node_signature(attr_member)).to eq([:attr_writer, "age"])
      end

      it "computes attr_accessor signature" do
        decl = analysis.declarations.first
        attr_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::AttrAccessor) }
        expect(analysis.compute_node_signature(attr_member)).to eq([:attr_accessor, "value"])
      end
    end

    context "with mixin members" do
      let(:source) do
        <<~RBS
          class Foo
            include Bar
            extend Baz
            prepend Qux
          end
        RBS
      end
      let(:analysis) { described_class.new(source) }

      it "computes include signature" do
        decl = analysis.declarations.first
        include_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::Include) }
        expect(analysis.compute_node_signature(include_member)).to eq([:include, "Bar"])
      end

      it "computes extend signature" do
        decl = analysis.declarations.first
        extend_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::Extend) }
        expect(analysis.compute_node_signature(extend_member)).to eq([:extend, "Baz"])
      end

      it "computes prepend signature" do
        decl = analysis.declarations.first
        prepend_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::Prepend) }
        expect(analysis.compute_node_signature(prepend_member)).to eq([:prepend, "Qux"])
      end
    end

    context "with variable members" do
      let(:source) do
        <<~RBS
          class Foo
            @instance_var: String
            self.@class_instance_var: Integer
            @@class_var: Float
          end
        RBS
      end
      let(:analysis) { described_class.new(source) }

      it "computes instance variable signature" do
        decl = analysis.declarations.first
        ivar_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::InstanceVariable) }
        expect(analysis.compute_node_signature(ivar_member)).to eq([:ivar, "@instance_var"])
      end

      it "computes class instance variable signature" do
        decl = analysis.declarations.first
        civar_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::ClassInstanceVariable) }
        expect(analysis.compute_node_signature(civar_member)).to eq([:civar, "@class_instance_var"])
      end

      it "computes class variable signature" do
        decl = analysis.declarations.first
        cvar_member = decl.members.find { |m| m.is_a?(RBS::AST::Members::ClassVariable) }
        expect(analysis.compute_node_signature(cvar_member)).to eq([:cvar, "@@class_var"])
      end
    end

    context "with unknown node type" do
      it "returns unknown signature with class name and location" do
        # Create a mock object that doesn't match any known type
        unknown_node = double("UnknownNode", class: Class.new { def name = "UnknownType" }.new, location: double(start_line: 42))
        analysis = described_class.new("class Foo\nend\n")

        signature = analysis.compute_node_signature(unknown_node)
        expect(signature[0]).to eq(:unknown)
      end
    end
  end

  describe "freeze marker edge cases" do
    context "with unmatched freeze end marker" do
      let(:source) do
        <<~RBS
          class Foo
          end
          # rbs-merge:unfreeze
        RBS
      end

      it "warns about unmatched end marker but still parses" do
        expect(Rbs::Merge::DebugLogger).to receive(:warning).with(/Unmatched freeze end marker/)
        analysis = described_class.new(source)
        expect(analysis.valid?).to be true
        expect(analysis.statements.size).to eq(1)
      end
    end

    context "with unmatched freeze start marker" do
      let(:source) do
        <<~RBS
          # rbs-merge:freeze
          class Foo
          end
        RBS
      end

      it "warns about unmatched start marker but still parses" do
        expect(Rbs::Merge::DebugLogger).to receive(:warning).with(/Unmatched freeze start marker/)
        analysis = described_class.new(source)
        expect(analysis.valid?).to be true
      end
    end

    context "with invalid marker type" do
      let(:source) do
        <<~RBS
          # rbs-merge:invalid
          class Foo
          end
        RBS
      end

      it "ignores invalid marker types" do
        analysis = described_class.new(source)
        expect(analysis.valid?).to be true
        # No freeze blocks created for invalid marker
        expect(analysis.statements.none? { |s| s.is_a?(Rbs::Merge::FreezeNode) }).to be true
      end
    end

    context "with no freeze markers" do
      let(:source) do
        <<~RBS
          class Foo
          end
          class Bar
          end
        RBS
      end

      it "returns declarations without modification" do
        analysis = described_class.new(source)
        expect(analysis.statements.size).to eq(2)
        expect(analysis.statements).to all(be_a(RBS::AST::Declarations::Class))
      end
    end
  end
end
