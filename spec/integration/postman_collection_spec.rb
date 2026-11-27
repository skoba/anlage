require "rails_helper"

# Postman のコレクション（skoba/anlage#193、R-20261127-1 の 3、docs/design/m3-plan.md 9.3）の regression pin。
# コレクションの要求のパスは、anlage か、Gemfile.lock が指す openehr-rails の engine の routes にある入口だけ（推測で足さない）。
RSpec.describe "Postman のコレクション（docs/demo/postman/）" do
  COLLECTION = Rails.root.join("docs/demo/postman/anlage.postman_collection.json")
  ENVIRONMENT = Rails.root.join("docs/demo/postman/anlage.postman_environment.json")
  ENGINE_MOUNT = "/openehr".freeze
  SAMPLE = { "ehr_id" => "08ec1843-d1f3-4e8b-ab99-9194f41c745e",
             "composition_uid" => "833da556-875f-4cf2-9931-ef04a6c0ce73" }.freeze

  let(:collection) { JSON.parse(COLLECTION.read) }
  let(:environment) { JSON.parse(ENVIRONMENT.read) }

  def requests(items = collection["item"])
    items.flat_map { |item| item["item"] ? requests(item["item"]) : [ item ] }
  end

  # {{base_url}} を除き、ほかの変数は見本の値に置き換えたパス（クエリは除く）
  def path_of(request)
    raw = request.dig("request", "url", "raw")
    raw.delete_prefix("{{base_url}}").gsub(/\{\{(\w+)\}\}/) { SAMPLE.fetch(Regexp.last_match(1)) }.split("?").first
  end

  def recognize(method, path)
    if path.start_with?("#{ENGINE_MOUNT}/")
      OpenehrRails::Engine.routes.recognize_path(path.delete_prefix(ENGINE_MOUNT), method:)
    else
      Rails.application.routes.recognize_path(path, method:)
    end
  end

  it "v2.1 の形式で、FHIR と openEHR REST のフォルダを持つ" do
    expect(collection.dig("info", "schema")).to eq("https://schema.getpostman.com/json/collection/v2.1.0/collection.json")
    expect(collection["item"].map { _1["name"] }).to eq([ "FHIR", "openEHR REST" ])
  end

  it "Basic 認証はコレクションに 1 か所だけで、利用者名とパスワードの変数を引く。要求ごとの認証は持たない" do
    expect(collection["auth"]["type"]).to eq("basic")
    expect(collection["auth"]["basic"].to_h { [ _1["key"], _1["value"] ] }).to eq("username" => "{{username}}", "password" => "{{password}}")
    expect(requests.map { _1["request"]["auth"] }.compact).to be_empty
  end

  it "環境の雛形は、接続先・利用者名・パスワード（空）・EHR ID・記録の uid を持つ" do
    values = environment["values"].to_h { [ _1["key"], _1["value"] ] }
    expect(values.keys).to eq(%w[base_url username password ehr_id composition_uid])
    expect(values["password"]).to eq("")
    expect(values["base_url"]).to eq("http://localhost:8080")
  end

  # R-20261127-5 の 1: いつも 0 件になる要求（anlage での FHIR の Observation。既知の制限 19）は入れない
  it "FHIR の Observation の要求は入れない（FHIR 2 件、openEHR REST 3 件）" do
    expect(collection["item"].map { |folder| folder["item"].size }).to eq([ 2, 3 ])
    expect(requests.map { _1.dig("request", "url", "raw") }).to all(satisfy { !_1.include?("/Observation") })
  end

  it "すべての要求のパスが、anlage か engine の routes で解決できる" do
    expect(requests.size).to eq(5)
    requests.each do |request|
      method = request.dig("request", "method").downcase.to_sym
      expect { recognize(method, path_of(request)) }.not_to raise_error, "#{request['name']}: #{method} #{path_of(request)}"
    end
  end

  it "AQL の要求は、台本 H5 の問いに uid の列を足し、EHR ID を query_parameters で渡す。応答の uid を composition_uid に入れる" do
    aql = requests.find { _1["name"] == "AQL の実行" }
    body = JSON.parse(aql.dig("request", "body", "raw"))
    expect(body["q"]).to include("SELECT c/uid/value AS uid, o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude AS systolic")
    expect(body["q"]).to include("FROM EHR e[ehr_id/value=$ehr_id] CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]")
    expect(body["query_parameters"]).to eq("ehr_id" => "{{ehr_id}}")
    script = aql["event"].find { _1["listen"] == "test" }.dig("script", "exec").join("\n")
    expect(script).to include('.set("composition_uid", uid)')
  end
end
