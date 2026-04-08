# frozen_string_literal: true

require "set"

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
      # @param remove_template_missing_nodes [Boolean] Controls whether to remove
      #   destination-only declarations while promoting their leading comments
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
        remove_template_missing_nodes: false,
        freeze_token: nil,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        max_recursion_depth: Float::INFINITY,
        **options
      )
        @max_recursion_depth = max_recursion_depth
        @remove_template_missing_nodes = remove_template_missing_nodes
        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
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
          node_typing: @node_typing,
          remove_template_missing_nodes: @remove_template_missing_nodes,
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

        emit_root_boundary(:preamble)
        process_alignment(alignment)
        emit_root_boundary(:postlude)

        # Normalize consecutive blank lines left behind by comment dedup or node removal
        @result.normalize_consecutive_blank_lines!

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

      def emit_root_boundary(kind)
        analysis, lines = preferred_root_boundary_lines(kind)
        return unless analysis
        return if lines.empty?

        decision = (analysis == @template_analysis) ? MergeResult::DECISION_TEMPLATE : MergeResult::DECISION_DESTINATION
        @result.add_raw(lines, decision: decision)
      end

      def preferred_root_boundary_lines(kind)
        analyses = [preferred_root_boundary_analysis]
        fallback_analysis = (analyses.first == @template_analysis) ? @dest_analysis : @template_analysis
        analyses << fallback_analysis

        analyses.each do |analysis|
          lines = root_boundary_lines_for(kind, analysis)
          return [analysis, lines] if lines.any?
        end

        [nil, []]
      end

      def preferred_root_boundary_analysis
        pref = @preference.is_a?(Hash) ? (@preference[:default] || :destination) : @preference
        (pref == :template) ? @template_analysis : @dest_analysis
      end

      def root_boundary_lines_for(kind, analysis)
        return [] unless analysis&.respond_to?(:comment_augmenter)

        comment_only_lines = comment_only_boundary_lines_for(kind, analysis)
        return comment_only_lines if comment_only_lines.any?

        region = root_boundary_region(kind, analysis)
        return [] unless region_present?(region)

        start_line, end_line = root_boundary_range(kind, analysis, region)
        return [] unless start_line && end_line
        return [] if start_line > end_line

        (start_line..end_line).filter_map { |line_number| analysis.line_at(line_number) }
      end

      def comment_only_boundary_lines_for(kind, analysis)
        return [] unless kind == :preamble
        return [] unless Array(analysis.statements).empty?
        return [] unless analysis.respond_to?(:comment_nodes) && analysis.comment_nodes.any?

        analysis.lines.dup
      end

      def root_boundary_region(kind, analysis)
        augmenter = root_comment_augmenter_for(analysis)
        return unless augmenter

        (kind == :preamble) ? augmenter.preamble_region : augmenter.postlude_region
      end

      def root_comment_augmenter_for(analysis)
        @root_comment_augmenters ||= {}
        @root_comment_augmenters[analysis.object_id] ||= analysis.comment_augmenter(owners: analysis.statements)
      end

      def root_boundary_range(kind, analysis, region)
        statements = Array(analysis.statements).select do |statement|
          statement.respond_to?(:start_line) && statement.respond_to?(:end_line)
        end

        case kind
        when :preamble
          end_line = if statements.any?
            statements.map(&:start_line).compact.min.to_i - 1
          else
            analysis.lines.length
          end
          [1, end_line]
        when :postlude
          start_line = if statements.any?
            statements.map(&:end_line).compact.max.to_i + 1
          else
            region.start_line || 1
          end
          [start_line, analysis.lines.length]
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
          if entry[:template_decl].is_a?(FreezeNode)
            @result.add_freeze_block(entry[:template_decl])
          else
            @result.add_from_template(
              entry[:template_index],
              decision: resolution[:decision],
              comment_source_statement: entry[:dest_decl],
              comment_source_analysis: @dest_analysis,
            )
          end
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

        # FreezeNodes from template should always be added
        if entry[:template_decl].is_a?(FreezeNode)
          @result.add_freeze_block(entry[:template_decl])
        else
          @result.add_from_template(entry[:template_index], decision: MergeResult::DECISION_ADDED)
        end
      end

      # Process a destination-only declaration
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_dest_only(entry)
        if entry[:dest_decl].is_a?(FreezeNode)
          @result.add_freeze_block(entry[:dest_decl])
        elsif @remove_template_missing_nodes
          emit_removed_destination_declaration_comments(entry[:dest_decl])
        else
          @result.add_from_destination(entry[:dest_index], decision: MergeResult::DECISION_DESTINATION)
        end
      end

      def emit_removed_destination_declaration_comments(decl)
        lines = removed_declaration_comment_lines(decl, @dest_analysis)
        @result.add_raw(lines, decision: MergeResult::DECISION_DESTINATION) if lines.any?
      end

      def removed_declaration_comment_lines(decl, analysis)
        leading_region = leading_region_for(decl, analysis)
        start_line = get_start_line(decl)

        if region_present?(leading_region)
          region_start = region_start_line(leading_region)
          if region_start && start_line && region_start < start_line
            leading_start = preceding_blank_line_start(region_start, analysis)
            return (leading_start...start_line).filter_map { |ln| analysis.line_at(ln) }
          end
        elsif decl.respond_to?(:comment) && decl.comment
          comment_start = decl.comment.location&.start_line
          return (comment_start...start_line).filter_map { |ln| analysis.line_at(ln) } if comment_start && start_line && comment_start < start_line
        end

        []
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
        comment_source_decl = (pref == :template) ? dest_decl : nil
        comment_source_analysis = (pref == :template) ? @dest_analysis : nil

        # Support both NodeWrapper (has start_line/end_line) and RBS gem nodes (has location)
        start_line = get_start_line(decl)
        end_line = get_end_line(decl)

        leading_region, leading_analysis, leading_decl = preferred_leading_region(
          decl,
          analysis,
          comment_source_decl: comment_source_decl,
          comment_source_analysis: comment_source_analysis,
        )

        if leading_region && leading_decl
          region_start = region_start_line(leading_region)
          leading_end = get_start_line(leading_decl)

          if region_start && leading_end && region_start < leading_end
            leading_start = preceding_blank_line_start(region_start, leading_analysis)
            leading_lines = (leading_start...leading_end).filter_map { |ln| leading_analysis.line_at(ln) }
            body_lines = recursive_body_lines_for_declaration(
              template_decl,
              dest_decl,
              decl,
              analysis,
            )
            return (leading_lines + body_lines).join("\n") + "\n"
          end
        end

        # Include leading comment if present (RBS gem nodes only)
        if decl.respond_to?(:comment) && decl.comment
          comment_loc = decl.comment.respond_to?(:location) ? decl.comment.location : nil
          if comment_loc
            comment_start = comment_loc.start_line
            start_line = comment_start if comment_start < start_line
          end
        end

        recursive_body_lines_for_declaration(
          template_decl,
          dest_decl,
          decl,
          analysis,
          start_line: start_line,
          end_line: end_line,
        ).join("\n") + "\n"
      end

      def recursive_body_lines_for_declaration(template_decl, dest_decl, selected_decl, selected_analysis, start_line: nil, end_line: nil)
        template_members = template_decl.respond_to?(:members) ? template_decl.members : []
        dest_members = dest_decl.respond_to?(:members) ? dest_decl.members : []
        selected_members = selected_decl.respond_to?(:members) ? selected_decl.members : []

        start_line ||= get_start_line(selected_decl)
        end_line ||= get_end_line(selected_decl)

        return (start_line..end_line).map { |ln| selected_analysis.line_at(ln) } if template_members.empty? && dest_members.empty?

        if selected_members.empty?
          return empty_container_header_lines(selected_analysis, start_line: start_line, end_line: end_line) +
              merge_member_lines(template_members, dest_members) +
              empty_container_footer_lines(selected_analysis, start_line: start_line, end_line: end_line)
        end

        container_header_lines(selected_decl, selected_analysis) +
          merge_member_lines(template_members, dest_members) +
          container_footer_lines(selected_decl, selected_analysis)
      end

      def merge_member_lines(template_members, dest_members)
        align_member_lists(template_members, dest_members).each_with_object([]) do |entry, lines|
          case entry[:type]
          when :match
            resolution = @resolver.resolve(
              entry[:template_decl],
              entry[:dest_decl],
              template_index: entry[:template_index],
              dest_index: entry[:dest_index],
            )

            case resolution[:source]
            when :template
              lines.concat(
                extract_statement_lines_with_leading_comments(
                  entry[:template_decl],
                  @template_analysis,
                  comment_source_statement: entry[:dest_decl],
                  comment_source_analysis: @dest_analysis,
                ),
              )
            when :destination
              lines.concat(extract_statement_lines_with_leading_comments(entry[:dest_decl], @dest_analysis))
            when :recursive
              lines.concat(
                reconstruct_declaration_with_merged_members(
                  resolution[:template_declaration],
                  resolution[:dest_declaration],
                  entry[:template_index],
                  entry[:dest_index],
                ).split("\n", -1).tap { |parts| parts.pop if parts.last == "" },
              )
            end
          when :template_only
            next unless @add_template_only_nodes

            lines.concat(extract_statement_lines_with_leading_comments(entry[:template_decl], @template_analysis))
          when :dest_only
            if @remove_template_missing_nodes
              lines.concat(removed_declaration_comment_lines(entry[:dest_decl], @dest_analysis))
            else
              lines.concat(extract_statement_lines_with_leading_comments(entry[:dest_decl], @dest_analysis))
            end
          end
        end
      end

      def align_member_lists(template_members, dest_members)
        template_by_sig = build_member_signature_map(template_members, @template_analysis)
        dest_by_sig = build_member_signature_map(dest_members, @dest_analysis)
        matched_template = Set.new
        matched_dest = Set.new
        alignment = []

        template_by_sig.each do |sig, template_indices|
          next unless dest_by_sig.key?(sig)

          template_indices.zip(dest_by_sig[sig]).each do |t_idx, d_idx|
            next unless t_idx && d_idx

            alignment << {
              type: :match,
              template_index: t_idx,
              dest_index: d_idx,
              template_decl: template_members[t_idx],
              dest_decl: dest_members[d_idx],
            }
            matched_template << t_idx
            matched_dest << d_idx
          end
        end

        template_members.each_with_index do |stmt, idx|
          next if matched_template.include?(idx)

          alignment << {
            type: :template_only,
            template_index: idx,
            dest_index: nil,
            template_decl: stmt,
            dest_decl: nil,
          }
        end

        dest_members.each_with_index do |stmt, idx|
          next if matched_dest.include?(idx)

          alignment << {
            type: :dest_only,
            template_index: nil,
            dest_index: idx,
            template_decl: nil,
            dest_decl: stmt,
          }
        end

        alignment.sort_by do |entry|
          if entry[:dest_index]
            [0, entry[:dest_index], entry[:template_index] || Float::INFINITY]
          elsif entry[:template_index]
            [1, entry[:template_index], 0]
          else
            [2, 0, 0]
          end
        end
      end

      def build_member_signature_map(members, analysis)
        members.each_with_index.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(member, idx), map|
          signature = member_alignment_signature(member, analysis)
          map[signature] << idx if signature
        end
      end

      def member_alignment_signature(member, analysis)
        signature = analysis.generate_signature(member)
        return signature unless method_member_signature?(member, signature)

        overload_key = method_overload_alignment_key(member, analysis)
        return signature unless overload_key

        signature + [overload_key]
      end

      def method_member_signature?(member, signature)
        return false unless signature.is_a?(Array) && signature.first == :method
        return member.method? if member.respond_to?(:method?)

        true
      end

      def method_overload_alignment_key(member, analysis)
        text = if member.respond_to?(:text) && member.text
          member.text
        else
          extract_raw_statement_lines(member, analysis).join("\n")
        end

        callable_shape = extract_callable_shape(text)
        callable_shape unless callable_shape.nil? || callable_shape.empty?
      end

      def extract_callable_shape(text)
        stripped = text.to_s.strip
        return if stripped.empty?

        colon_index = stripped.index(":")
        return unless colon_index

        type_text = stripped[(colon_index + 1)..].to_s.strip
        callable_portion, = split_top_level_return_type(type_text)
        normalize_signature_whitespace(callable_portion)
      end

      def split_top_level_return_type(type_text)
        depth = 0
        index = 0

        while index < (type_text.length - 1)
          char = type_text[index]
          next_char = type_text[index + 1]

          case char
          when "(", "[", "{", "<"
            depth += 1
          when ")", "]", "}", ">"
            depth -= 1 if depth.positive?
          end

          if depth.zero? && char == "-" && next_char == ">"
            return [type_text[0...index].strip, type_text[(index + 2)..].to_s.strip]
          end

          index += 1
        end

        [type_text.strip, nil]
      end

      def normalize_signature_whitespace(text)
        text.to_s.gsub(/\s+/, " ").strip
      end

      def extract_raw_statement_lines(statement, analysis)
        start_line = get_start_line(statement)
        end_line = get_end_line(statement)
        return [] unless start_line && end_line

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def extract_statement_lines_with_leading_comments(statement, analysis, comment_source_statement: nil, comment_source_analysis: nil)
        start_line = get_start_line(statement)
        return [] unless start_line

        leading_region, leading_analysis, leading_statement = preferred_leading_region(
          statement,
          analysis,
          comment_source_decl: comment_source_statement,
          comment_source_analysis: comment_source_analysis,
        )

        leading_lines = if leading_region && leading_statement
          region_start = region_start_line(leading_region)
          leading_end = get_start_line(leading_statement)

          if region_start && leading_end && region_start < leading_end
            leading_start = preceding_blank_line_start(region_start, leading_analysis)
            (leading_start...leading_end).filter_map { |line_number| leading_analysis.line_at(line_number) }
          else
            []
          end
        else
          []
        end

        leading_lines + extract_raw_statement_lines(statement, analysis)
      end

      def empty_container_header_lines(analysis, start_line:, end_line:)
        return [] unless start_line && end_line
        return [] unless start_line < end_line

        (start_line...end_line).map { |line_number| analysis.line_at(line_number) }
      end

      def empty_container_footer_lines(analysis, start_line:, end_line:)
        return [] unless start_line && end_line

        [analysis.line_at(end_line)]
      end

      def container_header_lines(decl, analysis)
        members = decl.respond_to?(:members) ? decl.members : []
        first_member = members.first
        return [] unless first_member

        start_line = get_start_line(decl)
        end_line = get_start_line(first_member) - 1
        return [] unless start_line && end_line && start_line <= end_line

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def container_footer_lines(decl, analysis)
        members = decl.respond_to?(:members) ? decl.members : []
        last_member = members.last
        return [] unless last_member

        start_line = get_end_line(last_member) + 1
        end_line = get_end_line(decl)
        return [] unless start_line && end_line && start_line <= end_line

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def preferred_leading_region(decl, analysis, comment_source_decl: nil, comment_source_analysis: nil)
        primary_region = leading_region_for(decl, analysis)
        return [primary_region, analysis, decl] if region_present?(primary_region)

        if comment_source_decl && comment_source_analysis
          source_region = leading_region_for(comment_source_decl, comment_source_analysis)
          return [source_region, comment_source_analysis, comment_source_decl] if region_present?(source_region)
        end

        [nil, analysis, decl]
      end

      def leading_region_for(decl, analysis)
        return unless decl && analysis && analysis.respond_to?(:comment_attachment_for)

        attachment = analysis.comment_attachment_for(decl)
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

      # Get start line for a declaration (works with both backends)
      # @param decl [Object] Declaration (NodeWrapper or RBS::AST::*)
      # @return [Integer]
      def get_start_line(decl)
        if decl.respond_to?(:start_line)
          decl.start_line
        elsif decl.respond_to?(:location) && decl.location
          decl.location.start_line
        else
          1
        end
      end

      # Get end line for a declaration (works with both backends)
      # @param decl [Object] Declaration (NodeWrapper or RBS::AST::*)
      # @return [Integer]
      def get_end_line(decl)
        if decl.respond_to?(:end_line)
          decl.end_line
        elsif decl.respond_to?(:location) && decl.location
          decl.location.end_line
        else
          1
        end
      end
    end
  end
end
