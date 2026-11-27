require "rails_helper"

# クエリビルダーの「文で問う」（docs/design/s4-nl-aql-plan.md 7 節の段 3。R-20261127-14）を、実ブラウザの操作列で通す。
# 問いを文で入れる → LLM が作った選択が「表示する項目」「条件」に入る → 説明を読む → 直せる → 実行して行を見る。
# LLM の応答は、記録した応答で固定する。ここの応答は、セッションが手で書いたもの（モデルの応答ではない）。外は呼ばない。
# データは demo_initial（rake demo:reset の初期状態）。期待する行は、評価 v2 の a002 と同じ。文言は docs/demo/ui-vocabulary.md の写し。
RSpec.describe "クエリビルダーの「文で問う」（実ブラウザ）", type: :system, js: true do
  let(:question) { "診断確度が「疑い」の傷病名" }
  let(:recordings) { Pathname(Dir.mktmpdir) }
  let(:usage_dir) { Pathname(Dir.mktmpdir) }
  let(:env) { { "ANLAGE_LLM" => "recorded", "ANLAGE_LLM_RECORDINGS" => recordings.to_s } }

  before do
    Evaluation::Datasets.build("demo_initial")
    allow(Llm::Settings).to receive(:from_env).and_wrap_original { |original| original.call(env) }
    allow(Llm::Usage).to receive(:default).and_return(Llm::Usage.new(path: usage_dir.join("llm_usage.json")))
  end

  after do
    FileUtils.remove_entry(recordings)
    FileUtils.remove_entry(usage_dir)
  end

  def record(response_body)
    candidates = NlQuery::Candidates.call(question)
    number = lambda do |label|
      candidates.index { |card| card.dig("identity", "template_id") == "ProblemList" && card.dig("semantics", "labels", 0, "text") == label } + 1
    end
    prompt = NlQuery::Prompt.new(question: question, cards: candidates)
    text = response_body.respond_to?(:call) ? JSON.generate(response_body.call(number)) : response_body
    recordings.join("#{prompt.sha256}.json").write(JSON.generate(
      sha256: prompt.sha256, input: prompt.input, response: text, model: "hand-written", input_tokens: 900, output_tokens: 40, source: "hand_written"
    ))
  end

  it "問いを文で入れると、選択が入り、説明が出る。条件を直して実行できる" do
    record(lambda { |number|
      { columns: [ number.call("プロブレム・診断名") ],
        conditions: [ { card: number.call("診断確度"), operator: "MATCHES", value: [ "疑い" ] } ] }
    })

    visit new_query_path
    expect(page).to have_css("#nl_query p", text: "文で問う（LLM）は、オンです（recorded）。")
    expect(page).to have_css("#nl_query p", text: "きょうの呼び出し: 0／100 回")
    expect(page).not_to have_text("外の API に送られます")

    fill_in "問い", with: question
    click_button "選択を作る"

    expect(page).to have_css("#nl_explanation p", text: "問い: #{question}")
    expect(page).to have_css("#nl_explanation p", text: "「プロブレム・診断」の「プロブレム・診断名」を表示します。条件: 「診断確度」が 疑い（at0074）。")
    expect(page).to have_css("#query_columns li .card-label", text: "プロブレム・診断名（ProblemList）")
    within("#query_conditions li") do
      expect(page).to have_checked_field("疑い")
      expect(page).to have_unchecked_field("確定")
    end
    expect(page).to have_css("#query_aql pre", text: 'value/defining_code/code_string MATCHES {"at0074"}')
    expect(page).to have_css("#nl_query p", text: "きょうの呼び出し: 1／100 回")
    expect(page).not_to have_css("#query_result")

    click_button "実行"
    expect(page).to have_css("#query_result p", text: "7 行")
    expect(all("#query_result tbody td").map(&:text)).to match_array(%w[高血圧症 起立性低血圧 狭心症 狭心症 白血病 悪性リンパ腫 多発性骨髄腫])

    # 利用者が条件を直すと、説明も、いまの選択に合わせて変わる
    within("#query_conditions li") { check "推定" }
    click_button "実行"
    expect(page).to have_css("#nl_explanation p", text: "「診断確度」が 疑い（at0074）、推定（at0075）のいずれか")
    expect(page).to have_css("#query_result p", text: "8 行")
    expect(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")).to be(false)
  end

  it "選択を作れなかったときは、理由が出て、候補のカードから手で選んで続けられる" do
    record("プロブレム・診断名を表示します。")

    visit new_query_path
    fill_in "問い", with: question
    click_button "選択を作る"

    expect(page).to have_css("#nl_reason", text: "選択を作れませんでした: JSON として読めない応答。下で、手で選んでください。")
    find("#query_candidates .pathcard", text: "ProblemList", match: :first) { |card| card.has_css?("h2", text: "プロブレム・診断名", exact_text: true) }
      .click_button "表示する項目に足す"

    expect(page).to have_css("#query_columns li .card-label", text: "プロブレム・診断名（ProblemList）")
    expect(page).not_to have_css("#nl_explanation")
  end

  context "オフのとき（既定）" do
    let(:env) { {} }

    it "オフであることと案内が出て、クエリビルダーは、これまでどおり使える" do
      visit new_query_path

      expect(page).to have_css("#nl_query p", text: "文で問う（LLM）は、オフです。")
      expect(page).not_to have_button("選択を作る")

      fill_in "探したい項目", with: "収縮期"
      click_button "検索"
      expect(page).to have_css("#query_candidates .pathcard h2", text: "収縮期")
    end
  end
end
