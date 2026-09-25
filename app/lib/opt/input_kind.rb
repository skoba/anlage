module Opt
  # フォーム入力の方針属性（skoba/anlage#33 裁定 A）。登録時に一度だけ導出して
  # web_template の field に `input_kind` として保存し、view／validator／builder は
  # これを読むだけで方針を再導出しない。rm_type はモデルの事実として保持する
  # （パスカード v1.2 の semantics.rm_type と整合）。
  #
  #   number       DV_QUANTITY／DV_COUNT
  #   select       DV_CODED_TEXT でローカル code_list あり
  #   coded_free   DV_CODED_TEXT だが code_list が空（外部値集合のみ）で DV_TEXT 代替あり
  #                → 自由記載を DV_TEXT で保存（OR 制約の正規の一方）
  #   coded_manual 同上で DV_TEXT 代替なし（コード化必須）→ 用語サービス未接続のため
  #                system／code の手入力を要求する。WP5（$lookup）接続後はこの導出だけを
  #                変える（docs/backlog.md 13 項）
  #   date / time / datetime  DV_DATE／DV_TIME／DV_DATE_TIME（skoba/anlage#35: ネイティブ入力。
  #                datetime は date＋「時刻（任意）」の 2 入力で、ISO 部分精度のまま保存）
  #   text         それ以外
  module InputKind
    NUMBER_TYPES = %w[DV_QUANTITY DV_COUNT].freeze
    TEMPORAL_KINDS = { "DV_DATE" => "date", "DV_TIME" => "time", "DV_DATE_TIME" => "datetime" }.freeze

    module_function

    def for(field, alternatives)
      rm_type = field["rm_type"]
      return "number" if NUMBER_TYPES.include?(rm_type)
      return TEMPORAL_KINDS.fetch(rm_type) if TEMPORAL_KINDS.key?(rm_type)
      return "text" unless rm_type == "DV_CODED_TEXT"
      return "select" if Array(field["code_list"]).any?

      Array(alternatives).include?("DV_TEXT") ? "coded_free" : "coded_manual"
    end
  end
end
