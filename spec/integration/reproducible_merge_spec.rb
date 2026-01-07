# frozen_string_literal: true

require "rbs/merge"
require "ast/merge/rspec/shared_examples"

# Integration specs - works with any RBS parser backend
# Tagged with :rbs_parsing since SmartMerger supports both RBS gem and tree-sitter-rbs
RSpec.describe "RBS reproducible merge", :rbs_parsing do
  let(:fixtures_path) { File.expand_path("../fixtures/reproducible", __dir__) }
  let(:merger_class) { Rbs::Merge::SmartMerger }
  let(:file_extension) { "rbs" }

  describe "basic merge scenarios (destination wins by default)" do
    context "when a method is removed in destination" do
      it_behaves_like "a reproducible merge", "01_method_removed"
    end

    context "when a method is added in destination" do
      it_behaves_like "a reproducible merge", "02_method_added"
    end

    context "when a type signature is changed in destination" do
      it_behaves_like "a reproducible merge", "03_signature_changed"
    end
  end
end
