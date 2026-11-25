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

    # 帳票の必須の印（R-20261125-1。docs/demo/ui-vocabulary.md）: 常に書かれる入れ物の中の必須は :always（「*」）、
    # 任意の入れ物の中の必須は :if_written（「※ この枠に書くなら必須」）。必須でなければ nil
    def self.required_mark(field)
      return nil unless field["required"]

      optional = (field["containers"] || []).any? { |container| container["min"] && container["min"] < 1 }
      optional ? :if_written : :always
    end

    def initialize(template, values)
      @template = template
      @values = values.stringify_keys
    end

    # 帳票全体で値が 1 つも無いとき、項目ではなく帳票に付くメッセージ（R-20261125-1。文言は docs/demo/ui-vocabulary.md）
    EMPTY_FORM_MESSAGE = "値が 1 つも入力されていません。少なくとも 1 つの項目を入力してください".freeze

    def call
      fields = @template.fields
      return Result.new({ "base" => EMPTY_FORM_MESSAGE }) if fields.any? && fields.none? { |field| filled?(field) }

      errors = {}
      fields.each do |field|
        message = error_for(field)
        errors[field["name"]] = message if message
      end
      Result.new(errors)
    end

    # 必須の規則（R-20261125-1、案 B）: 下限 ≥1 の要素（required）は、それを含む入れ物（ENTRY と埋め込み CLUSTER、
    # field の containers。外側から並ぶ）が書かれるときに必須。入れ物が書かれるのは、配下に値が 1 つでもあるとき、
    # または自身の下限 ≥1 で親が書かれるとき（根の COMPOSITION は常に書かれる）。下限が分からない（nil）入れ物は
    # 書かれるものとして扱う（任意と見なして黙って通さない）。containers の無い field（古い登録）はこれまでどおり必須
    def required_now?(field)
      return false unless field["required"]
      return true unless field.key?("containers")

      written?(field["containers"])
    end

    private

    def written?(chain)
      return true if chain.empty?

      container = chain.last
      return true if filled_keys.include?(container["key"])

      (container["min"].nil? || container["min"] >= 1) && written?(chain[0...-1])
    end

    # 値が入った field を含む入れ物の key（外側の入れ物も含む）
    def filled_keys
      @filled_keys ||= @template.fields.select { |field| filled?(field) }
                                .flat_map { |field| (field["containers"] || []).map { |container| container["key"] } }.to_set
    end

    # 入力された値に数えるのは、項目そのものの値と、コード入力（__code）。単位（__units）・時刻（__time）だけでは数えない
    def filled?(field)
      @values[field["name"]].present? || @values["#{field['name']}__code"].present?
    end

    def error_for(field)
      raw = @values[field["name"]]

      return "必須項目です" if required_now?(field) && raw.blank?
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
