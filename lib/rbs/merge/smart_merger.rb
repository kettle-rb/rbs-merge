# frozen_string_literal: true

module Rbs
  module Merge
    # Orchestrates the smart merge process for RBS type signature files.
    # Uses FileAnalysis, FileAligner, ConflictResolver, and MergeResult to
    # merge two RBS files intelligently.
    #
    # SmartMerger provides flexible configuration for different merge scenarios.
    # When matching class or module definitions are found in both files, the merger
    # can perform recursive merging of their members.
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example Custom signature matching
    #   sig_gen = ->(node) { [:decl, node.name.to_s] }
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_generator: sig_gen
    #   )
    #
    # @see FileAnalysis
    # @see FileAligner
    # @see ConflictResolver
    # @see MergeResult
    class SmartMerger
      # @return [FileAnalysis] Analysis of the template file
      attr_reader :template_analysis

      # @return [FileAnalysis] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [FileAligner] Aligner for finding matches and differences
      attr_reader :aligner

      # @return [ConflictResolver] Resolver for handling conflicting content
      attr_reader :resolver

      # @return [MergeResult] Result object tracking merged content
      attr_reader :result

      # Creates a new SmartMerger for intelligent RBS file merging.
      #
      # @param template_content [String] Template RBS source code
      # @param dest_content [String] Destination RBS source code
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom node signatures.
      #   The proc receives an RBS declaration and should return one of:
      #   - An array representing the node's signature
      #   - `nil` to indicate the node should have no signature
      #   - The original node to fall through to default signature computation
      #
      # @param preference [Symbol] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations)
      #   - `:template` - Use template version (applies updates)
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add template-only nodes to result
      #
      # @param freeze_token [String] Token to use for freeze block markers.
      #   Default: "rbs-merge" (looks for # rbs-merge:freeze / # rbs-merge:unfreeze)
      #
      # @param max_recursion_depth [Integer, Float] Maximum depth for recursive body merging.
      #   Default: Float::INFINITY (no limit)
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        freeze_token: FileAnalysis::DEFAULT_FREEZE_TOKEN,
        max_recursion_depth: Float::INFINITY
      )
        @preference = preference
        @add_template_only_nodes = add_template_only_nodes
        @max_recursion_depth = max_recursion_depth

        # Parse template
        begin
          @template_analysis = FileAnalysis.new(
            template_content,
            freeze_token: freeze_token,
            signature_generator: signature_generator,
          )
        rescue RBS::ParsingError => e
          raise TemplateParseError.new([e])
        end

        # Parse destination
        begin
          @dest_analysis = FileAnalysis.new(
            dest_content,
            freeze_token: freeze_token,
            signature_generator: signature_generator,
          )
        rescue RBS::ParsingError => e
          raise DestinationParseError.new([e])
        end

        @aligner = FileAligner.new(@template_analysis, @dest_analysis)
        @resolver = ConflictResolver.new(
          preference: @preference,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        )
        @result = MergeResult.new(@template_analysis, @dest_analysis)
      end

      # Perform the merge operation
      #
      # @return [String] The merged content as a string
      def merge
        merge_result.to_s
      end

      # Perform the merge operation and return the full result object
      #
      # @return [MergeResult] The merge result containing merged content
      def merge_result
        return @merge_result if @merge_result

        @merge_result = DebugLogger.time("SmartMerger#merge") do
          alignment = @aligner.align

          DebugLogger.debug("Alignment complete", {
            total_entries: alignment.size,
            matches: alignment.count { |e| e[:type] == :match },
            template_only: alignment.count { |e| e[:type] == :template_only },
            dest_only: alignment.count { |e| e[:type] == :dest_only },
          })

          process_alignment(alignment)
          @result
        end
      end

      private

      # Process alignment entries and build result
      # @param alignment [Array<Hash>] Alignment entries
      # @return [void]
      def process_alignment(alignment)
        alignment.each do |entry|
          case entry[:type]
          when :match
            process_match(entry)
          when :template_only
            process_template_only(entry)
          when :dest_only
            process_dest_only(entry)
          end
        end
      end

      # Process a matched declaration pair
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_match(entry)
        resolution = @resolver.resolve(
          entry[:template_decl],
          entry[:dest_decl],
          template_index: entry[:template_index],
          dest_index: entry[:dest_index],
        )

        case resolution[:source]
        when :template
          @result.add_from_template(entry[:template_index], decision: resolution[:decision])
        when :destination
          if entry[:dest_decl].is_a?(FreezeNode)
            @result.add_freeze_block(entry[:dest_decl])
          else
            @result.add_from_destination(entry[:dest_index], decision: resolution[:decision])
          end
        when :recursive
          process_recursive_merge(entry, resolution)
        end
      end

      # Process a template-only declaration
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_template_only(entry)
        return unless @add_template_only_nodes

        @result.add_from_template(entry[:template_index], decision: MergeResult::DECISION_ADDED)
      end

      # Process a destination-only declaration
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_dest_only(entry)
        if entry[:dest_decl].is_a?(FreezeNode)
          @result.add_freeze_block(entry[:dest_decl])
        else
          @result.add_from_destination(entry[:dest_index], decision: MergeResult::DECISION_DESTINATION)
        end
      end

      # Process recursive merge for container declarations
      # @param entry [Hash] Alignment entry
      # @param resolution [Hash] Resolution info
      # @return [void]
      def process_recursive_merge(entry, resolution)
        template_decl = resolution[:template_declaration]
        dest_decl = resolution[:dest_declaration]

        # For now, just use the destination version for complex recursive merges
        # A full recursive implementation would merge members individually
        merged_content = reconstruct_declaration_with_merged_members(
          template_decl,
          dest_decl,
          entry[:template_index],
          entry[:dest_index],
        )

        @result.add_recursive_merge(
          merged_content,
          template_index: entry[:template_index],
          dest_index: entry[:dest_index],
        )
      end

      # Reconstruct a declaration with merged members
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @param template_index [Integer] Template index
      # @param dest_index [Integer] Destination index
      # @return [String] Merged declaration source
      def reconstruct_declaration_with_merged_members(template_decl, dest_decl, template_index, dest_index)
        # Choose which declaration to use based on preference
        decl = (@preference == :template) ? template_decl : dest_decl
        analysis = (@preference == :template) ? @template_analysis : @dest_analysis

        start_line = decl.location.start_line
        end_line = decl.location.end_line

        # Include leading comment if present
        if decl.respond_to?(:comment) && decl.comment
          comment_start = decl.comment.location.start_line
          start_line = comment_start if comment_start < start_line
        end

        (start_line..end_line).map { |ln| analysis.line_at(ln) }.join("\n") + "\n"
      end
    end
  end
end
