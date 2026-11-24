module QueryBuilder
  # リンタの知識源: Template.active のパスカード（docs/design/s2-query-builder-plan.md 2.1、判断 D1）。
  # 節パスは「アーキタイプのルートから下」で持つ（判断 D3）: カードの identity.path を、述語がそのアーキタイプ ID の節で切り、
  # 末尾の属性（/value）を落としたもの。/content[...] 直下でも SECTION 配下でも、埋め込み CLUSTER でも同じ規則になる。
  class Corpus
    Segment = Struct.new(:attribute, :predicate)

    def self.active
      new(Template.active.where.not(pathcards: nil).flat_map { |template| Array(template.pathcards) })
    end

    attr_reader :cards

    def initialize(cards)
      @cards = cards
    end

    # 画面が持ち回るカードの参照（"<template_id>|<path>"。設計書 6.4）
    def self.ref(card)
      card.fetch("identity").values_at("template_id", "path").join("|")
    end

    def find(ref)
      @cards.find { |card| self.class.ref(card) == ref }
    end

    def archetype_ids
      @archetype_ids ||= @cards.map { |card| card.dig("identity", "archetype_id") }.uniq
    end

    def include?(archetype_id) = archetype_ids.include?(archetype_id)

    # archetype_id のルートから見た節パス → カードの配列
    def node_paths(archetype_id)
      @node_paths ||= {}
      @node_paths[archetype_id] ||= @cards.each_with_object({}) do |card, index|
        relative_node_paths(card, archetype_id).each { |node_path| (index[node_path] ||= []) << card }
      end
    end

    def cards_at(archetype_id, node_path)
      node_paths(archetype_id).fetch(node_path, [])
    end

    private

    def relative_node_paths(card, archetype_id)
      segments = parse(card.dig("identity", "path"))
      segments = segments[0...-1] if segments.last && segments.last.predicate.nil? # 末尾の属性（value）
      segments.each_index.select { |i| segments[i].predicate == archetype_id }.map do |i|
        segments[(i + 1)..].map { |segment| segment.predicate ? "#{segment.attribute}[#{segment.predicate}]" : segment.attribute }.join("/")
      end
    end

    def parse(path)
      path.to_s.split("/").reject(&:empty?).map do |text|
        attribute, predicate = text.match(/\A([^\[]+)(?:\[(.+)\])?\z/).captures
        Segment.new(attribute, predicate)
      end
    end
  end
end
