module Opt
  # パスカード（スキーマ v1.2 の Hash）からの表示用の導出値。カード自体は変えない。
  module Pathcard
    # アーキタイプパス: identity.path のうち、所属アーキタイプの述語 [<archetype_id>] の
    # 最後の出現より後ろ（skoba/anlage#64、裁定 R-20261116-1）。埋め込み CLUSTER 配下は
    # CLUSTER を根とした相対パスになる。同じアーキタイプの入れ子（jp_referral の
    # organisation 内 organisation）があるので最後の出現で切る。述語が無ければ nil。
    def self.archetype_path(card)
      identity = card.fetch("identity")
      path = identity.fetch("path")
      predicate = "[#{identity.fetch('archetype_id')}]"
      index = path.rindex(predicate)
      return nil unless index

      path[(index + predicate.size)..]
    end
  end
end
