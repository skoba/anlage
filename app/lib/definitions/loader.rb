module Definitions
  # 定義の YAML を安全に読む（docs/design/definition-layer-plan.md 9 節、skoba/anlage#257）。
  # 別名（alias）と任意のクラスを許さない（Date・Symbol も許さない。文字列・数・真偽・nil・配列・Hash だけ）。
  # 1 ファイル MAX_BYTES まで。読めないものは例外にせず、D1 の問題として返す
  module Loader
    MAX_BYTES = 64 * 1024
    Result = Data.define(:data, :problems)

    module_function

    def read(path, root:)
      parse(File.binread(path).force_encoding(Encoding::UTF_8), path: Pathname(path).relative_path_from(root).to_s)
    end

    def parse(text, path:)
      return failure(path, "ファイルが大きすぎる（上限は 64 KiB）") if text.bytesize > MAX_BYTES

      data = YAML.safe_load(text, permitted_classes: [], aliases: false)
      return failure(path, "最上位は対応表（キー: 値）でなければならない") unless data.is_a?(Hash)

      Result.new(data:, problems: [])
    rescue Psych::AliasesNotEnabled, Psych::BadAlias
      failure(path, "別名（& と *）は使えない")
    rescue Psych::DisallowedClass => e
      failure(path, "使えない型がある（#{e.message}）。文字列は引用符で囲む")
    rescue Psych::SyntaxError => e
      failure(path, "YAML の文法の誤り（#{e.problem}、#{e.line} 行目）")
    end

    def failure(path, message)
      Result.new(data: nil, problems: [ Problem.new(code: "D1", definition: path, message:) ])
    end
  end
end
