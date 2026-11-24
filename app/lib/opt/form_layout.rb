module Opt
  # 帳票の入力欄を、ルート（SECTION → ENTRY → 埋め込み CLUSTER）の入れ子にまとめる（skoba/anlage#119、M2 の E）。
  # 名前はすべて web_template に登録時に入れたテンプレート上の名前（section_labels、entry の label、field の root_chain）。
  # 返すのは Node の配列。Node#items は、子の Node か field（Hash）を文書順に並べたもの。
  class FormLayout
    Node = Struct.new(:key, :label, :items)

    def self.call(template)
      new(template).call
    end

    def initialize(template)
      @template = template
    end

    def call
      root = Node.new(nil, nil, [])
      @template.entries.each_with_index do |entry, entry_index|
        (entry["fields"] || []).each do |field|
          parent = keys_for(field, entry, entry_index).inject(root) { |node, (key, label)| child(node, key, label) }
          parent.items << field
        end
      end
      root.items
    end

    private

    def keys_for(field, entry, entry_index)
      sections(field) +
        [ [ [ :entry, entry_index ], entry["label"] || entry["concept"] ] ] +
        Array(field["root_chain"]).map { |root| [ [ :root, root["archetype_id"], root["index"] ], root["label"] ] }
    end

    # field の path の中の SECTION（外側から）。名前は web_template["section_labels"]（#80）
    def sections(field)
      labels = @template.web_template["section_labels"] || {}
      prefix = ""
      field["path"].to_s.split("/").reject(&:empty?).filter_map do |segment|
        prefix = "#{prefix}/#{segment}"
        next unless (archetype_id = segment[/\[(openEHR-EHR-SECTION\.[^\]]+)\]/, 1])

        [ [ :section, prefix ], labels[prefix] || archetype_id.split(".")[1] ]
      end
    end

    def child(node, key, label)
      node.items.find { |item| item.is_a?(Node) && item.key == key } || Node.new(key, label, []).tap { |created| node.items << created }
    end
  end
end
