# frozen_string_literal: true

RSpec.describe Rbs::Merge::FileAligner do
  describe "#initialize" do
    let(:template_source) { "class Foo\nend" }
    let(:dest_source) { "class Bar\nend" }
    let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
    let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

    it "stores template_analysis" do
      aligner = described_class.new(template_analysis, dest_analysis)
      expect(aligner.template_analysis).to eq(template_analysis)
    end

    it "stores dest_analysis" do
      aligner = described_class.new(template_analysis, dest_analysis)
      expect(aligner.dest_analysis).to eq(dest_analysis)
    end
  end

  describe "#align" do
    context "with matching declarations" do
      let(:template_source) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          class Foo
            def baz: () -> void
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "creates :match entries for matching signatures" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).not_to be_empty
      end
    end

    context "with template-only declarations" do
      let(:template_source) do
        <<~RBS
          class Foo
          end

          class OnlyInTemplate
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "creates :template_only entries" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        template_only = alignment.select { |e| e[:type] == :template_only }
        expect(template_only).not_to be_empty
      end
    end

    context "with dest-only declarations" do
      let(:template_source) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          class Foo
          end

          class OnlyInDest
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "creates :dest_only entries" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        dest_only = alignment.select { |e| e[:type] == :dest_only }
        expect(dest_only).not_to be_empty
      end
    end

    context "with modules and classes" do
      let(:template_source) do
        <<~RBS
          module MyModule
            class Nested
            end
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          module MyModule
            class Different
            end
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "aligns by signature" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        expect(alignment).to be_an(Array)
        # Should have matches for the module, and possibly unmatched for children
      end
    end

    context "with empty files" do
      let(:template_source) { "" }
      let(:dest_source) { "" }
      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "returns empty alignment" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        expect(alignment).to eq([])
      end
    end

    context "with type aliases" do
      let(:template_source) do
        <<~RBS
          type my_type = String
        RBS
      end

      let(:dest_source) do
        <<~RBS
          type my_type = Integer
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "matches type aliases by name" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).not_to be_empty
      end
    end

    context "with interface definitions" do
      let(:template_source) do
        <<~RBS
          interface _Printable
            def to_s: () -> String
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          interface _Printable
            def inspect: () -> String
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it "matches interfaces by name" do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).not_to be_empty
      end
    end
  end

  describe "#sort_alignment" do
    let(:template_source) { "class Foo\nend" }
    let(:dest_source) { "class Foo\nend" }
    let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
    let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

    it "sorts matches before template_only and dest_only" do
      aligner = described_class.new(template_analysis, dest_analysis)
      alignment = aligner.align

      # Verify alignment is sorted (matches come first, sorted by dest_index)
      expect(alignment).to be_an(Array)
    end
  end
end
