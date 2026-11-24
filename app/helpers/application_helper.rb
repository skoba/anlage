module ApplicationHelper
  # 左ナビで印を付ける項目（skoba/anlage#95）。帳票はテンプレートから開くので「テンプレート」、
  # カルテ記録の詳細は「カルテ記録一覧」に入れる。
  NAV_CURRENT = {
    "templates" => :templates, "forms" => :templates,
    "compositions" => :compositions, "pathcards" => :pathcards
  }.freeze

  def nav_current
    NAV_CURRENT[controller_name]
  end
end
