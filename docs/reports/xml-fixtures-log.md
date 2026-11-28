# XML の fixture の整形式（R-20261128-13、`skoba/anlage#284`）

## R1（2026-11-28）注釈の `--` を直し、整形式を spec で見る

- 対象: 追跡している `*.opt` と `*.xml`（`git ls-files`）。いまは `spec/fixtures/opt/` の 6 つだけ（XML のアーキタイプは追跡していない）
- Red: `spec/docs/xml_fixtures_spec.rb`（Nokogiri の STRICT で読む）→ 2 examples, 1 failure

  ```
  整形式でない XML:
  spec/fixtures/opt/bmi_calculation.opt: 9:14: FATAL: Double hyphen within comment: <!--
  ```

- 直したのは、先頭の出どころの注釈の 1 行だけ: `structure) -- label language …` → `structure); label language …`（要素には触らない。裁定が名指しした例外）
- 直す前とあとで、読んだ木が同じ（Nokogiri の既定で読み、`//*` の要素の数と、根の要素を文字にしたものの SHA-256）:
  どちらも 1407 個、`aacac398…6920d9`。根の要素の文字は一致
- ファイルの sha256 は `d80e2ea6…c9baea` → `0685493a…bde7ce`、大きさは 80,616 → 80,614 バイト。sha256 を書いている `docs/demo/opt-catalog.md` を直した。
  注釈の中の sha256（`d72b6d50…`）は、写した元（openehr-rails の demo_assets）のファイルのものなので、そのまま。
  `docs/plans/opt-dropzone.md` の「80,158 bytes」も、写した元のファイルの大きさなので、そのまま
- Green: `spec/docs` 6 examples, 0 failures。OPT を読む `spec/models`・`spec/lib/opt` 240 examples, 0 failures
- CLAUDE.md の絶対規律 3（実物主義）の下に、1 行足した
