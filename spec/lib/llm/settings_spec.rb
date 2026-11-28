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

    it "local で、モデルの名前が無いときはオフ。理由が付く" do
      expect(settings("ANLAGE_LLM" => "local").reason).to eq("モデルの名前（ANLAGE_LLM_MODEL）がありません。")
    end

    it "local と、モデルの名前がそろうと、オン。外に文を送らないアダプタ。鍵は要らない" do
      on = settings("ANLAGE_LLM" => "local", "ANLAGE_LLM_MODEL" => "qwen3:4b")

      expect(on).to be_on
      expect(on).not_to be_external
      expect(on.adapter_name).to eq("local")
    end

    it "lmstudio と、モデルの名前がそろうと、オン。外に文を送らないアダプタ。トークンは要らない" do
      expect(settings("ANLAGE_LLM" => "lmstudio").reason).to eq("モデルの名前（ANLAGE_LLM_MODEL）がありません。")

      on = settings("ANLAGE_LLM" => "lmstudio", "ANLAGE_LLM_MODEL" => "google/gemma-4-12b")
      expect(on).to be_on
      expect(on).not_to be_external
      expect(on.adapter_name).to eq("lmstudio")
      expect(on.adapter).to be_a(Llm::Adapters::LmStudio)
    end

    it "anthropic で、鍵かモデルの名前が無いときはオフ。理由が付く。理由に鍵の値は出ない" do
      expect(settings("ANLAGE_LLM" => "anthropic", "ANLAGE_LLM_MODEL" => "claude-haiku-5-5").reason)
        .to eq("API の鍵（ANTHROPIC_API_KEY）がありません。")

      off = settings("ANLAGE_LLM" => "anthropic", "ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key")
      expect(off).not_to be_on
      expect(off.reason).to eq("モデルの名前（ANLAGE_LLM_MODEL）がありません。")
      expect(off.reason).not_to include("sk-ant")
      expect(off.inspect).not_to include("sk-ant")
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

    it "anthropic と、鍵と、モデルの名前がそろうと、オン。外に文を送るアダプタ" do
      on = settings("ANLAGE_LLM" => "anthropic", "ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "ANLAGE_LLM_MODEL" => "claude-haiku-5-5")

      expect(on).to be_on
      expect(on).to be_external
      expect(on.adapter_name).to eq("anthropic")
      expect(on.inspect).not_to include("sk-ant")
    end
  end

  describe "openai（R-20261127-25）" do
    it "openai と、OpenAI の鍵と、モデルの名前がそろうと、オン。外に文を送るアダプタ" do
      on = settings("ANLAGE_LLM" => "openai", "OPENAI_API_KEY" => "sk-not-a-real-key", "ANLAGE_LLM_MODEL" => "the-model")

      expect(on).to be_on
      expect(on).to be_external
      expect(on.adapter_name).to eq("openai")
      expect(on.inspect).not_to include("sk-not-a-real-key")
    end

    it "鍵だけ、鍵とモデルの名前だけ（ANLAGE_LLM が無い）では、オフ" do
      expect(settings("OPENAI_API_KEY" => "sk-not-a-real-key")).not_to be_on
      expect(settings("OPENAI_API_KEY" => "sk-not-a-real-key", "ANLAGE_LLM_MODEL" => "the-model")).not_to be_on
    end

    it "openai で、鍵かモデルの名前が無いときはオフ。理由が付く" do
      expect(settings("ANLAGE_LLM" => "openai", "ANLAGE_LLM_MODEL" => "the-model").reason).to eq("API の鍵（OPENAI_API_KEY）がありません。")
      expect(settings("ANLAGE_LLM" => "openai", "OPENAI_API_KEY" => "sk-not-a-real-key").reason)
        .to eq("モデルの名前（ANLAGE_LLM_MODEL）がありません。")
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
