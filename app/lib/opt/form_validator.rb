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

      # 方針は input_kind を読むだけ（登録時に導出済み、Opt::InputKind。#33 裁定 A）
      case field["input_kind"]
      when "number"
        numeric_error(field, raw) || units_error(field)
      when "select"
        coded_text_error(field, raw)
      when "coded_manual"
        coded_manual_error(field)
      when "date"
        date_error(raw)
      when "time"
        time_error(raw)
      when "datetime"
        datetime_error(raw) || (@values["#{field['name']}__time"].present? ? time_error(@values["#{field['name']}__time"]) : nil)
      end
    end

    # skoba/anlage#35: 日付・時刻はローカルで形式検証し、ISO 部分精度の文字列のまま保存する。
    # datetime の日付欄はブラウザの YYYY-MM-DD のほか、POST クライアントが送る完全な
    # ISO 日時（YYYY-MM-DDThh:mm[:ss][Z|±hh:mm]）も受ける
    DATE_PATTERN = /\A\d{4}(-\d{2}(-\d{2})?)?\z/
    DATETIME_PATTERN = /\A\d{4}(-\d{2}(-\d{2})?)?(T\d{2}(:\d{2}(:\d{2})?)?(Z|[+-]\d{2}:?\d{2})?)?\z/
    TIME_PATTERN = /\A\d{2}:\d{2}(:\d{2})?\z/

    def date_error(raw)
      "日付の形式が不正です（YYYY-MM-DD）" unless raw.to_s.match?(DATE_PATTERN)
    end

    def datetime_error(raw)
      "日付の形式が不正です（YYYY-MM-DD）" unless raw.to_s.match?(DATETIME_PATTERN)
    end

    def time_error(raw)
      "時刻の形式が不正です（HH:MM）" unless raw.to_s.match?(TIME_PATTERN)
    end

    # 裁定 B: raw 文字列を code に詰めた DvCodedText は存在しないコードの捏造になるので、
    # コード化必須（用語サービス未接続）では code 未入力をエラーにする
    def coded_manual_error(field)
      return nil if @values["#{field['name']}__code"].present?

      "コード入力が必要です（用語サービス未接続のため system／code を手入力してください）"
    end

    # skoba/anlage#37: 単位は __units、無ければ units リストの先頭。どちらも無ければエラー
    def units_error(field)
      return nil if Opt::FormValidator.units_for(field, @values).present?

      "単位を入力してください"
    end

    def self.units_for(field, values)
      values["#{field['name']}__units"].presence || Array(field["units_list"].presence || [ field["units"] ].compact).first
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
