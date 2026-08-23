class Composition < ApplicationRecord
  # 権威ストアはCompositionCommitter経由のRMグラフ（openehr_rm_*テーブル）で、
  # AQLはそちらを照会する。このcompositionsテーブルはarchival・原本表示専用であり、
  # AQLの照会対象ではない。
  belongs_to :template

  def concept
    rm_composition["name"]&.dig("value") || template.template_id
  end
end
