require "digest"

# LLM を呼ぶ汎用の部品（docs/design/s4-nl-aql-plan.md 3.1 節。R-20261127-14）。文を送って、文を受け取るだけ。
# カードも、問い合わせの選択も知らない。問い合わせの側（NlQuery）は、この上に乗る。
#
# アダプタの口:
#   #complete(instructions:, input:, json_schema: nil) → Llm::Response。落ちるときは Llm::Error
#     json_schema は、出力の形（JSON スキーマ）。省ける。出力の形を縛れるアダプタだけが使う（いまは local）
#   #name（設定と記録に使う名前）、#external?（外に文を送るか）
module Llm
  # 通信の失敗、時間切れ、断り、記録が無い、など。message は画面とログに出るので、鍵や応答の中身を入れない
  class Error < StandardError; end

  Response = Struct.new(:text, :model, :input_tokens, :output_tokens, keyword_init: true)

  # 送る文（指示文と入力）の指紋。記録した応答の鍵と、測定の記録に使う
  def self.fingerprint(instructions:, input:)
    Digest::SHA256.hexdigest("#{instructions}\n#{input}")
  end
end
