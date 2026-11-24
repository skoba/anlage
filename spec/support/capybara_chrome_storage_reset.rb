# skoba/anlage#73 のつなぎの回避策（裁定 R-20261124-1）。
#
# capybara 3.40.0 の `Capybara::Selenium::Driver::ChromeDriver#reset!` は、例の後始末で
# `Storage.clearDataForOrigin` に `origin: '*'` を渡す（chrome_driver.rb:54）。Chrome 158 は
# これを `invalid argument: * is not a valid URL` で拒否するので、`js: true` の例がすべて
# 後始末で落ちる。拒否されたときだけ、cookie の全消去と、アプリの origin に対する
# 同じ storageTypes の消去に切り替える。ほかのエラーはそのまま上げる。
#
# 消す条件（skoba/anlage#74）: 上流（teamcapybara/capybara#2868）の修正が入った capybara に
# 切り替えたら、このファイルと spec/lib/capybara_chrome_storage_reset_spec.rb を消す。
# capybara 3.40.0 以外では組み込まれず、警告が 1 行出る。
module CapybaraChromeStorageReset
  CAPYBARA_VERSION = "3.40.0"
  REJECTION = "is not a valid URL"

  def self.install(target, capybara_version: Capybara::VERSION)
    if capybara_version == CAPYBARA_VERSION
      target.prepend(self)
    else
      warn "CapybaraChromeStorageReset は capybara #{capybara_version} には組み込まない" \
           "（#{CAPYBARA_VERSION} 用。要否を確かめて消す: skoba/anlage#74）"
    end
  end

  private

  def execute_cdp(cmd, params = {})
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError => e
    raise unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*" && e.message.include?(REJECTION)

    super("Storage.clearCookies")
    origin = session&.server&.base_url
    super(cmd, params.merge(origin: origin)) if origin
  end
end

CapybaraChromeStorageReset.install(Capybara::Selenium::Driver::ChromeDriver)
