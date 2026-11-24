require "rails_helper"

# skoba/anlage#73: Chrome 158 は `Storage.clearDataForOrigin` の `origin: '*'` を拒否する。
# capybara 3.40.0 は例の後始末で必ずこれを送るので、拒否されたときだけ別の消去に切り替える。
# ブラウザを使わずに、切り替えの経路だけを確かめる（CI の Chrome 157 ではこの経路を通らない）。
RSpec.describe CapybaraChromeStorageReset do
  let(:server) { instance_double(Capybara::Server, base_url: "http://127.0.0.1:41234") }
  let(:session) { instance_double(Capybara::Session, server: server) }
  let(:driver_class) do
    Class.new do
      attr_reader :calls
      attr_accessor :rejection

      def initialize(session)
        @session = session
        @calls = []
      end

      private

      attr_reader :session

      def execute_cdp(cmd, params = {})
        @calls << [ cmd, params ]
        raise rejection if rejection && params[:origin] == "*"
      end
    end.prepend(described_class)
  end
  let(:driver) { driver_class.new(session) }
  let(:wildcard_clear) { [ "Storage.clearDataForOrigin", { origin: "*", storageTypes: "cookies,local_storage" } ] }

  def clear_all_origins
    driver.send(:execute_cdp, "Storage.clearDataForOrigin", origin: "*", storageTypes: "cookies,local_storage")
  end

  context "origin '*' が「is not a valid URL」で拒否されたとき" do
    before do
      driver.rejection = Selenium::WebDriver::Error::InvalidArgumentError.new("invalid argument: * is not a valid URL")
    end

    it "cookie の全消去と、アプリの origin に対する同じ storageTypes の消去に切り替える" do
      clear_all_origins

      expect(driver.calls).to eq([
        wildcard_clear,
        [ "Storage.clearCookies", {} ],
        [ "Storage.clearDataForOrigin", { origin: "http://127.0.0.1:41234", storageTypes: "cookies,local_storage" } ]
      ])
    end

    it "サーバーが無いセッションでは、cookie の全消去だけを行う" do
      allow(session).to receive(:server).and_return(nil)

      clear_all_origins

      expect(driver.calls).to eq([ wildcard_clear, [ "Storage.clearCookies", {} ] ])
    end
  end

  context "origin '*' が拒否されないとき（Chrome 157 以前）" do
    it "元の呼び出しだけを行う" do
      clear_all_origins

      expect(driver.calls).to eq([ wildcard_clear ])
    end
  end

  context "別のエラーのとき" do
    it "同じ例外クラスでも文言が違えば、そのまま上げる" do
      driver.rejection = Selenium::WebDriver::Error::InvalidArgumentError.new("invalid argument: storageTypes")

      expect { clear_all_origins }.to raise_error(Selenium::WebDriver::Error::InvalidArgumentError, /storageTypes/)
      expect(driver.calls).to eq([ wildcard_clear ])
    end

    it "別の例外クラスは、そのまま上げる" do
      driver.rejection = Selenium::WebDriver::Error::UnknownError.new("is not a valid URL")

      expect { clear_all_origins }.to raise_error(Selenium::WebDriver::Error::UnknownError)
      expect(driver.calls).to eq([ wildcard_clear ])
    end
  end

  describe ".install" do
    let(:target) { Module.new }

    it "capybara 3.40.0 では、対象のモジュールに組み込む" do
      described_class.install(target, capybara_version: "3.40.0")

      expect(target.ancestors).to include(described_class)
    end

    it "版が違えば組み込まず、警告を 1 行出す" do
      expect { described_class.install(target, capybara_version: "3.41.0") }
        .to output(/\A.*capybara 3\.41\.0.*skoba\/anlage#\d+.*\n\z/).to_stderr

      expect(target.ancestors).not_to include(described_class)
    end

    it "この suite では Capybara の ChromeDriver に組み込まれている" do
      expect(Capybara::Selenium::Driver::ChromeDriver.ancestors).to include(described_class)
    end
  end
end
