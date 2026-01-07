# frozen_string_literal: true

module Rbs
  module Merge
    # Aligns declarations between template and destination files by matching signatures.
    # Produces alignment information used by SmartMerger to combine files.
    #
    # @example Basic usage
    #   aligner = FileAligner.new(template_analysis, dest_analysis)
    #   alignment = aligner.align
    #   alignment.each do |entry|
    #     case entry[:type]
    #     when :match
    #       # Both files have this declaration
    #     when :template_only
    #       # Only in template
    #     when :dest_only
    #       # Only in destination
    #     end
    #   end
    class FileAligner
      # @return [FileAnalysis] Template file analysis
      attr_reader :template_analysis

      # @return [FileAnalysis] Destination file analysis
      attr_reader :dest_analysis

      # Initialize a file aligner
      #
      # @param template_analysis [FileAnalysis] Analysis of the template file
      # @param dest_analysis [FileAnalysis] Analysis of the destination file
      def initialize(template_analysis, dest_analysis)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
      end

      # Perform alignment between template and destination statements
      #
      # @return [Array<Hash>] Alignment entries with type, indices, and declarations
      def align
        template_statements = @template_analysis.statements
        dest_statements = @dest_analysis.statements

        # Build signature maps
        template_by_sig = build_signature_map(template_statements, @template_analysis)
        dest_by_sig = build_signature_map(dest_statements, @dest_analysis)

        # Track which indices have been matched
        matched_template = Set.new
        matched_dest = Set.new
        alignment = []

        # First pass: find matches by signature
        template_by_sig.each do |sig, template_indices|
          next unless dest_by_sig.key?(sig)

          dest_indices = dest_by_sig[sig]

          # Match indices pairwise (first template with first dest, etc.)
          template_indices.zip(dest_indices).each do |t_idx, d_idx|
            next unless t_idx && d_idx

            alignment << {
              type: :match,
              template_index: t_idx,
              dest_index: d_idx,
              signature: sig,
              template_decl: template_statements[t_idx],
              dest_decl: dest_statements[d_idx],
            }

            matched_template << t_idx
            matched_dest << d_idx
          end
        end

        # Second pass: add template-only entries
        template_statements.each_with_index do |stmt, idx|
          next if matched_template.include?(idx)

          alignment << {
            type: :template_only,
            template_index: idx,
            dest_index: nil,
            signature: @template_analysis.signature_at(idx),
            template_decl: stmt,
            dest_decl: nil,
          }
        end

        # Third pass: add dest-only entries
        dest_statements.each_with_index do |stmt, idx|
          next if matched_dest.include?(idx)

          alignment << {
            type: :dest_only,
            template_index: nil,
            dest_index: idx,
            signature: @dest_analysis.signature_at(idx),
            template_decl: nil,
            dest_decl: stmt,
          }
        end

        # Sort by appearance order (prefer destination order, then template)
        sort_alignment(alignment)
      end

      private

      # Build a map from signatures to statement indices
      # @param statements [Array] Statements to map
      # @param analysis [FileAnalysis] File analysis for signature generation
      # @return [Hash{Array => Array<Integer>}] Signature to indices map
      def build_signature_map(statements, analysis)
        map = Hash.new { |h, k| h[k] = [] }

        statements.each_with_index do |stmt, idx|
          sig = analysis.signature_at(idx)
          map[sig] << idx if sig

          # For FreezeNodes, also index by the signatures of contained nodes
          # This allows matching a freeze block with the non-frozen version of the same declaration
          if stmt.is_a?(FreezeNode) && stmt.nodes.any?
            stmt.nodes.each do |contained_node|
              contained_sig = analysis.generate_signature(contained_node)
              map[contained_sig] << idx if contained_sig
            end
          end
        end

        map
      end

      # Sort alignment entries for output
      # @param alignment [Array<Hash>] Alignment entries
      # @return [Array<Hash>] Sorted alignment
      def sort_alignment(alignment)
        alignment.sort_by do |entry|
          case entry[:type]
          when :match
            # Sort by destination index for matches
            [0, entry[:dest_index], entry[:template_index]]
          when :dest_only
            # Destination-only items sorted by their index
            [1, entry[:dest_index], 0]
          when :template_only
            # Template-only items at the end, by template index
            [2, entry[:template_index], 0]
          else
            [3, 0, 0]
          end
        end
      end
    end
  end
end
