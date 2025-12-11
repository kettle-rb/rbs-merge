# frozen_string_literal: true

module Rbs
  module Merge
    # File analysis for RBS type signature files.
    # Parses RBS source code and extracts declarations, members, and freeze blocks.
    #
    # This class provides the foundation for intelligent merging by:
    # - Parsing RBS files using the official RBS parser
    # - Extracting top-level declarations (classes, modules, interfaces, type aliases, constants)
    # - Detecting freeze blocks marked with comment directives
    # - Generating signatures for matching declarations between files
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(rbs_source)
    #   analysis.statements.each do |stmt|
    #     puts stmt.class
    #   end
    #
    # @example With custom freeze token
    #   analysis = FileAnalysis.new(source, freeze_token: "my-merge")
    #   # Looks for: # my-merge:freeze / # my-merge:unfreeze
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      # @return [String]
      DEFAULT_FREEZE_TOKEN = "rbs-merge"

      # @return [RBS::Buffer] The RBS buffer for this file
      attr_reader :buffer

      # @return [Array<RBS::AST::Directives::Base>] RBS directives (use statements, etc.)
      attr_reader :directives

      # @return [Array<RBS::AST::Declarations::Base>] Raw declarations from parser
      attr_reader :declarations

      # Initialize file analysis with RBS parser
      #
      # @param source [String] RBS source code to analyze
      # @param freeze_token [String] Token for freeze block markers (default: "rbs-merge")
      # @param signature_generator [Proc, nil] Custom signature generator
      # @raise [RBS::ParsingError] If the source has syntax errors
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil)
        @source = source
        @lines = source.split("\n", -1)
        @freeze_token = freeze_token
        @signature_generator = signature_generator

        # Parse the RBS source
        @buffer = RBS::Buffer.new(name: "merge.rbs", content: source)
        @buffer, @directives, @declarations = DebugLogger.time("FileAnalysis#parse") do
          RBS::Parser.parse_signature(@buffer)
        end

        # Extract and integrate all nodes including freeze blocks
        @statements = extract_and_integrate_all_nodes

        DebugLogger.debug("FileAnalysis initialized", {
          signature_generator: signature_generator ? "custom" : "default",
          directives_count: @directives.size,
          declarations_count: @declarations.size,
          statements_count: @statements.size,
          freeze_blocks: freeze_blocks.size,
        })
      end

      # Check if parse was successful (RBS parser raises on failure, so always true if we get here)
      # @return [Boolean]
      def valid?
        true
      end

      # Get all statements (declarations outside freeze blocks + FreezeNodes)
      # @return [Array<RBS::AST::Declarations::Base, FreezeNode>]
      attr_reader :statements

      # Compute default signature for a node
      # @param node [Object] The declaration or FreezeNode
      # @return [Array, nil] Signature array
      def compute_node_signature(node)
        case node
        when FreezeNode
          node.signature
        when RBS::AST::Declarations::Class
          [:class, node.name.to_s]
        when RBS::AST::Declarations::Module
          [:module, node.name.to_s]
        when RBS::AST::Declarations::Interface
          [:interface, node.name.to_s]
        when RBS::AST::Declarations::TypeAlias
          [:type_alias, node.name.to_s]
        when RBS::AST::Declarations::Constant
          [:constant, node.name.to_s]
        when RBS::AST::Declarations::Global
          [:global, node.name.to_s]
        when RBS::AST::Members::MethodDefinition
          [:method, node.name.to_s, node.kind]
        when RBS::AST::Members::Alias
          [:alias, node.new_name.to_s, node.old_name.to_s]
        when RBS::AST::Members::AttrReader
          [:attr_reader, node.name.to_s]
        when RBS::AST::Members::AttrWriter
          [:attr_writer, node.name.to_s]
        when RBS::AST::Members::AttrAccessor
          [:attr_accessor, node.name.to_s]
        when RBS::AST::Members::Include
          [:include, node.name.to_s]
        when RBS::AST::Members::Extend
          [:extend, node.name.to_s]
        when RBS::AST::Members::Prepend
          [:prepend, node.name.to_s]
        when RBS::AST::Members::InstanceVariable
          [:ivar, node.name.to_s]
        when RBS::AST::Members::ClassInstanceVariable
          [:civar, node.name.to_s]
        when RBS::AST::Members::ClassVariable
          [:cvar, node.name.to_s]
        else
          # Unknown node type - use class name and location as signature
          [:unknown, node.class.name, node.location&.start_line]
        end
      end

      # Override to detect RBS nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(RBS::AST::Declarations::Base) ||
          value.is_a?(RBS::AST::Members::Base) ||
          value.is_a?(FreezeNode) ||
          super
      end

      private

      # Extract all nodes and integrate freeze blocks
      # @return [Array<Object>] Integrated list of declarations and freeze blocks
      def extract_and_integrate_all_nodes
        freeze_markers = find_freeze_markers
        return @declarations.dup if freeze_markers.empty?

        # Build freeze blocks from markers
        freeze_block_nodes = build_freeze_blocks(freeze_markers)
        return @declarations.dup if freeze_block_nodes.empty?

        # Integrate declarations with freeze blocks
        integrate_nodes_with_freeze_blocks(@declarations, freeze_block_nodes)
      end

      # Find all freeze markers in the source
      # @return [Array<Hash>] Array of marker info hashes
      def find_freeze_markers
        markers = []
        # Use shared pattern from Ast::Merge::FreezeNodeBase with our specific token
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          next unless (match = line.match(pattern))

          marker_type = match[1]&.downcase # 'freeze' or 'unfreeze'
          if marker_type == "freeze"
            markers << {type: :start, line: line_num, text: line}
          elsif marker_type == "unfreeze"
            markers << {type: :end, line: line_num, text: line}
          end
        end

        markers
      end

      # Build freeze blocks from paired markers
      # @param markers [Array<Hash>] Freeze markers
      # @return [Array<FreezeNode>] Freeze block nodes
      def build_freeze_blocks(markers)
        blocks = []
        stack = []

        markers.each do |marker|
          case marker[:type]
          when :start
            stack.push(marker)
          when :end
            if stack.any?
              start_marker = stack.pop
              # Find nodes contained in this freeze block
              contained_nodes = find_contained_nodes(start_marker[:line], marker[:line])
              overlapping_nodes = find_overlapping_nodes(start_marker[:line], marker[:line])

              blocks << FreezeNode.new(
                start_line: start_marker[:line],
                end_line: marker[:line],
                analysis: self,
                nodes: contained_nodes,
                overlapping_nodes: overlapping_nodes,
                start_marker: start_marker[:text],
                end_marker: marker[:text],
              )
            else
              DebugLogger.warning("Unmatched freeze end marker at line #{marker[:line]}")
            end
          end
        end

        stack.each do |unmatched|
          DebugLogger.warning("Unmatched freeze start marker at line #{unmatched[:line]}")
        end

        blocks
      end

      # Find declarations fully contained within a range
      # @param start_line [Integer] Start line
      # @param end_line [Integer] End line
      # @return [Array<Object>] Contained declarations
      def find_contained_nodes(start_line, end_line)
        @declarations.select do |decl|
          decl.location.start_line >= start_line && decl.location.end_line <= end_line
        end
      end

      # Find declarations that overlap with a range
      # @param start_line [Integer] Start line
      # @param end_line [Integer] End line
      # @return [Array<Object>] Overlapping declarations
      def find_overlapping_nodes(start_line, end_line)
        @declarations.select do |decl|
          decl_start = decl.location.start_line
          decl_end = decl.location.end_line

          # Overlaps if not fully before and not fully after
          !(decl_end < start_line || decl_start > end_line)
        end
      end

      # Integrate declarations with freeze blocks, avoiding duplicates
      # @param declarations [Array] Original declarations
      # @param freeze_blocks [Array<FreezeNode>] Freeze blocks
      # @return [Array] Integrated list sorted by line number
      def integrate_nodes_with_freeze_blocks(declarations, freeze_blocks)
        # Track which declarations are inside freeze blocks
        frozen_declarations = freeze_blocks.flat_map(&:nodes).to_set

        # Filter out frozen declarations and add freeze blocks
        result = declarations.reject { |d| frozen_declarations.include?(d) }
        result.concat(freeze_blocks)

        # Sort by start line
        result.sort_by do |node|
          if node.is_a?(FreezeNode)
            node.start_line
          elsif node.respond_to?(:comment) && node.comment
            # Include comment line in sorting if present
            [node.comment.location.start_line, node.location.start_line].min
          else
            node.location.start_line
          end
        end
      end
    end
  end
end
