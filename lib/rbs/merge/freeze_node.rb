# frozen_string_literal: true

module Rbs
  module Merge
    # Wrapper to represent freeze blocks as first-class nodes in RBS files.
    # A freeze block is a section marked with freeze/unfreeze comment markers that
    # should be preserved from the destination during merges.
    #
    # Inherits from Ast::Merge::FreezeNodeBase for shared functionality including
    # the Location struct, InvalidStructureError, and configurable marker patterns.
    #
    # Uses the `:hash_comment` pattern type by default for RBS type signature files.
    #
    # @example Freeze block in RBS
    #   # rbs-merge:freeze
    #   # Custom type definitions
    #   type custom_config = { key: String, value: untyped }
    #   # rbs-merge:unfreeze
    #
    # @example Freeze block with reason
    #   # rbs-merge:freeze Project-specific types
    #   type project_result = success | failure
    #   # rbs-merge:unfreeze
    class FreezeNode < Ast::Merge::FreezeNodeBase
      # Inherit InvalidStructureError from base class
      InvalidStructureError = Ast::Merge::FreezeNodeBase::InvalidStructureError

      # Inherit Location from base class
      Location = Ast::Merge::FreezeNodeBase::Location

      # @param start_line [Integer] Line number of freeze marker
      # @param end_line [Integer] Line number of unfreeze marker
      # @param analysis [FileAnalysis] The file analysis containing this block
      # @param nodes [Array<RBS::AST::Declarations::Base, RBS::AST::Members::Base>] Nodes fully contained within the freeze block
      # @param overlapping_nodes [Array] All nodes that overlap with freeze block (for validation)
      # @param start_marker [String, nil] The freeze start marker text
      # @param end_marker [String, nil] The freeze end marker text
      # @param pattern_type [Symbol] Pattern type for marker matching (defaults to :hash_comment)
      def initialize(start_line:, end_line:, analysis:, nodes: [], overlapping_nodes: nil, start_marker: nil, end_marker: nil, pattern_type: Ast::Merge::FreezeNodeBase::DEFAULT_PATTERN)
        super(
          start_line: start_line,
          end_line: end_line,
          analysis: analysis,
          nodes: nodes,
          overlapping_nodes: overlapping_nodes || nodes,
          start_marker: start_marker,
          end_marker: end_marker,
          pattern_type: pattern_type
        )

        # Validate structure
        validate_structure!
      end

      # Returns a stable signature for this freeze block
      # Signature includes the normalized content to detect changes
      # @return [Array] Signature array
      def signature
        normalized = (@start_line..@end_line).map do |ln|
          @analysis.normalized_line(ln)
        end.compact.join("\n")

        [:FreezeNode, normalized]
      end

      # String representation for debugging
      # @return [String]
      def inspect
        "#<Rbs::Merge::FreezeNode lines=#{@start_line}..#{@end_line} nodes=#{@nodes.length}>"
      end

      private

      # Validate that the freeze block has proper structure:
      # - All nodes must be either fully contained or fully outside
      # - No partial overlaps allowed
      def validate_structure!
        unclosed = []

        @overlapping_nodes.each do |node|
          node_start = node.location.start_line
          node_end = node.location.end_line

          # Check if node is fully contained (valid)
          fully_contained = node_start >= @start_line && node_end <= @end_line

          # Check if node completely encompasses the freeze block
          # This is valid for container nodes like classes/modules
          encompasses = node_start < @start_line && node_end > @end_line

          # Check if node is fully outside (valid)
          fully_outside = node_end < @start_line || node_start > @end_line

          # If none of the above, it's a partial overlap (invalid)
          next if fully_contained || encompasses || fully_outside

          unclosed << node
        end

        return if unclosed.empty?

        node_names = unclosed.map do |n|
          name = n.respond_to?(:name) ? n.name.to_s : n.class.name.split("::").last
          "#{name} (lines #{n.location.start_line}-#{n.location.end_line})"
        end.join(", ")

        raise InvalidStructureError.new(
          "Freeze block at lines #{@start_line}-#{@end_line} has partial overlap with: #{node_names}. " \
            "Freeze blocks must fully contain declarations or be fully contained within them.",
          start_line: @start_line,
          end_line: @end_line,
          unclosed_nodes: unclosed,
        )
      end
    end
  end
end
