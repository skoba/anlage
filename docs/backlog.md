# Backlog（低優先度・要別途承認の項目）

WP0-5やSliceの実装計画には載らないが、確認済みで記録しておくべき
低優先度項目。ここに載っている項目は**このファイルへの追記自体が
対応の完了**であり、実装対応は別途承認を得てから着手する。

## CI status (verified, 2026-08-24)

`.github/workflows/ci.yml`（`scan_ruby`・`scan_js`・`lint`・`test`の4ジョブ）は、
`skoba/anlage#15`/`#16`のCI修復（`docs/reports/ci-fix-log.md`）により、
コミット`92932b6`のpush runで**全ジョブgreenであることを実際に確認済み**
（`gh run view 32687777074` → `conclusion: success`、`headSha`が当該コミットと一致）。
それ以前は`lint`ジョブが直近5件のpush runすべてで`failure`だった実測記録が
`docs/reports/ci-fix-log.md` R1にある。

- `test`ジョブ（`bin/rails db:test:prepare` + `bundle exec rspec`全suite）は
  system spec（Capybara、`rack_test`/`selenium_chrome_headless`両ドライバ）を
  含めて特別な設定無しで一発green化した（run 32687777074、`test`ジョブ32秒）。
  開発機のsandbox環境で観測されていた`Errno::EPERM`（ローカルsocket作成拒否）は
  この開発機固有の制約であり、GitHub Actions runnerには再現しなかった。
- `lint`ジョブは`.rubocop_todo.yml`で既存14件をベースライン化してgreen化した。

**`.rubocop_todo.yml`の運用方針**: `openehr-ruby`のrubocop-rspec todoファイル運用
（1cop単位で段階的に縮小、一括修正はしない）に倣う。ベースライン化した14件
（`Layout/SpaceInsideArrayLiteralBrackets`×12・`Style/StringLiterals`×2）の
実際の解消は、本項目とは別に着手時期を判断する。

**構造的要因（未解決、要判断）**: `Layout/SpaceInsideArrayLiteralBrackets`の12件中
大半は`db/migrate/`配下のマイグレーションファイルに集中している。本セッション中の
複数の過去作業で、`bin/rails db:migrate`実行のたびに`db/schema.rb`の配列表記が
`[ "x" ]`（スペース入り）⇔`["x"]`（スペース無し）で無害に書式変動することを
繰り返し観測してきた——これは、このRails環境が生成する既定の配列書式が
`rubocop-rails-omakase`既定の`Layout/SpaceInsideArrayLiteralBrackets`有効設定
（スペース無し必須）と食い違っていることを示唆する。`.rubocop.yml`自体に
「このcopを無効化する」設定例がコメントとして既に用意されている。この食い違いは
今後もマイグレーション・スキーマ再生成のたびに再発しうる。対応方針（(a) 今回の
12件を手動修正して以後は書式を統一する (b) copを無効化しRails生成コードの実態に
合わせる (c) 現状のtodoベースラインのまま据え置く）は未判断——別途裁定が必要。

## 1. `Opt::SafeParser` の DOCTYPE 検知が UTF-16 入力で素通りする

- 発見日: 2026-08-22（読み取り検査のみ、実装変更なし）
- 対象: `app/lib/opt/safe_parser.rb`
- 内容: `DOCTYPE_PATTERN = /<!DOCTYPE/i` によるDOCTYPE事前拒否
  （`docs/plans/opt-dropzone.md` §2.7 as-built 参照）は、アップロード
  バイト列を `.b`（ASCII-8BIT化）してから正規表現マッチする。これは
  UTF-8/ASCII/Shift_JIS等、`<!DOCTYPE` がASCII互換のバイト列として
  連続するエンコーディングでは確実に検知できるが、**UTF-16などASCII
  文字がヌルバイトを挟んで並ぶエンコーディングでは、バイト列が
  連続しないため正規表現に一致せず素通りする**。
- 実測（`bundle exec rails runner` で実際の `Opt::SafeParser.parse`
  にUTF-16LEエンコードのXXEペイロードを通した結果、tmpスクリプトの
  実行のみ・コミットなし）:
  - ASCII/UTF-8のXXEペイロード → `Opt::UnsafeTemplate` で正しく拒否
  - 同内容をUTF-16LEでエンコードしたペイロード →
    DOCTYPE検知をすり抜けて `OpenehrRails::Opt.parse`
    まで到達（今回のPoCペイロードは完全なOPT/archetype XMLではないため
    その先で`ArgumentError: invalid archetype id form`になったが、
    これはOPT構造として不正なための失敗であり、DOCTYPE検知の突破とは
    無関係。実際に有効なarchetype構造を持つUTF-16 OPTであれば、
    DOCTYPE宣言はチェックされずにNokogiriまで到達する）。
  - 補足: `templates_controller.rb:148/:170` の
    `force_encoding(Encoding::UTF_8)` はラベル貼り替えのみで実バイト列を
    変換しないため、この経路のどこにもエンコーディング正規化
    （宣言されたencodingを読んでUTF-8へ実変換する等）は存在しない。
- **緊急度: 低**。nokogiri 1.19.4 の `ParseOptions::DEFAULT_XML`
  （`RECOVER | NONET | BIG_LINES`）で **`NONET` が既定でON**・
  **`NOENT` が既定でOFF**（`docs/plans/opt-dropzone.md` §2.7参照）
  であるため、DOCTYPE検知をすり抜けたペイロードがNokogiriまで
  到達しても、外部ネットワーク参照やエンティティ実体展開自体は
  下段の既定動作でブロックされる。二層防御の一段目に穴があるが、
  二段目（gem側の既定）は生きている状態。
- **対応方針（本タスクでは実施しない）**: 修正案の候補は
  (a) DOCTYPE正規表現をかける前に宣言されたencodingを読んでUTF-8へ
  実変換する、(b) バイト列レベルで `<`/`!`/`D`/`O`/`C`/`T`/`Y`/`P`/`E`
  の各バイトの間にヌルバイトを許容する形へ正規表現を緩める、
  (c) Nokogiri側にも明示的な `NONET`/`NOENT` を渡し二段目を保証させる
  （`docs/upstream/issues/openehr-ruby--xxe-safe-default-parse-options.md`
  参照）などが考えられるが、**いずれも実装は別途承認を得てから**。

## 2. 診療情報提供書 OPT 入手時の受け入れスモーク

- **Issue化済み**: [skoba/anlage#4](https://github.com/skoba/anlage/issues/4)

- ドロップゾーン通過・埋め込みCLUSTERラベル・FHIR facade出力を確認し
  `docs/evidence/` に証跡追加（デモ本番アーティファクトの新スタック
  初通過の記録）。
- 要件チェックリストの保存先はIssue本体（[skoba/anlage#4](https://github.com/skoba/anlage/issues/4)）とする。相互参照のみ本行に残す。

## 3. bmi_calculation.optのja化（任意・低優先）

- `spec/fixtures/opt/bmi_calculation.opt`（`skoba/anlage#5`用、lang=en）を
  日本語ラベル付きへ差し替える価値があるかは未確定。AQLのpath照会用途では
  言語は本質的でないため、現時点では見送る。パスカードのラベル取得実演で
  height系archetypeが必要になった場合に再検討する。

## 4. rails demo README整備（12月・冬眠中）

- openehr-rails側の`demo_assets/`に対応するREADME/MANIFEST整備は、
  Anlageの管轄外（層規律）。12月世界公開準備のタイミングまで保留（現在
  「冬眠中」＝アクティブな作業対象ではない）。
