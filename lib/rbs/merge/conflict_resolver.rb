# frozen_string_literal: true

module Rbs
  module Merge
    # Resolves conflicts between template and destination declarations.
    # Determines which version to use when both files have declarations
    # with matching signatures but different content.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(
    #     preference: :destination,
    #     template_analysis: template_analysis,
    #     dest_analysis: dest_analysis
    #   )
    #   winner = resolver.resolve(template_decl, dest_decl)
    class ConflictResolver < ::Ast::Merge::ConflictResolverBase
      # Initialize a conflict resolver
      #
      # @param preference [Symbol] Which version wins on conflict (:template or :destination)
      # @param template_analysis [FileAnalysis] Analysis of the template file
      # @param dest_analysis [FileAnalysis] Analysis of the destination file
      def initialize(preference:, template_analysis:, dest_analysis:)
        super(
          strategy: :node,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      # Resolve a conflict between template and destination declarations
      #
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @param template_index [Integer] Index in template statements
      # @param dest_index [Integer] Index in destination statements
      # @return [Hash] Resolution result with :source and :declaration keys
      def resolve(template_decl, dest_decl, template_index:, dest_index:)
        # Freeze blocks always win (they represent protected content)
        if freeze_node?(dest_decl)
          return {source: :destination, declaration: dest_decl, decision: DECISION_FREEZE_BLOCK}
        end

        # Check if declarations are identical
        if declarations_identical?(template_decl, dest_decl)
          # Prefer destination to minimize diffs
          return {source: :destination, declaration: dest_decl, decision: DECISION_DESTINATION}
        end

        # Check if we should recursively merge (for container types)
        if can_recursive_merge?(template_decl, dest_decl)
          return {
            source: :recursive,
            template_declaration: template_decl,
            dest_declaration: dest_decl,
            decision: DECISION_RECURSIVE,
          }
        end

        # Apply preference
        case @preference
        when :template
          {source: :template, declaration: template_decl, decision: DECISION_TEMPLATE}
        else # :destination (validated in initialize)
          {source: :destination, declaration: dest_decl, decision: DECISION_DESTINATION}
        end
      end

      # Check if two declarations are identical
      # @param decl1 [Object] First declaration
      # @param decl2 [Object] Second declaration
      # @return [Boolean]
      def declarations_identical?(decl1, decl2)
        # Use RBS's built-in equality
        decl1 == decl2
      end

      # Check if declarations can be recursively merged
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @return [Boolean]
      def can_recursive_merge?(template_decl, dest_decl)
        # Only container types can be recursively merged
        container_types = [
          RBS::AST::Declarations::Class,
          RBS::AST::Declarations::Module,
          RBS::AST::Declarations::Interface,
        ]

        template_decl.class == dest_decl.class &&
          container_types.any? { |type| template_decl.is_a?(type) } &&
          template_decl.respond_to?(:members) &&
          dest_decl.respond_to?(:members) &&
          template_decl.members.any? &&
          dest_decl.members.any?
      end
    end
  end
end
