module Opt
  # パース済みの OPT から、C_ARCHETYPE_ROOT ごと（＝同じアーキタイプの複数インスタンス別）の
  # term_definitions を返す。キーはルートの RM path（archetype_id 述語。FieldExtractor／
  # PathcardExtractor と同じ書式。テンプレートのルート自身は ""）、値はその path に現れるルートを
  # 文書順に並べた配列で、各要素は { at_code => { "text" => .., "description" => .. } }。
  #
  # openehr 2.5.0（skoba/openehr-ruby#58）から、CArchetypeRoot#term_definitions
  # （{ language => { code => ArchetypeTerm } }）がルートごとの値を持つ。それまでは gem が
  # component_terminologies[archetype_id] に畳み込んで後勝ちにしていたので、anlage が OPT の XML を
  # Nokogiri で読み直していた（Opt::TemplateTerms。2026-11-24 に撤去）。
  # skoba/anlage#31 の container_labels と、ELEMENT の改名のインスタンス別の扱いが、これを共有する。
  class RootTerms
    ROOT = OpenEHR::AM::Archetype::ConstraintModel::CArchetypeRoot

    def self.call(opt)
      new(opt).call
    end

    def initialize(opt)
      @opt = opt
    end

    def call
      terms = Hash.new { |hash, key| hash[key] = [] }
      each_root(@opt.definition) { |root| terms[root.path == "/" ? "" : root.path] << root_terms(root) }
      terms
    end

    private

    def each_root(node, &block)
      yield node if node.is_a?(ROOT)
      return unless node.respond_to?(:attributes)

      (node.attributes || []).each { |attribute| (attribute.children || []).each { |child| each_root(child, &block) } }
    end

    # OPT は 1 つの言語で書き出される（登録する OPT は lang=ja 前提。docs/design/pathcards-language-policy.md）
    def root_terms(root)
      definitions = (root.term_definitions || {}).values.first || {}
      definitions.transform_values { |term| { "text" => term.items["text"], "description" => term.items["description"] } }
    end
  end
end
