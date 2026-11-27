module NlQuery
  # 問い合わせの流れ（docs/design/s4-nl-aql-plan.md 1 節）:
  #   問い → 候補のカード → アダプタ（LLM）→ 選択の検査 → クエリビルダーが AQL を組む → リンタ →（実行）→ 説明
  #
  # うまくいかないときは、どれも例外にせず、候補のカードと理由だけを返す（画面はクエリビルダーに落ちる）。
  #   status: :ok／:blank（問いが空）／:off（LLM がオフ）／:limit（回数の上限）／:failed（アダプタが落ちた）／
  #           :unanswerable（LLM が答えられないと返した）／:rejected（選択の検査、クエリビルダー、リンタではねた）
  # 外に出るのは、Prompt が組んだ文だけ。実行の結果は LLM に渡さない。
  class Runner
    Result = Struct.new(:status, :candidates, :selection, :reason, :explanation, :run, :sha256, :model, keyword_init: true) do
      def ok? = status == :ok
    end

    def self.call(question:, settings: Llm::Settings.from_env, usage: Llm::Usage.default, corpus: QueryBuilder::Corpus.active,
                  execute: false)
      new(question, settings, usage, corpus, execute).call
    end

    def initialize(question, settings, usage, corpus, execute)
      @question = question.to_s.strip
      @settings = settings
      @usage = usage
      @corpus = corpus
      @execute = execute
    end

    def call
      return result(:blank, candidates: []) if @question.empty?

      candidates = Candidates.call(@question, corpus: @corpus)
      return result(:off, candidates: candidates, reason: @settings.reason) unless @settings.on?

      if @usage.exhausted?(@settings.daily_call_limit)
        return result(:limit, candidates: candidates,
                              reason: "きょうの呼び出しの回数が、上限（#{@settings.daily_call_limit} 回）に達しました。")
      end

      prompt = Prompt.new(question: @question, cards: candidates)
      response, failure = complete(prompt)
      return result(:failed, candidates: candidates, reason: failure, sha256: prompt.sha256) unless response

      interpret(response, prompt, candidates)
    end

    private

    # [応答, nil] か [nil, 落ちた理由]。成功も失敗も、1 回に数える。Llm::Error でない例外の文は、鍵などを含みうるので出さない
    def complete(prompt)
      response = @settings.adapter.complete(instructions: prompt.instructions, input: prompt.input, json_schema: prompt.json_schema)
      @usage.record(response)
      [ response, nil ]
    rescue Llm::Error => e
      @usage.record(nil)
      [ nil, e.message ]
    rescue StandardError => e
      @usage.record(nil)
      [ nil, "LLM の呼び出しに失敗しました（#{e.class.name}）。" ]
    end

    def interpret(response, prompt, candidates)
      common = { candidates: candidates, sha256: prompt.sha256, model: response.model }
      parsed = SelectionParser.parse(response.text, cards: candidates)
      return result(parsed.status, reason: parsed.reason, **common) unless parsed.ok?

      selection = parsed.selection
      run = QueryBuilder::Runner.call(columns: selection[:columns], conditions: selection[:conditions],
                                      template_id: selection[:template_id], across_versions: selection[:across_versions],
                                      order: selection[:order], execute: @execute, corpus: @corpus)
      return result(:rejected, reason: run.error, **common) if run.queries.empty?
      return result(:rejected, reason: run.lint.findings.select(&:error?).map(&:message).join("／"), **common) unless run.lint.ok?

      result(:ok, selection: selection, explanation: Explanation.build(selection), run: run, **common)
    end

    def result(status, **fields)
      Result.new(status: status, **fields)
    end
  end
end
