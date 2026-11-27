require "rails_helper"

# LLM のオンとオフ（docs/design/s4-nl-aql-plan.md 10.1 節。R-20261127-14）。運用する人が、環境変数で決める。
# オンになるのは、ANLAGE_LLM（アダプタの名前）と、そのアダプタが要るもの（鍵など）の両方がそろったときだけ。
RSpec.describe Llm::Settings do
  let(:recordings) { Dir.mktmpdir }

  after { FileUtils.remove_entry(recordings) }

  def settings(env)
    described_class.from_env(env)
  end

  describe "オフ" do
    it "設定が無ければオフ。アダプタは無い" do
      off = settings({})

      expect(off).not_to be_on
      expect(off.adapter).to be_nil
      expect(off.reason).to be_nil
    end

    it "ANLAGE_LLM が空、off のときもオフ" do
      expect(settings("ANLAGE_LLM" => "")).not_to be_on
      expect(settings("ANLAGE_LLM" => "off")).not_to be_on
      expect(settings("ANLAGE_LLM" => "OFF")).not_to be_on
    end

    it "鍵だけがあっても、オフ（鍵を置いただけでは、外を呼ばない）" do
      off = settings("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key")

      expect(off).not_to be_on
      expect(off.adapter).to be_nil
    end

    it "知らないアダプタの名前はオフ。理由が付く" do
      off = settings("ANLAGE_LLM" => "somewhere")

      expect(off).not_to be_on
      expect(off.reason).to eq("知らないアダプタの名前です（somewhere）。")
    end

    it "まだ入っていないアダプタ（anthropic、local）はオフ。理由が付く。理由に鍵の値は出ない" do
      off = settings("ANLAGE_LLM" => "anthropic", "ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key")

      expect(off).not_to be_on
      expect(off.reason).to eq("このアダプタは、まだ使えません（anthropic）。")
      expect(off.reason).not_to include("sk-ant")
      expect(off.inspect).not_to include("sk-ant")
      expect(settings("ANLAGE_LLM" => "local").reason).to eq("このアダプタは、まだ使えません（local）。")
    end

    it "recorded で、記録のディレクトリが無いときはオフ。理由が付く" do
      expect(settings("ANLAGE_LLM" => "recorded").reason).to eq("記録した応答のディレクトリ（ANLAGE_LLM_RECORDINGS）がありません。")
      expect(settings("ANLAGE_LLM" => "recorded", "ANLAGE_LLM_RECORDINGS" => "/nonexistent/dir")).not_to be_on
    end
  end

  describe "オン" do
    it "recorded と、記録のディレクトリがそろうと、オン" do
      on = settings("ANLAGE_LLM" => "recorded", "ANLAGE_LLM_RECORDINGS" => recordings)

      expect(on).to be_on
      expect(on.adapter).to be_a(Llm::Adapters::Recorded)
      expect(on.adapter_name).to eq("recorded")
      expect(on.reason).to be_nil
    end
  end

  describe "回数の上限" do
    it "既定は 1 日 100 回" do
      expect(settings({}).daily_call_limit).to eq(100)
    end

    it "ANLAGE_LLM_DAILY_CALL_LIMIT で決められる。0 は、1 回も呼ばない" do
      expect(settings("ANLAGE_LLM_DAILY_CALL_LIMIT" => "20").daily_call_limit).to eq(20)
      expect(settings("ANLAGE_LLM_DAILY_CALL_LIMIT" => "0").daily_call_limit).to eq(0)
    end

    it "数でない値、負の値は、既定に戻す" do
      expect(settings("ANLAGE_LLM_DAILY_CALL_LIMIT" => "たくさん").daily_call_limit).to eq(100)
      expect(settings("ANLAGE_LLM_DAILY_CALL_LIMIT" => "-1").daily_call_limit).to eq(100)
    end
  end
end
