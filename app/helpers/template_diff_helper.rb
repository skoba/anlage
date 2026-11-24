# 版差分の画面（skoba/anlage#100）の文言。正典は docs/demo/ui-vocabulary.md
module TemplateDiffHelper
  PATHCARD_ASPECT_LABELS = {
    "labels" => "ラベル", "descriptions" => "説明", "container_labels" => "祖先の名前",
    "rm_type" => "型", "constraints" => "制約", "bindings" => "コード束縛"
  }.freeze

  def pathcard_aspect_label(aspect)
    PATHCARD_ASPECT_LABELS.fetch(aspect, aspect)
  end

  # 文字列の並びは「／」でつなぎ、それ以外（制約・束縛）は JSON で出す
  def diff_value(value)
    value.is_a?(Array) && value.all?(String) ? value.join("／") : value.to_json
  end

  def pathcard_label(card)
    card.dig("semantics", "labels", 0, "text") || card.dig("identity", "at_code")
  end
end
