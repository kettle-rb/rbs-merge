#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to discover and map tree-sitter-rbs node types
#
# This script parses various RBS constructs using tree-sitter-rbs
# and outputs the actual node types produced by the grammar.
#
# Usage:
#   ruby examples/map_tree_sitter_node_types.rb
#
# This helps build the NodeTypeNormalizer mappings for the tree_sitter backend.
#
# NOTE: tree-sitter-rbs grammar compatibility with ruby_tree_sitter may vary
# depending on the tree-sitter ABI version used to compile the grammar.
# If tree-sitter backends fail, the script will report an error.

require "bundler/inline"

gemfile do
  source "https://gem.coop"

  # stdlib gems
  gem "benchmark"

  # tree-sitter MRI backend
  gem "ruby_tree_sitter", require: false

  # Load local gems
  gem "ast-merge", path: File.expand_path("../../..", __dir__)
  gem "tree_haver", path: File.expand_path("../../tree_haver", __dir__)
  gem "rbs-merge", path: File.expand_path("..", __dir__)
end

require "tree_haver"
require "rbs/merge"

# Only try tree-sitter backends (not the RBS gem backend)
# This script is specifically for discovering tree-sitter-rbs node types
BACKENDS_TO_TRY = %i[mri ffi rust java].freeze

def find_working_backend
  BACKENDS_TO_TRY.each do |backend|
    TreeHaver.with_backend(backend) do
      parser = TreeHaver.parser_for(:rbs)
      result = parser.parse("class Foo end")
      if result&.root_node
        puts "Using backend: #{backend}"
        return backend
      end
    end
  rescue Exception => e  # TreeHaver errors inherit from Exception
    puts "Backend #{backend} not available: #{e.message}"
  end
  nil
end

def print_node(node, indent = 0, source = nil)
  prefix = "  " * indent
  type = node.type.to_s

  # Get text content if available
  text = ""
  if source && node.respond_to?(:start_byte) && node.respond_to?(:end_byte)
    text = source[node.start_byte...node.end_byte].to_s.gsub("\n", "\\n")
    text = text[0..50] + "..." if text.length > 50
    text = " => #{text.inspect}"
  end

  # Get position info
  pos = ""
  if node.respond_to?(:start_point) && node.start_point
    sp = node.start_point
    ep = node.end_point
    pos = " [#{sp.row}:#{sp.column}-#{ep.row}:#{ep.column}]"
  end

  puts "#{prefix}#{type}#{pos}#{text}"

  # Recurse into children
  node.each do |child|
    print_node(child, indent + 1, source)
  end
end

def analyze_rbs(name, source, backend)
  puts "\n" + "=" * 70
  puts "#{name}"
  puts "=" * 70
  puts "Source:"
  puts source.gsub(/^/, "  ")
  puts "\nAST:"

  TreeHaver.with_backend(backend) do
    parser = TreeHaver.parser_for(:rbs)
    result = parser.parse(source)

    if result&.root_node
      print_node(result.root_node, 1, source)

      # Collect all unique node types
      types = collect_types(result.root_node)
      puts "\nNode types found: #{types.sort.join(', ')}"
    else
      puts "  (no result)"
    end
  end
rescue => e
  puts "  ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).map { |l| "    #{l}" }.join("\n")
end

def collect_types(node, types = Set.new)
  types << node.type.to_s
  node.each { |child| collect_types(child, types) }
  types
end

# Main execution
puts "Tree-sitter-rbs Node Type Discovery"
puts "=" * 70

backend = find_working_backend
unless backend
  puts "ERROR: No working tree-sitter backend found for RBS grammar"
  exit 1
end

# Test various RBS constructs
EXAMPLES = {
  "Simple class" => <<~RBS,
    class Foo
    end
  RBS

  "Class with method" => <<~RBS,
    class Foo
      def bar: (String) -> Integer
    end
  RBS

  "Module" => <<~RBS,
    module Bar
      def baz: () -> void
    end
  RBS

  "Interface" => <<~RBS,
    interface _Qux
      def qux: () -> bool
    end
  RBS

  "Type alias" => <<~RBS,
    type my_type = String | Integer
  RBS

  "Constant" => <<~RBS,
    CONST: String
  RBS

  "Global variable" => <<~RBS,
    $global: Integer
  RBS

  "Class with inheritance" => <<~RBS,
    class Child < Parent
      def method: () -> void
    end
  RBS

  "Class with mixins" => <<~RBS,
    class WithMixins
      include Enumerable[String]
      extend ClassMethods
      prepend PrependedModule
    end
  RBS

  "Attributes" => <<~RBS,
    class WithAttrs
      attr_reader name: String
      attr_writer value: Integer
      attr_accessor both: Bool
    end
  RBS

  "Instance variables" => <<~RBS,
    class WithVars
      @ivar: String
      self.@civar: Integer
      @@cvar: Bool
    end
  RBS

  "Method alias" => <<~RBS,
    class WithAlias
      def original: () -> void
      alias new_name original
    end
  RBS

  "Singleton method" => <<~RBS,
    class WithSingleton
      def self.class_method: () -> void
    end
  RBS

  "Visibility" => <<~RBS,
    class WithVisibility
      public
      def pub: () -> void
      private
      def priv: () -> void
    end
  RBS

  "Generic class" => <<~RBS,
    class Generic[T]
      def get: () -> T
      def set: (T) -> void
    end
  RBS

  "Multiple declarations" => <<~RBS,
    class First
    end

    module Second
    end

    type third = String
  RBS

  "Comments" => <<~RBS,
    # This is a comment
    class Commented
      # Method comment
      def method: () -> void
    end
  RBS
}.freeze

EXAMPLES.each do |name, source|
  analyze_rbs(name, source, backend)
end

# Summary of all types found
puts "\n" + "=" * 70
puts "SUMMARY: All node types discovered"
puts "=" * 70

all_types = Set.new
EXAMPLES.each do |_name, source|
  TreeHaver.with_backend(backend) do
    parser = TreeHaver.parser_for(:rbs)
    result = parser.parse(source)
    collect_types(result.root_node, all_types) if result&.root_node
  end
rescue
  # Ignore errors in summary
end

puts all_types.sort.join("\n")
