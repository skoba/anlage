module ApplicationHelper
  # 左ナビで印を付ける項目（skoba/anlage#95）。帳票はテンプレートから開くので「テンプレート」、
  # カルテ記録の詳細は「カルテ記録一覧」に入れる。
  NAV_CURRENT = {
    "templates" => :templates, "forms" => :templates,
    "compositions" => :compositions, "pathcards" => :pathcards, "queries" => :queries
  }.freeze

  def nav_current
    NAV_CURRENT[controller_name]
  end

  # クエリビルダー: カードの名前（ラベル。無ければ at-code）と、テンプレートつきの表示
  def query_card_name(card)
    card.dig("semantics", "labels", 0, "text") || card.dig("identity", "at_code")
  end

  def query_card_label(card)
    "#{query_card_name(card)}（#{card.dig('identity', 'template_id')}）"
  end
end
