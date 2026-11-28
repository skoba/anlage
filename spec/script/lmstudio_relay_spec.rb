require "rails_helper"
require "net/http"
require "tmpdir"
require Rails.root.join("script/lmstudio_relay").to_s

# 開発機の道具: WSL の中から、Windows 側の LM Studio（127.0.0.1:1234 だけで待ち受け）への中継
# （docs/reports/s4-lmstudio-network-check.md 5 節。R-20261128-10。skoba/anlage#286）。
# WSL の中の 127.0.0.1 で要求を受け、本文を Windows 側の curl.exe に標準入力で渡して、状態の番号と本文を返す。
# アプリのコードではない。spec は、curl.exe の代わりの、決まった応答を返すプログラムだけを使う。Windows も LM Studio も呼ばない。
RSpec.describe LmstudioRelay do
  # curl.exe の代わり。受けた引数と標準入力を JSON でファイルに残し、決まった本文と、中継が読む状態の行を出す
  def fake_curl(dir, status: 200, body: %({"ok":true}), exit_code: 0)
    path = File.join(dir, "fake_curl.rb")
    File.write(path, <<~RUBY)
      require "json"
      File.write(#{File.join(dir, 'seen.json').inspect}, JSON.generate(args: ARGV, stdin: $stdin.read))
      exit #{exit_code} unless #{exit_code}.zero?
      $stdout.write(#{body.inspect} + "\\n#{LmstudioRelay::STATUS_MARK}#{status}")
    RUBY
    [ RbConfig.ruby, path ]
  end

  def seen(dir) = JSON.parse(File.read(File.join(dir, "seen.json")))

  def with_relay(**fake)
    Dir.mktmpdir do |dir|
      relay = described_class.new(port: 0, command: fake_curl(dir, **fake))
      thread = Thread.new { relay.run }
      begin
        yield "http://127.0.0.1:#{relay.port}", dir
      ensure
        relay.stop
        thread.join(2)
      end
    end
  end

  def post(base_url, path, body, headers = {})
    uri = URI("#{base_url}#{path}")
    Net::HTTP.start(uri.host, uri.port) do |http|
      http.post(uri.path, body, { "Content-Type" => "application/json" }.merge(headers))
    end
  end

  describe "要求を、Windows 側の curl.exe に渡す" do
    it "POST の本文を標準入力で渡し、同じパスの、Windows 側の 127.0.0.1:1234 に送らせる。状態の番号と本文を返す" do
      with_relay(body: %({"choices":[]})) do |base_url, dir|
        response = post(base_url, "/v1/chat/completions", %({"model":"google/gemma-4-12b","messages":[{"role":"user","content":"血圧"}]}))

        expect(response.code).to eq("200")
        expect(response.body).to eq(%({"choices":[]}))
        expect(JSON.parse(seen(dir)["stdin"])["messages"].first["content"]).to eq("血圧")
        expect(seen(dir)["args"]).to include("http://127.0.0.1:1234/v1/chat/completions", "--data-binary", "@-", "POST")
      end
    end

    it "GET は、本文を渡さない" do
      with_relay(body: %({"data":[]})) do |base_url, dir|
        response = Net::HTTP.get_response(URI("#{base_url}/v1/models"))

        expect(response.body).to eq(%({"data":[]}))
        expect(seen(dir)["args"]).to include("http://127.0.0.1:1234/v1/models", "GET")
        expect(seen(dir)["args"]).not_to include("--data-binary")
      end
    end

    it "LM Studio が返したエラーの番号は、そのまま返す" do
      with_relay(status: 400, body: %({"error":"bad"})) do |base_url, _dir|
        response = post(base_url, "/v1/chat/completions", "{}")

        expect(response.code).to eq("400")
        expect(response.body).to eq(%({"error":"bad"}))
      end
    end

    it "curl.exe が失敗したとき（LM Studio のサーバーが立っていない、など）は、502 と、失敗の番号を返す" do
      with_relay(exit_code: 7) do |base_url, _dir|
        response = post(base_url, "/v1/chat/completions", "{}")

        expect(response.code).to eq("502")
        expect(JSON.parse(response.body)["error"]).to include("curl", "7")
      end
    end

    it "Authorization のヘッダは、渡さない（コマンドの引数に、トークンを出さない）" do
      with_relay do |base_url, dir|
        post(base_url, "/v1/chat/completions", "{}", "Authorization" => "Bearer lm-not-a-real-token")

        expect(seen(dir)["args"].join(" ")).not_to include("lm-not-a-real-token")
      end
    end
  end

  describe "同じ機械の中だけ" do
    it "待ち受けは、127.0.0.1 だけ" do
      with_relay do |_base_url, _dir|
        expect(described_class::BIND).to eq("127.0.0.1")
      end
    end

    it "中継の先が、同じ機械の中（127.0.0.1・localhost）でなければ、立ち上げのときに断る" do
      expect { described_class.new(port: 0, target: "http://192.168.0.10:1234") }.to raise_error(ArgumentError, /同じ機械の中/)
      expect { described_class.new(port: 0, target: "https://example.com") }.to raise_error(ArgumentError, /同じ機械の中/)
    end
  end

  describe "アダプタから使う" do
    it "Llm::Adapters::LmStudio の接続先を中継に向けると、アダプタの検査（同じ機械の中だけ）を変えずに、応答を受け取れる" do
      reply = JSON.generate(model: "google/gemma-4-12b",
                            choices: [ { index: 0, finish_reason: "stop", message: { role: "assistant", content: %({"columns": [1]}) } } ],
                            usage: { prompt_tokens: 1500, completion_tokens: 70 })
      with_relay(body: reply) do |base_url, _dir|
        adapter, reason = Llm::Adapters::LmStudio.build({ "ANLAGE_LLM_MODEL" => "google/gemma-4-12b", "ANLAGE_LLM_BASE_URL" => "#{base_url}/v1" })

        expect(reason).to be_nil
        expect(adapter.external?).to be(false)
        expect(adapter.complete(instructions: "指示文", input: "問い").text).to eq(%({"columns": [1]}))
      end
    end
  end
end
