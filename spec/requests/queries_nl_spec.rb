require "rails_helper"

# クエリビルダーの「文で問う」（docs/design/s4-nl-aql-plan.md 7 節の段 3・10.2 節。R-20261127-14）。
# LLM のオンとオフは、運用する人の設定（環境変数）。既定はオフで、オフのとき、クエリビルダーはこれまでどおり動く。
# LLM の応答は、記録した応答で固定する。ここの応答は、セッションが手で書いたもの（モデルの応答ではない）。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し。データは demo_initial（rake demo:reset の初期状態）。
RSpec.describe "クエリビルダーの「文で問う」", type: :request do
  NL_QUESTION = "診断確度が「疑い」の傷病名".freeze

  let(:recordings) { Pathname(Dir.mktmpdir) }
  let(:usage_dir) { Pathname(Dir.mktmpdir) }
  let(:usage) { Llm::Usage.new(path: usage_dir.join("llm_usage.json")) }
  let(:env) { { "ANLAGE_LLM" => "recorded", "ANLAGE_LLM_RECORDINGS" => recordings.to_s } }
  let(:corpus) { QueryBuilder::Corpus.active }
  let(:candidates) { NlQuery::Candidates.call(NL_QUESTION, corpus: corpus) }

  before do
    Evaluation::Datasets.build("demo_initial")
    allow(Llm::Settings).to receive(:from_env).and_wrap_original { |original| original.call(env) }
    allow(Llm::Usage).to receive(:default).and_return(usage)
  end

  after do
    FileUtils.remove_entry(recordings)
    FileUtils.remove_entry(usage_dir)
  end

  def doc = Nokogiri::HTML(response.body)
  def texts(selector) = doc.css(selector).map { _1.text.strip.squish }

  def number(template_id, label)
    candidates.index { |card| card.dig("identity", "template_id") == template_id && card.dig("semantics", "labels", 0, "text") == label } + 1
  end

  def record(response_body)
    prompt = NlQuery::Prompt.new(question: NL_QUESTION, cards: candidates)
    text = response_body.is_a?(String) ? response_body : JSON.generate(response_body)
    recordings.join("#{prompt.sha256}.json").write(JSON.generate(
      sha256: prompt.sha256, input: prompt.input, response: text, model: "hand-written", input_tokens: 900, output_tokens: 40, source: "hand_written"
    ))
  end

  let(:a002_response) do
    { columns: [ number("ProblemList", "プロブレム・診断名") ],
      conditions: [ { card: number("ProblemList", "診断確度"), operator: "MATCHES", value: [ "疑い" ] } ] }
  end

  context "オフのとき（既定）" do
    let(:env) { {} }

    it "オフであることと、オンにする方法への案内が出る。文で問う欄は出ない。クエリビルダーは、これまでどおり" do
      get "/queries/new"

      expect(response).to have_http_status(:ok)
      expect(texts("#nl_query h2")).to eq([ "文で問う" ])
      expect(texts("#nl_query p")).to eq([
        "文で問う（LLM）は、オフです。オンにする方法は docs/nl-query.md にあります（環境変数 ANLAGE_LLM を設定して、起動し直します）。"
      ])
      expect(doc.at_css("#nl_query form")).to be_nil
      expect(doc.at_css("label[for=q]").text.strip).to eq("探したい項目")
    end

    it "鍵だけがあっても、オフのまま" do
      env["ANTHROPIC_API_KEY"] = "sk-ant-not-a-real-key"

      get "/queries/new"
      expect(texts("#nl_query p").first).to start_with("文で問う（LLM）は、オフです。")
      expect(response.body).not_to include("sk-ant")
    end

    it "オンの設定があっても使えないときは、オフで、理由が出る。鍵の値は出ない" do
      env.merge!("ANLAGE_LLM" => "anthropic", "ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key")

      get "/queries/new"
      expect(texts("#nl_query p")).to include("モデルの名前（ANLAGE_LLM_MODEL）がありません。")
      expect(doc.at_css("#nl_query form")).to be_nil
      expect(response.body).not_to include("sk-ant")
    end

    it "文で問う口に直接送っても、LLM は呼ばれず、理由が出る" do
      post "/queries/ask", params: { nl: NL_QUESTION }

      expect(response).to have_http_status(422)
      expect(texts("#nl_reason")).to eq([ "選択を作れませんでした: 文で問う（LLM）は、オフです。下で、手で選んでください。" ])
      expect(usage.today[:calls]).to eq(0)
    end
  end

  context "オンのとき（記録した応答のアダプタ）" do
    it "文で問う欄と、オンであること、きょう使った回数と上限、トークンの数が出る。手で選ぶ欄も同じ画面にある" do
      usage.record(Llm::Response.new(text: "{}", model: "m", input_tokens: 2700, output_tokens: 120))

      get "/queries/new"

      expect(doc.at_css("#nl_query form")["action"]).to eq("/queries/ask")
      expect(doc.at_css("#nl_query form")["method"]).to eq("post")
      expect(doc.at_css("#nl_query label[for=nl]").text.strip).to eq("問い")
      expect(doc.at_css("#nl_query input[type=submit]")["value"]).to eq("選択を作る")
      expect(texts("#nl_query p")).to eq([
        "文で問う（LLM）は、オンです（recorded）。",
        "きょうの呼び出し: 1／100 回（入力 2700・出力 120 トークン）"
      ])
      expect(doc.at_css("label[for=q]").text.strip).to eq("探したい項目")
    end

    it "外に送らないアダプタのときは、「外に送られます」の注意を出さない" do
      get "/queries/new"

      expect(response.body).not_to include("外の API に送られます")
    end

    it "問いを入れると、表示する項目と条件が入った状態（URL）に移る。実行はまだ" do
      record(a002_response)

      post "/queries/ask", params: { nl: NL_QUESTION }

      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(request.path).to eq("/queries/new")
      expect(request.query_parameters["nl"]).to eq(NL_QUESTION)
      expect(texts("#query_columns li .card-label")).to eq([ "プロブレム・診断名（ProblemList）" ])
      expect(texts("#query_conditions li .card-label")).to eq([ "診断確度（ProblemList）" ])
      expect(doc.at_css("#query_conditions input[type=checkbox][value=at0074]")["checked"]).to be_present
      expect(doc.at_css("#query_conditions input[type=checkbox][value=at0076]")["checked"]).to be_nil
      expect(texts("#query_aql pre").first).to include('/items[at0073]/value/defining_code/code_string MATCHES {"at0074"}')
      expect(doc.at_css("#query_result")).to be_nil
      expect(usage.today[:calls]).to eq(1)
    end

    it "移った先に、問いと説明が出る。説明は、選択とカードの文言から組んだもの" do
      record(a002_response)
      post "/queries/ask", params: { nl: NL_QUESTION }
      follow_redirect!

      expect(texts("#nl_explanation h2")).to eq([ "説明" ])
      expect(texts("#nl_explanation p")).to eq([
        "問い: #{NL_QUESTION}",
        "「プロブレム・診断」の「プロブレム・診断名」を表示します。条件: 「診断確度」が 疑い（at0074）。" \
        "アーキタイプ: openEHR-EHR-EVALUATION.problem_diagnosis.v1。テンプレート: ProblemList。",
        "この選択は、文で問う（LLM）から始めました。表示する項目と条件を確かめてから、実行してください。"
      ])
      expect(doc.at_css("#nl_query input[name=nl]")["value"]).to eq(NL_QUESTION)
      expect(doc.at_css("#query_builder input[type=hidden][name=nl]")["value"]).to eq(NL_QUESTION)
    end

    it "移った先で実行すると、a002 の期待行が出る。LLM は、もう呼ばれない" do
      record(a002_response)
      post "/queries/ask", params: { nl: NL_QUESTION }
      follow_redirect!

      get "/queries/new", params: request.query_parameters.merge(run: "実行")

      expect(texts("#query_result p")).to eq([ "7 行" ])
      expect(texts("#query_result tbody td")).to match_array(%w[高血圧症 起立性低血圧 狭心症 狭心症 白血病 悪性リンパ腫 多発性骨髄腫])
      expect(usage.today[:calls]).to eq(1)
    end

    it "選択を作れなかったとき（読めない応答）は、理由が出て、候補のカードから手で選べる" do
      record("プロブレム・診断名を表示します。")

      post "/queries/ask", params: { nl: NL_QUESTION }

      # 422 で返す（Turbo は、フォームの POST への 200 の HTML を画面に出さない。実ブラウザの spec で分かった）
      expect(response).to have_http_status(422)
      expect(texts("#nl_reason")).to eq([ "選択を作れませんでした: JSON として読めない応答。下で、手で選んでください。" ])
      expect(doc.css("#query_candidates .pathcard").size).to eq(candidates.size)
      expect(doc.at_css("#query_candidates button[name=add_column]")).to be_present
      expect(doc.at_css("#nl_query input[name=nl]")["value"]).to eq(NL_QUESTION)
    end

    it "選択を作れなかったあと、手で選んだ選択には、「文で問うから始めました」の説明を付けない" do
      record("プロブレム・診断名を表示します。")
      post "/queries/ask", params: { nl: NL_QUESTION }

      expect(doc.at_css("#query_builder input[type=hidden][name=nl]")).to be_nil
      expect(doc.at_css("#nl_explanation")).to be_nil
    end

    it "回数の上限に達しているときは、LLM を呼ばず、理由が出る" do
      record(a002_response)
      env["ANLAGE_LLM_DAILY_CALL_LIMIT"] = "1"
      post "/queries/ask", params: { nl: NL_QUESTION }

      post "/queries/ask", params: { nl: NL_QUESTION }

      expect(texts("#nl_reason")).to eq([ "選択を作れませんでした: きょうの呼び出しの回数が、上限（1 回）に達しました。下で、手で選んでください。" ])
      expect(usage.today[:calls]).to eq(1)
    end

    it "LLM が返した理由（答えられない）は、文字として出す（HTML として解釈しない）" do
      record({ columns: [], conditions: [], reason: "<b>体重</b>がありません。" })

      post "/queries/ask", params: { nl: NL_QUESTION }

      expect(texts("#nl_reason")).to eq([ "選択を作れませんでした: <b>体重</b>がありません。下で、手で選んでください。" ])
      expect(doc.at_css("#nl_reason b")).to be_nil
    end

    it "問いが空のときは、LLM を呼ばない" do
      post "/queries/ask", params: { nl: " " }

      expect(texts("#nl_reason")).to eq([ "選択を作れませんでした: 問いが空です。下で、手で選んでください。" ])
      expect(usage.today[:calls]).to eq(0)
    end
  end

  context "オンのとき（外に文を送るアダプタ）" do
    it "問いの文が外に送られること、患者の情報を書かないこと、費用がかかることが出る" do
      external = Class.new do
        def name = "external-for-spec"
        def external? = true
      end.new
      allow(Llm::Settings).to receive(:from_env).and_return(Llm::Settings.new(adapter: external, adapter_name: "external-for-spec"))

      get "/queries/new"

      expect(texts("#nl_query p")).to include(
        "問いの文は、外の API に送られます。患者の情報を書かないでください。呼び出すたびに、費用がかかります。"
      )
    end
  end
end
