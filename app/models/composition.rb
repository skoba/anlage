class Composition < ApplicationRecord
  # 権威ストアはCompositionCommitter経由のRMグラフ（openehr_rm_*テーブル）で、
  # AQLはそちらを照会する。このcompositionsテーブルはarchival・原本表示専用であり、
  # AQLの照会対象ではない。
  belongs_to :template

  # 原本は版ごとに 1 行（同じ uid の行が版の数だけ並ぶ。skoba/anlage#138）。各記録の新しい版の行だけ。
  # uid の無い古い行（#9 より前）は、それぞれを 1 つの記録として残す
  scope :latest_versions, -> { where(uid: nil).or(where(id: unscoped.where.not(uid: nil).group(:uid).select("MAX(id)"))) }

  # 削除済み（RM の head の版の lifecycle が 523。skoba/anlage#140）の記録の uid
  def self.deleted_uids
    OpenehrRails::Rm::Composition.latest.joins(:version)
                                 .where(openehr_rm_versions: { lifecycle_state_code: OpenehrRails::Rm::Version::LIFECYCLE_DELETED })
                                 .pluck(:uid)
  end

  # 一覧に出す記録: 各記録の新しい版の行で、削除済みでないもの
  scope :listed, -> { latest_versions.where.not(uid: deleted_uids).or(latest_versions.where(uid: nil)) }

  def rm_head
    uid && OpenehrRails::Rm::Composition.latest.find_by(uid: uid)
  end

  def deleted?
    rm_head&.version&.lifecycle_state_code == OpenehrRails::Rm::Version::LIFECYCLE_DELETED
  end

  # 同じ記録の版の行（古い順）。版の番号は、この並びの 1 から（commit 1 回につき行 1 つ）
  def versions
    uid ? self.class.where(uid: uid).order(:id) : self.class.where(id: id)
  end

  def latest_version?
    versions.last == self
  end

  def concept
    rm_composition["name"]&.dig("value") || template.template_id
  end
end
