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
    # @example With node_typing for per-node-type preferences
    #   merger = SmartMerger.new(template, dest,
    #     node_typing: { "ClassDecl" => ->(n) { NodeTyping.with_merge_type(n, :model) } },
    #     preference: { default: :destination, model: :template })
    #
    # @see FileAnalysis
    # @see FileAligner
    # @see ConflictResolver
    # @see MergeResult
    class SmartMerger < ::Ast::Merge::SmartMergerBase
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
      # @param preference [Symbol, Hash] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations)
      #   - `:template` - Use template version (applies updates)
      #   - Hash for per-type preferences
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add template-only nodes to result
      #
      # @param freeze_token [String] Token to use for freeze block markers.
      #   Default: "rbs-merge" (looks for # rbs-merge:freeze / # rbs-merge:unfreeze)
      #
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
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
        freeze_token: nil,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        max_recursion_depth: Float::INFINITY
      )
        @max_recursion_depth = max_recursion_depth
        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
        )
      end

      protected

      # @return [Class] The analysis class for RBS files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token
      def default_freeze_token
        "rbs-merge"
      end

      # @return [Class, nil] The resolver class for RBS files
      def resolver_class
        ConflictResolver
      end

      # @return [Class, nil] Result class (built with analysis args)
      def result_class
        nil
      end

      # @return [Class] The aligner class for RBS files
      def aligner_class
        FileAligner
      end

      # @return [Class] The template parse error class for RBS
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for RBS
      def destination_parse_error_class
        DestinationParseError
      end

      # Build the result with required analysis arguments
      def build_result
        MergeResult.new(@template_analysis, @dest_analysis)
      end

      # Build the resolver with RBS-specific options
      def build_resolver
        ConflictResolver.new(
          preference: @preference,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        )
      end

      # Build the aligner
      def build_aligner
        FileAligner.new(@template_analysis, @dest_analysis)
      end

      # Perform the RBS-specific merge with recursive body merging
      #
      # @return [MergeResult] The merge result
      def perform_merge
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
        pref = @preference.is_a?(Hash) ? (@preference[:default] || :destination) : @preference
        decl = (pref == :template) ? template_decl : dest_decl
        analysis = (pref == :template) ? @template_analysis : @dest_analysis

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
