module CompositionsHelper
  # 記録の中身の 1 項目の表示（skoba/anlage#191、docs/design/m3-plan.md 9.1）。値は記録（Opt::CompositionReader の読み戻し）から、
  # 選択肢の表示と単位はテンプレート（field の code_labels・units）から。値が無ければ nil
  def record_field_value(field, values)
    value = values[field["name"]]
    return nil if value.blank?

    case field["input_kind"]
    when "select" then field.dig("code_labels", value) || value
    when "number" then [ value, values["#{field['name']}__units"].presence || field["units"].presence ].compact.join(" ")
    else value
    end
  end

  # 入れ子の下に、値のある項目が 1 つでもあるか
  def record_group_filled?(node, values)
    node.items.any? do |item|
      item.is_a?(Opt::FormLayout::Node) ? record_group_filled?(item, values) : record_field_value(item, values).present?
    end
  end
end
