require "json"
require "fileutils"

module Evaluation
  module Grounding
    # 測定を回す: 問い × 腕 × くり返し（docs/design/s4-nl-aql-plan.md 5 節・7 節の段 6。R-20261127-32）。
    # 試行ごとに <dir>/trials/<問い>.<腕>.<回>.json を残す。済んだ試行は呼ばずに飛ばすので、途中で止めても、続きから回せる。
    # <dir>/run.json に、測定の記録（アダプタ、腕、回数、問いのファイルの sha256、commit、gem の版）を残す。鍵は持たない。
    # 選択を出す腕だけで数える問い（もとから版をまたぐ a014 の文）は、AQL を書かせる腕では回さない。
    class Run
      ARMS = %i[n0 n1 g_aql g_selection].freeze

      def self.call(queries:, arms:, adapter:, repeats:, dir:, corpus: QueryBuilder::Corpus.active, note: nil, progress: nil)
        new(queries, arms, adapter, repeats, dir, corpus, note, progress).call
      end

      def initialize(queries, arms, adapter, repeats, dir, corpus, note, progress)
        @queries = queries
        @arms = arms.map(&:to_sym)
        raise ArgumentError, "腕は #{ARMS.join('／')}" unless (@arms - ARMS).empty?

        @adapter = adapter
        @repeats = repeats
        @dir = Pathname(dir)
        @corpus = corpus
        @note = note
        @progress = progress
      end

      def call
        @dir.join("trials").mkpath
        write_meta
        @queries.each do |query|
          @arms.each do |arm|
            next if query.selection_only? && arm != :g_selection

            (1..@repeats).each { |repeat| trial(query, arm, repeat) }
          end
        end
        @dir
      end

      private

      def trial(query, arm, repeat)
        path = @dir.join("trials", "#{query.id}.#{arm}.#{repeat}.json")
        return if path.file?

        prompt = prompt_for(query, arm)
        schema = arm == :g_selection ? prompt.json_schema : nil
        record = { query: query.id, arm: arm, repeat: repeat, instructions_sha256: Digest::SHA256.hexdigest(prompt.instructions),
                   sha256: prompt.sha256, input: prompt.input }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          response = @adapter.complete(instructions: prompt.instructions, input: prompt.input, json_schema: schema)
          seconds = elapsed(started)
          result = Scorer.score(query, arm: arm, response: response.text, corpus: @corpus)
          record.merge!(response: response.text, model: response.model, input_tokens: response.input_tokens, output_tokens: response.output_tokens,
                        seconds: seconds, **result.to_h.except(:rows), rows: result.rows)
        rescue Llm::Error => e
          record.merge!(status: :failed, reason: e.message, seconds: elapsed(started), order_free: false, parseable: false, lint_ok: false, executed: false)
        end
        path.write(JSON.pretty_generate(record))
        @progress&.call(record)
      end

      def prompt_for(query, arm)
        return NlQuery::Prompt.new(question: query.nl_query, cards: NlQuery::Candidates.call(query.nl_query, corpus: @corpus)) if arm == :g_selection

        AqlPrompt.new(arm: arm, question: query.nl_query, corpus: @corpus)
      end

      def elapsed(started) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)

      def write_meta
        path = @dir.join("run.json")
        meta = path.file? ? JSON.parse(path.read) : fresh_meta
        meta["resumed_at"] = Array(meta["resumed_at"]) + [ Time.current.iso8601 ] if path.file?
        path.write(JSON.pretty_generate(meta))
      end

      def fresh_meta
        { "adapter" => @adapter.name, "external" => @adapter.external?, "model" => (@adapter.model if @adapter.respond_to?(:model)),
          "arms" => @arms.map(&:to_s), "repeats" => @repeats, "queries" => @queries.map(&:id),
          "queries_sha256" => Queries.sha256, "cards" => @corpus.cards.size,
          # 出力の形（JSON スキーマ）を渡したか。腕ごと。渡しても、縛るかどうかはアダプタによる（いま縛るのは local と lmstudio）
          "json_schema" => @arms.to_h { |arm| [ arm.to_s, arm == :g_selection ] },
          "dialect_sha256" => Digest::SHA256.hexdigest(AqlPrompt::DIALECT), "selection_instructions_sha256" => Digest::SHA256.hexdigest(NlQuery::Prompt::INSTRUCTIONS),
          "commit" => `git -C #{Rails.root} rev-parse HEAD`.strip,
          "gems" => %w[openehr openehr-rails anthropic].to_h { |name| [ name, Gem.loaded_specs[name]&.version&.to_s ] }.compact,
          "started_at" => Time.current.iso8601, "note" => @note }.compact
      end
    end
  end
end
