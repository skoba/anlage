require "digest"

# 定義の組の 1 つの版（docs/design/definition-registration-plan.md 1 節・1.1 節、skoba/anlage#277、R-20261128-7）。
# 状態は draft（下書き）・active（動いている）・superseded。active は組ごとに 1 つ（表の部分索引）。
# 消す道は作らない（必ず止まる 3）
class DefinitionBundle < ApplicationRecord
  class LintFailed < StandardError; end

  STATUSES = %w[draft active superseded].freeze
  # registered?: 行を足したか。errors: 検査のエラー（Definitions::Problem）。message: 足さなかった理由
  Registration = Data.define(:bundle, :errors, :message) do
    def registered? = message.nil? && errors.empty?
  end

  validates :bundle_id, :version, :checksum, :files, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :version, uniqueness: { scope: :bundle_id }

  def self.checksum(files) = Digest::SHA256.hexdigest(JSON.generate(files.sort.to_h))

  # files: path → YAML の文字（Definitions::Files.read）。registered_by は運用者の名前（患者の記録や計測には使わない）
  def self.register(files, registered_by:)
    report = Definitions::Linter.check(files)
    return Registration.new(bundle: nil, errors: report.errors, message: nil) unless report.ok?

    bundle_id = report.bundle.id
    version = report.bundle.data["version"]
    existing = find_by(bundle_id:, version:)
    if existing
      message = existing.checksum == checksum(files) ? "組 #{bundle_id} の版 #{version} は登録済み" :
                                                     "組 #{bundle_id} の版 #{version} は、別の中身で登録済み。bundle.yml の version を上げる"
      return Registration.new(bundle: existing, errors: [], message:)
    end

    bundle = create!(bundle_id:, version:, files:, checksum: checksum(files), registered_by:,
                     lint_report: report.problems.map { _1.to_h.transform_keys(&:to_s) })
    Registration.new(bundle:, errors: [], message: nil)
  end

  # 下書き（か superseded）を動かす。直前に、いまのテンプレートで検査し直す
  def activate!
    report = Definitions::Linter.check(files)
    raise LintFailed, report.errors.map(&:to_s).join("\n") unless report.ok?

    transaction do
      self.class.where(bundle_id:, status: "active").where.not(id:).update_all(status: "superseded", updated_at: Time.current)
      update!(status: "active")
    end
  end
end
