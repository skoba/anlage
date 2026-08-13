module Opt
  # Validates submitted form values against a Template's web_template
  # constraints (required, numeric range, coded-text membership) before
  # CompositionBuilder ever touches them, so the visitor sees a normal
  # per-field validation message instead of an RM ArgumentError.
  class FormValidator
    Result = Struct.new(:errors) do
      def valid? = errors.empty?
    end

    def self.call(template, values)
      new(template, values).call
    end

    def initialize(template, values)
      @template = template
      @values = values.stringify_keys
    end

    def call
      errors = {}
      @template.fields.each do |field|
        message = error_for(field)
        errors[field["name"]] = message if message
      end
      Result.new(errors)
    end

    private

    def error_for(field)
      raw = @values[field["name"]]

      return "必須項目です" if field["required"] && raw.blank?
      return nil if raw.blank?

      case field["rm_type"]
      when "DV_QUANTITY", "DV_COUNT"
        numeric_error(field, raw)
      when "DV_CODED_TEXT"
        coded_text_error(field, raw)
      end
    end

    def numeric_error(field, raw)
      value = Float(raw)
      range = field["magnitude_range"]
      if range
        lower, upper = range
        return "#{lower}以上である必要があります" if lower && value < lower
        return "#{upper}以下である必要があります" if upper && value > upper
      end
      nil
    rescue ArgumentError, TypeError
      "数値を入力してください"
    end

    def coded_text_error(field, raw)
      codes = field["code_list"]
      return nil if codes.blank?

      "許可されていない値です" unless codes.include?(raw)
    end
  end
end
