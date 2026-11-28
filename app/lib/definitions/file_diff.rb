module Definitions
  # 定義の組の 2 つの版の、ファイルごとの行の差分（skoba/anlage#296）。gem を足さない（1 ファイル 64 KiB まで。Definitions::Loader）。
  # 行の最長共通部分列で、残った行（" "）、消した行（"-"）、足した行（"+"）に分ける。変えていないファイルは返さない
  module FileDiff
    File = Data.define(:path, :status, :lines) # status: :added・:removed・:changed。lines: "+…"・"-…"・" …" の文字
    STATUS_LABELS = { added: "足した", removed: "消した", changed: "変えた" }.freeze

    module_function

    def call(before, after)
      (before.keys | after.keys).sort.filter_map do |path|
        old, new = before[path], after[path]
        next if old == new

        status = old.nil? ? :added : (new.nil? ? :removed : :changed)
        File.new(path:, status:, lines: lines(old.to_s.lines(chomp: true), new.to_s.lines(chomp: true)))
      end
    end

    def lines(old, new)
      table = Array.new(old.size + 1) { Array.new(new.size + 1, 0) }
      old.size.downto(1) do |i|
        new.size.downto(1) do |j|
          table[i - 1][j - 1] = old[i - 1] == new[j - 1] ? table[i][j] + 1 : [ table[i][j - 1], table[i - 1][j] ].max
        end
      end
      walk(old, new, table)
    end

    def walk(old, new, table)
      i = j = 0
      result = []
      while i < old.size && j < new.size
        if old[i] == new[j]
          result << " #{old[i]}"
          i += 1
          j += 1
        elsif table[i + 1][j] >= table[i][j + 1]
          result << "-#{old[i]}"
          i += 1
        else
          result << "+#{new[j]}"
          j += 1
        end
      end
      result + old[i..].map { "-#{_1}" } + new[j..].map { "+#{_1}" }
    end
  end
end
