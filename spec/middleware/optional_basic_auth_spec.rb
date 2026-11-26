require "rails_helper"

# 任意の Basic 認証（skoba/anlage#163、R-20261126-2 の 4。docs/design/basic-auth-plan.md）。
# 環境変数で利用者名とパスワードを両方与えたときだけ、全体にかける。/up（ヘルスチェック）はかけない。
RSpec.describe OptionalBasicAuth do
  let(:inner) { ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] } }

  def request(middleware, path, credentials: nil)
    headers = credentials ? { "HTTP_AUTHORIZATION" => "Basic #{[ credentials ].pack('m0')}" } : {}
    Rack::MockRequest.new(middleware).get(path, headers)
  end

  context "利用者名とパスワードを与えたとき" do
    let(:middleware) { described_class.new(inner, username: "demo", password: "s3cret") }

    it "認証情報が無ければ 401 で、realm は Anlage" do
      response = request(middleware, "/patients")

      expect(response.status).to eq(401)
      expect(response["www-authenticate"]).to eq('Basic realm="Anlage"')
    end

    it "正しければ通す。違えば 401" do
      expect(request(middleware, "/openehr/query", credentials: "demo:s3cret").status).to eq(200)
      expect(request(middleware, "/openehr/query", credentials: "demo:wrong").status).to eq(401)
      expect(request(middleware, "/openehr/query", credentials: "other:s3cret").status).to eq(401)
    end

    it "/up（ヘルスチェック）はかけない" do
      expect(request(middleware, "/up").status).to eq(200)
    end
  end

  it "どちらも与えなければ（空の文字列も）、いまと同じに素通し" do
    expect(request(described_class.new(inner, username: nil, password: nil), "/patients").status).to eq(200)
    expect(request(described_class.new(inner, username: "", password: ""), "/patients").status).to eq(200)
  end

  it "片方だけを与えたら、起動を止める（かけたつもりで開いたままにしない）" do
    expect { described_class.new(inner, username: "demo", password: nil) }.to raise_error(ArgumentError, /ANLAGE_BASIC_AUTH_PASSWORD/)
    expect { described_class.new(inner, username: "", password: "s3cret") }.to raise_error(ArgumentError, /ANLAGE_BASIC_AUTH_USERNAME/)
  end

  it "アプリのミドルウェアの列に入っている（テスト環境は環境変数を与えないので素通し）" do
    expect(Rails.application.middleware.map(&:klass)).to include(described_class)
  end
end
