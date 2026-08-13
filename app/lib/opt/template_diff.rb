module Opt
  # Field-level semantic diff between two Templates that share a
  # template_id, keyed by each field's RM `path` (its semantic identity,
  # not its position in the document) -- used when a dropped OPT has the
  # same template_id as an already-registered active template but
  # different content, to show what actually changed before approving a
  # new version.
  class TemplateDiff
    Result = Struct.new(:added, :removed, :changed, keyword_init: true) do
      def any_changes?
        added.any? || removed.any? || changed.any?
      end
    end

    COMPARE_KEYS = %w[label rm_type units code_list required].freeze

    def self.call(old_template, new_template)
      new(old_template, new_template).call
    end

    def initialize(old_template, new_template)
      @old_fields = old_template.fields.index_by { |f| f["path"] }
      @new_fields = new_template.fields.index_by { |f| f["path"] }
    end

    def call
      Result.new(
        added: @new_fields.except(*@old_fields.keys).values,
        removed: @old_fields.except(*@new_fields.keys).values,
        changed: changed_fields
      )
    end

    private

    def changed_fields
      common_paths = @old_fields.keys & @new_fields.keys
      common_paths.filter_map do |path|
        before = @old_fields[path]
        after = @new_fields[path]
        next if COMPARE_KEYS.all? { |key| before[key] == after[key] }

        { "path" => path, "before" => before.slice(*COMPARE_KEYS), "after" => after.slice(*COMPARE_KEYS) }
      end
    end
  end
end
