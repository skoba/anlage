module ApplicationHelper
  # 左ナビで印を付ける項目（skoba/anlage#95）。帳票はテンプレートから開くので「テンプレート」、
  # カルテ記録の詳細は「カルテ記録一覧」に入れる。
  NAV_CURRENT = {
    "patients" => :patients, "templates" => :templates, "forms" => :templates,
    "compositions" => :compositions, "pathcards" => :pathcards, "queries" => :queries
  }.freeze

  def nav_current
    NAV_CURRENT[controller_name]
  end

  # クエリビルダー: カードの名前（ラベル。無ければ at-code）と、テンプレートつきの表示
  def query_card_name(card)
    card.dig("semantics", "labels", 0, "text") || card.dig("identity", "at_code")
  end

  # 別名表（skoba/anlage#152）で出たカードの理由。字面で当たったカードは nil（文言は docs/demo/ui-vocabulary.md）
  def alias_reason(card)
    "別名「#{card['alias']}」で一致" if card["alias"].present?
  end

  # 「対応させない」行だけに当たって 0 件になったときの案内（黙って 0 件にしない。R-20261125-11）。それ以外は nil
  def search_guidance(query, results)
    return nil unless results.empty? && Opt::SearchAliases.default.lookup(query)&.exclude?

    "「#{query.to_s.strip}」だけでは、項目を特定できません。ほかの語と組み合わせて探してください。"
  end

  def query_card_label(card)
    "#{query_card_name(card)}（#{card.dig('identity', 'template_id')}）"
  end
end
