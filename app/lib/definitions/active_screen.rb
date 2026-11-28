module Definitions
  # 患者の画面に使う定義を選ぶ（docs/design/definition-registration-plan.md 2 節・3 節・10 節、skoba/anlage#283、R-20261128-7 の回答 2・3）。
  # ANLAGE_DEFINITION_BUNDLE（運用者の設定）の組の active の版。無い・通らないときは組み込みの定義と、理由の文（500 にしない）。
  # 組の行は表示のたびに表から読む（別のプロセスの rake で動かした版も、次の表示に届く）。覚えるのは検査の結果だけで、
  # 鍵は組の行の id と updated_at、動いているテンプレートの id と checksum
  module ActiveScreen
    ENV_KEY = "ANLAGE_DEFINITION_BUNDLE".freeze
    CACHE_LIMIT = 32
    # bundle_id・version: いま出している組と版（組み込みは builtin）。screen: 画面の定義（Linter::Definition）。
    # notice: 組み込みに落ちたときの理由の文。problems: 検査のエラー（Definitions::Problem）
    Result = Data.define(:bundle_id, :version, :screen, :notice, :problems)

    @cache = {}
    @mutex = Mutex.new

    module_function

    # screen: 画面の id（ボタンの open.screen、?screen=）。組に無ければ start の画面
    def call(env: ENV, screen: nil)
      bundle_id = env[ENV_KEY].presence
      return builtin unless bundle_id

      bundle = DefinitionBundle.find_by(bundle_id:, status: "active")
      return builtin(notice: "定義の組 #{bundle_id} に、動いている版がありません。既定の画面を出しています。") unless bundle

      report = lint(bundle)
      unless report.ok?
        Rails.logger.warn("[definitions] #{bundle_id} #{bundle.version} が検査に通らない: #{report.errors.map(&:to_s).join(' / ')}")
        return builtin(notice: "定義の組 #{bundle_id} #{bundle.version} は、いまのテンプレートで検査に通りません。既定の画面を出しています。",
                       problems: report.errors)
      end

      chosen = report.screens.find { _1.id == screen } || start_screen(report)
      Result.new(bundle_id:, version: bundle.version, screen: chosen, notice: nil, problems: [])
    end

    def builtin(notice: nil, problems: [])
      report = Builtin.report
      Result.new(bundle_id: report.bundle.id, version: report.bundle.data["version"], screen: Builtin.patient_screen, notice:, problems:)
    end

    def start_screen(report) = report.screens.find { _1.id == report.bundle.data.dig("start", "screen") }

    def lint(bundle)
      templates = Template.active.order(:id).to_a
      key = [ bundle.id, bundle.updated_at.to_r, templates.map { [ _1.id, _1.checksum ] } ]
      @mutex.synchronize do
        @cache.clear if @cache.size >= CACHE_LIMIT
        @cache[key] ||= Linter.check(bundle.files, templates:)
      end
    end
  end
end
