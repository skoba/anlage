require "rack/auth/basic"
require "active_support/security_utils"

# 任意の Basic 認証（skoba/anlage#163、R-20261126-2 の 4。docs/design/basic-auth-plan.md）。
# 利用者名とパスワードを両方与えたときだけ、アプリの全体（anlage の画面、engine の画面と API）にかける。
# 与えなければ素通し（いまと同じ）。片方だけなら起動を止める。/up（ヘルスチェック）はかけない。
# rack の Rack::Auth::Basic を使う（gem は足さない）。config/application.rb で列に入れる。
class OptionalBasicAuth
  REALM = "Anlage".freeze
  UNPROTECTED_PATHS = %w[/up].freeze

  def initialize(app, username:, password:)
    @app = app
    username = username.presence
    password = password.presence
    if username.nil? != password.nil?
      missing = username ? "ANLAGE_BASIC_AUTH_PASSWORD" : "ANLAGE_BASIC_AUTH_USERNAME"
      raise ArgumentError, "Basic 認証には利用者名とパスワードの両方が要る（#{missing} が無い）"
    end

    @protected_app = username && Rack::Auth::Basic.new(app, REALM) do |given_username, given_password|
      # 両方を比べる（& は短絡しない）。時間の差で漏れない比べ方
      ActiveSupport::SecurityUtils.secure_compare(given_username, username) &
        ActiveSupport::SecurityUtils.secure_compare(given_password, password)
    end
  end

  def call(env)
    return @app.call(env) if @protected_app.nil? || UNPROTECTED_PATHS.include?(env["PATH_INFO"])

    @protected_app.call(env)
  end
end
