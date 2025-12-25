# frozen_string_literal: true

module Rbs
  module Merge
    # Result container for RBS file merge operations.
    # Inherits from Ast::Merge::MergeResultBase for shared functionality.
    #
    # Tracks merged content, decisions made during merge, and provides
    # methods to reconstruct the final merged RBS file.
    #
    # @example Basic usage
    #   result = MergeResult.new(template_analysis, dest_analysis)
    #   result.add_from_template(0)
    #   result.add_from_destination(1)
    #   merged_content = result.to_s
    #
    # @see Ast::Merge::MergeResultBase
    class MergeResult < Ast::Merge::MergeResultBase
      # Decision indicating content was preserved from a freeze block
      # @return [Symbol]
      DECISION_FREEZE_BLOCK = :freeze_block

      # Decision indicating content came from the template
      # @return [Symbol]
      DECISION_TEMPLATE = :template

      # Decision indicating content came from the destination (customization preserved)
      # @return [Symbol]
      DECISION_DESTINATION = :destination

      # Decision indicating content was added from template (new in template)
      # @return [Symbol]
      DECISION_ADDED = :added

      # Decision indicating content was recursively merged
      # @return [Symbol]
      DECISION_RECURSIVE = :recursive

      # Initialize a new merge result
      # @param template_analysis [FileAnalysis] Analysis of the template file
      # @param dest_analysis [FileAnalysis] Analysis of the destination file
      # @param options [Hash] Additional options for forward compatibility
      def initialize(template_analysis, dest_analysis, **options)
        super(template_analysis: template_analysis, dest_analysis: dest_analysis, **options)
      end

      # Add content from the template at the given statement index
      # @param index [Integer] Statement index in template
      # @param decision [Symbol] Decision type (default: DECISION_TEMPLATE)
      # @return [void]
      def add_from_template(index, decision: DECISION_TEMPLATE)
        statement = @template_analysis.statements[index]
        return unless statement

        lines = extract_lines(statement, @template_analysis)
        @lines.concat(lines)
        @decisions << {decision: decision, source: :template, index: index, lines: lines.length}
      end

      # Add content from the destination at the given statement index
      # @param index [Integer] Statement index in destination
      # @param decision [Symbol] Decision type (default: DECISION_DESTINATION)
      # @return [void]
      def add_from_destination(index, decision: DECISION_DESTINATION)
        statement = @dest_analysis.statements[index]
        return unless statement

        lines = extract_lines(statement, @dest_analysis)
        @lines.concat(lines)
        @decisions << {decision: decision, source: :destination, index: index, lines: lines.length}
      end

      # Add content from a freeze block
      # @param freeze_node [FreezeNode] The freeze block to add
      # @return [void]
      def add_freeze_block(freeze_node)
        lines = (freeze_node.start_line..freeze_node.end_line).map do |ln|
          @dest_analysis.line_at(ln)
        end
        @lines.concat(lines)
        @decisions << {
          decision: DECISION_FREEZE_BLOCK,
          source: :destination,
          start_line: freeze_node.start_line,
          end_line: freeze_node.end_line,
          lines: lines.length,
        }
      end

      # Add recursively merged content
      # @param merged_content [String] The merged content string
      # @param template_index [Integer] Template statement index
      # @param dest_index [Integer] Destination statement index
      # @return [void]
      def add_recursive_merge(merged_content, template_index:, dest_index:)
        # Split without trailing newlines for consistency with other methods
        lines = merged_content.split("\n", -1)
        # Remove trailing empty element if content ended with newline
        lines.pop if lines.last == ""
        @lines.concat(lines)
        @decisions << {
          decision: DECISION_RECURSIVE,
          source: :merged,
          template_index: template_index,
          dest_index: dest_index,
          lines: lines.length,
        }
      end

      # Add raw content lines
      # @param lines [Array<String>] Lines to add
      # @param decision [Symbol] Decision type
      # @return [void]
      def add_raw(lines, decision:)
        @lines.concat(lines)
        @decisions << {decision: decision, source: :raw, lines: lines.length}
      end

      # Convert the merged result to a string
      # @return [String] The merged RBS content
      def to_s
        return "" if @lines.empty?

        # Lines are stored without trailing newlines, so join with newlines
        result = @lines.join("\n")
        # Ensure file ends with newline if content is non-empty
        result += "\n" unless result.end_with?("\n")
        result
      end

      # Check if any content has been added
      # @return [Boolean]
      def empty?
        @lines.empty?
      end

      # Get summary of merge decisions
      # @return [Hash] Summary with counts by decision type
      def summary
        counts = @decisions.group_by { |d| d[:decision] }.transform_values(&:count)
        {
          total_decisions: @decisions.length,
          total_lines: @lines.length,
          by_decision: counts,
        }
      end

      private

      # Extract lines for a statement from analysis
      # @param statement [Object] The statement (declaration, member, or FreezeNode)
      # @param analysis [FileAnalysis] The file analysis
      # @return [Array<String>] Lines for the statement
      def extract_lines(statement, analysis)
        if statement.is_a?(FreezeNode)
          (statement.start_line..statement.end_line).map { |ln| analysis.line_at(ln) }
        else
          start_line = statement.location.start_line
          end_line = statement.location.end_line

          # Include leading comment if present
          if statement.respond_to?(:comment) && statement.comment
            comment_start = statement.comment.location.start_line
            start_line = comment_start if comment_start < start_line
          end

          (start_line..end_line).map { |ln| analysis.line_at(ln) }
        end
      end
    end
  end
end
