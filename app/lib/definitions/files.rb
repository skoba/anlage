module Definitions
  # 定義の組を「path → 文字」の対応表で持つ（docs/design/definition-registration-plan.md 1 節、skoba/anlage#277）。
  # 表（DefinitionBundle#files）とディレクトリの、どちらの組も、Definitions::Linter.check で同じように検査する。
  # 読むのは目録と、screens・logic の YAML だけ（ほかのファイルは組に入れない）
  module Files
    PATTERNS = [ Linter::BUNDLE, "screens/*.yml", "logic/*.yml" ].freeze

    module_function

    def read(dir)
      root = Pathname(dir)
      # path の順に並べる（DefinitionBundle の checksum が、読む順によらない）
      PATTERNS.flat_map { Dir.glob(_1, base: root) }.sort
              .select { root.join(_1).file? }
              .to_h { [ _1, File.binread(root.join(_1)).force_encoding(Encoding::UTF_8) ] }
    end
  end
end
