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
        @emitted_freeze_blocks = {}
      end

      # Add content from the template at the given statement index
      # @param index [Integer] Statement index in template
      # @param decision [Symbol] Decision type (default: DECISION_TEMPLATE)
      # @return [void]
      def add_from_template(index, decision: DECISION_TEMPLATE, comment_source_statement: nil, comment_source_analysis: nil)
        statement = @template_analysis.statements[index]
        return unless statement

        lines = extract_lines(
          statement,
          @template_analysis,
          comment_source_statement: comment_source_statement,
          comment_source_analysis: comment_source_analysis,
        )
        @lines.concat(lines)
        @decisions << {decision: decision, source: :template, index: index, lines: lines.length}
      end

      # Add content from the destination at the given statement index
      # @param index [Integer] Statement index in destination
      # @param decision [Symbol] Decision type (default: DECISION_DESTINATION)
      # @return [void]
      def add_from_destination(index, decision: DECISION_DESTINATION, comment_source_statement: nil, comment_source_analysis: nil)
        statement = @dest_analysis.statements[index]
        return unless statement

        lines = extract_lines(
          statement,
          @dest_analysis,
          comment_source_statement: comment_source_statement,
          comment_source_analysis: comment_source_analysis,
        )
        @lines.concat(lines)
        @decisions << {decision: decision, source: :destination, index: index, lines: lines.length}
      end

      # Add content from a freeze block
      # @param freeze_node [FreezeNode] The freeze block to add
      # @return [void]
      def add_freeze_block(freeze_node)
        # Use the freeze_node's own analysis to get the correct content
        # (template freeze blocks should use template lines, dest freeze blocks use dest lines)
        source_analysis = freeze_node.analysis
        freeze_key = [source_analysis.object_id, freeze_node.start_line, freeze_node.end_line]
        return if @emitted_freeze_blocks[freeze_key]

        lines = extract_lines(freeze_node, source_analysis)
        @lines.concat(lines)
        @emitted_freeze_blocks[freeze_key] = true

        # Determine source based on which analysis the freeze_node belongs to
        source = (source_analysis == @template_analysis) ? :template : :destination

        @decisions << {
          decision: DECISION_FREEZE_BLOCK,
          source: source,
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
      # @param statement [Object] The statement (declaration, member, FreezeNode, or NodeWrapper)
      # @param analysis [FileAnalysis] The file analysis
      # @return [Array<String>] Lines for the statement
      def extract_lines(statement, analysis, comment_source_statement: nil, comment_source_analysis: nil)
        # Support NodeWrapper, FreezeNode, and raw RBS nodes via shared start/end APIs.
        start_line = get_start_line(statement)
        end_line = get_end_line(statement)

        return [] unless start_line && end_line

        leading_region, leading_analysis, leading_statement = preferred_leading_region(
          statement,
          analysis,
          comment_source_statement: comment_source_statement,
          comment_source_analysis: comment_source_analysis,
        )
        if leading_region && leading_statement
          region_start = region_start_line(leading_region)
          source_start = get_start_line(leading_statement)

          if region_start && source_start && region_start < source_start
            leading_start = preceding_blank_line_start(region_start, leading_analysis)
            leading_lines = (leading_start...source_start).filter_map { |ln| leading_analysis.line_at(ln) }
            body_lines = (start_line..end_line).map { |ln| analysis.line_at(ln) }
            return leading_lines + body_lines
          end
        elsif statement.respond_to?(:comment) && statement.comment
          comment_start = statement.comment.location&.start_line
          start_line = comment_start if comment_start && comment_start < start_line
        end

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def preferred_leading_region(statement, analysis, comment_source_statement: nil, comment_source_analysis: nil)
        primary_region = leading_region_for(statement, analysis)
        return [primary_region, analysis, statement] if region_present?(primary_region)

        if comment_source_statement && comment_source_analysis
          source_region = leading_region_for(comment_source_statement, comment_source_analysis)
          return [source_region, comment_source_analysis, comment_source_statement] if region_present?(source_region)
        end

        [nil, analysis, statement]
      end

      def leading_region_for(statement, analysis)
        return unless statement && analysis && analysis.respond_to?(:comment_attachment_for)

        attachment = analysis.comment_attachment_for(statement)
        attachment.leading_region if attachment.respond_to?(:leading_region)
      end

      def region_present?(region)
        return false unless region
        return !region.empty? if region.respond_to?(:empty?)
        return region.nodes.any? if region.respond_to?(:nodes)

        true
      end

      def region_start_line(region)
        return region.start_line if region.respond_to?(:start_line) && region.start_line
        return unless region.respond_to?(:nodes)

        region.nodes.filter_map { |node| node.respond_to?(:line_number) ? node.line_number : nil }.min
      end

      def preceding_blank_line_start(region_start, analysis)
        line_num = region_start
        while line_num > 1
          previous_line = analysis.line_at(line_num - 1)
          break unless previous_line && previous_line.strip.empty?

          line_num -= 1
        end

        line_num
      end

      # Get start line for a statement (works with both backends)
      # @param statement [Object] The statement
      # @return [Integer, nil]
      def get_start_line(statement)
        if statement.respond_to?(:start_line)
          statement.start_line
        elsif statement.respond_to?(:location) && statement.location
          statement.location.start_line
        end
      end

      # Get end line for a statement (works with both backends)
      # @param statement [Object] The statement
      # @return [Integer, nil]
      def get_end_line(statement)
        if statement.respond_to?(:end_line)
          statement.end_line
        elsif statement.respond_to?(:location) && statement.location
          statement.location.end_line
        end
      end
    end
  end
end
