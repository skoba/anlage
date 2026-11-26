module Records
  # canonical の COMPOSITION から、ELEMENT の名前と値の表示を、文書の順に取り出す（skoba/anlage#182、
  # docs/design/m3-plan.md 8.2）。テンプレートが未登録の記録の閲覧に使う。意味はテンプレートから引けないので、
  # 記録に書いてある名前（name/value）と値だけを出す
  module ElementList
    module_function

    def call(node, found = [])
      case node
      when Array then node.each { call(_1, found) }
      when Hash
        if node["_type"] == "ELEMENT"
          found << [ node.dig("name", "value").to_s, display(node["value"]) ]
        else
          node.each_value { call(_1, found) }
        end
      end
      found
    end

    # テキスト・コード・日時は value、量は magnitude と units、件数は magnitude
    def display(value)
      return "" unless value.is_a?(Hash)
      return value["value"].to_s if value.key?("value")

      [ value["magnitude"], value["units"] ].compact.join(" ")
    end
  end
end
