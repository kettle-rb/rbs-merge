# frozen_string_literal: true

# External gems
require "rbs"
require "version_gem"
require "set"

# Shared merge infrastructure
require "ast/merge"

# This gem
require_relative "merge/version"

module Rbs
  module Merge
    # Base error class for rbs-merge errors
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    # @api public
    class Error < Ast::Merge::Error; end

    # Raised when an RBS file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(rbs_content)
    #   rescue ParseError => e
    #     puts "RBS syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    #
    # @api public
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The RBS source that failed to parse
      # @param errors [Array] Parse errors from RBS
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template RBS file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    #
    # @api public
    class TemplateParseError < ParseError; end

    # Raised when the destination RBS file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    #
    # @api public
    class DestinationParseError < ParseError; end

    autoload :DebugLogger, "rbs/merge/debug_logger"
    autoload :FreezeNode, "rbs/merge/freeze_node"
    autoload :MergeResult, "rbs/merge/merge_result"
    autoload :FileAnalysis, "rbs/merge/file_analysis"
    autoload :ConflictResolver, "rbs/merge/conflict_resolver"
    autoload :FileAligner, "rbs/merge/file_aligner"
    autoload :SmartMerger, "rbs/merge/smart_merger"
  end
end

Rbs::Merge::Version.class_eval do
  extend VersionGem::Basic
end
