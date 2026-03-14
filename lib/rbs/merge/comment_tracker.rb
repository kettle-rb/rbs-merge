# frozen_string_literal: true

module Rbs
  module Merge
    # Tracks hash-style comments in RBS source and exposes a shared comment API.
    class CommentTracker
      DEFAULT_FREEZE_TOKEN = "rbs-merge"
      FULL_LINE_COMMENT_REGEX = /\A(?<indent>\s*)#\s?(?<text>.*)\z/

      attr_reader :lines, :comments

      def initialize(lines, freeze_token: DEFAULT_FREEZE_TOKEN)
        @lines = Array(lines)
        @freeze_token = freeze_token
        @freeze_marker_pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)
        @comments = extract_comments
        @comments_by_line = @comments.group_by { |comment| comment[:line] }
      end

      def comment_at(line_num)
        @comments_by_line[line_num]&.first
      end

      def comment_nodes
        @comment_nodes ||= @comments.map { |comment| build_comment_node(comment) }
      end

      def comment_node_at(line_num)
        comment = comment_at(line_num)
        return unless comment

        build_comment_node(comment)
      end

      def comments_in_range(range)
        @comments.select { |comment| range.cover?(comment[:line]) }
      end

      def comment_region_for_range(range, kind:, full_line_only: false)
        selected = comments_in_range(range)
        selected = selected.select { |comment| comment[:full_line] } if full_line_only

        build_region(
          kind: kind,
          comments: selected,
          metadata: {
            range: range,
            full_line_only: full_line_only,
            source: :comment_tracker,
          },
        )
      end

      def leading_comments_before(line_num)
        leading = []
        current = line_num - 1

        current -= 1 while current >= 1 && blank_line?(current)

        while current >= 1
          comment = comment_at(current)
          break unless comment && comment[:full_line]

          leading.unshift(comment)
          current -= 1
          current -= 1 while current >= 1 && blank_line?(current)
        end

        leading
      end

      def leading_comment_region_before(line_num)
        selected = leading_comments_before(line_num)
        return if selected.empty?

        build_region(
          kind: :leading,
          comments: selected,
          metadata: {
            line_num: line_num,
            source: :comment_tracker,
          },
        )
      end

      def comment_attachment_for(owner, line_num: nil, **metadata)
        resolved_line_num = line_num || owner_line_num(owner)
        leading_region = resolved_line_num ? leading_comment_region_before(resolved_line_num) : nil

        build_attachment(
          owner: owner,
          leading_region: leading_region,
          inline_region: nil,
          metadata: metadata.merge(
            line_num: resolved_line_num,
            source: :comment_tracker,
          ),
        )
      end

      def blank_line?(line_num)
        return false if line_num < 1 || line_num > @lines.length

        @lines[line_num - 1].to_s.strip.empty?
      end

      def augment(owners: [], **options)
        Ast::Merge::Comment::Augmenter.new(
          lines: @lines,
          comments: @comments,
          owners: owners,
          style: :hash_comment,
          total_comment_count: @comments.size,
          **options,
        )
      end

      private

      def extract_comments
        @lines.each_with_index.filter_map do |line, index|
          next if freeze_marker_comment?(line)

          match = line.match(FULL_LINE_COMMENT_REGEX)
          next unless match

          {
            line: index + 1,
            indent: match[:indent].length,
            text: match[:text].to_s,
            full_line: true,
            raw: line,
          }
        end
      end

      def freeze_marker_comment?(line)
        return false unless line

        !!line.match(@freeze_marker_pattern)
      end

      def owner_line_num(owner)
        return owner.start_line if owner.respond_to?(:start_line) && owner.start_line

        nil
      end

      def build_comment_node(comment)
        Ast::Merge::Comment::TrackedHashAdapter.node(comment, style: :hash_comment)
      end

      def build_region(kind:, comments:, metadata: {})
        Ast::Merge::Comment::TrackedHashAdapter.region(
          kind: kind,
          comments: comments,
          style: :hash_comment,
          metadata: metadata,
        )
      end

      def build_attachment(owner:, leading_region:, inline_region:, metadata: {})
        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: leading_region,
          inline_region: inline_region,
          metadata: metadata,
        )
      end
    end
  end
end
