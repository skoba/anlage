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

**裁定済み・対応完了（2026-08-24、コミット`92ec864`）**: `.rubocop_todo.yml`は
**0件化**し削除済み。`bin/rubocop -f github`はexit=0。push後の実CI run `32689247483`
（全4ジョブ）greenを確認済み（`gh run view`で`conclusion: success`・`headSha`が
コミット`92ec864`と一致）。

対応内容:
- `Style/StringLiterals`2件（`config/routes.rb`・`config/initializers/openehr.rb`）は
  手動修正（シングル→ダブルクォート）。Anlage自身がauthorした設定ファイルであり
  除外の正当化理由が無いため
- `Layout/SpaceInsideArrayLiteralBrackets`12件は`.rubocop.yml`本体へ理由コメント付きの
  **恒久Exclude**として移した（`.rubocop_todo.yml`の段階的縮小対象ではない）。実測訂正:
  当初「Rails生成の既定書式がスペース無し」と記録したのは誤りで、実際は
  `rubocop-rails-omakase`の`EnforcedStyle`が**`space`**（スペース必須）。原因は
  gem`openehr-rails`のインストーラテンプレート原本
  （`lib/generators/openehr/install/templates/migrations/`）自体が`add_index`の配列引数を
  no_space書式（`[:a, :b]`）で書いていること（gem実測確認）。この2つのmigrationファイルは
  gemのテンプレートを素通しでコピーした生成物であり、Anlage側で手直ししてもgem再
  インストール時に上書きされ再発するため、恒久Excludeが正しい対応と判断した。


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

## 5. FHIR橋渡し層の恒久配置 — 方針確定（2026-08-26）

衛星gem`openehr-fhirbridge`として分離する。収容対象: FSHエミッタ・
StructureDefinition生成（現facadeの導出部）・将来のFHIRリソース
インスタンス変換。依存方向: `openehr`のみに依存（Rails非依存）。
スコープ原則: `openehr-ruby`はopenEHR仕様定義物のみ、他規格への写像は
橋gemに置く。

移行条件（いずれか）: Anlage外の第二消費者の出現／12月公開
パッケージング。前提作業: OPT平坦化（`FieldExtractor`相当）の
非Rails化（gem再編・第2巡以降）。

それまで実装はAnlage内で、純Rubyモジュール＋薄アダプタの構造条項
（`docs/design/fsh-plan.md`追記1）により移設可能性を保つ。

## 6. `skoba/mml` — 将来のコーパス拡張候補（出所記録、2026-08-26人間報告）

- `skoba/mml`（`openEHR/`配下）は522 ADL・31テンプレート（`.oet`/`.opt`対）
  の資産庫であり、`mml_referral`（`docs/design/fsh-plan.md`のv1規模上限
  判断で参照した大規模テンプレート）の全依存アーキタイプソースが同リポ内
  に実在する。将来コーパス拡張（現有7archetype・15カードからの多様化）の
  canonical元候補として記録する。Claude Codeは当該リポジトリ未探索
  （working directory外）——本項は人間報告として記録し、実際の取り込み
  判断時にAnlage側で改めて実測確認する。
- 前提値（取得時実測、人間報告）: ja翻訳含有ADLは38/522。将来この
  コーパスを取り込む際、パスカード抽出の未翻訳定量（例:
  `docs/design/wp3-plan.md`「descriptionsは15枚中13枚(87%)が未翻訳英語」
  のような実測値）と本前提値を突き合わせ、母集団側の翻訳率との整合を
  確認する用途に使う。

## 7. OPT生成ツールチェーンの受け入れポリシー — 確定版（2026-08-26裁定）

OPT生成ツールチェーンは5系統が並立する（人間報告）: Ocean Template
Designer／ADL Workbench／LinkEHR／HMC／Better Archetype Designer。
受け入れポリシー:

- **保証対象（first-class）**: Better Archetype Designer系——現在の
  主流。新規・改訂OPTの標準ツールもこれ
- **受け入れ実績（検証済み）**: Better AD系＋Ocean TD系。現役fixture:
  `ProblemList.opt`／`LabResultReport.opt`／`CardiologyEncounter.opt`
  ＝AD系、`bmi_calculation.opt`／`patient_blood_pressure.opt`／
  `mml_referral`（予定）＝Ocean系
- **他3系統（ADL Workbench／LinkEHR／HMC）**: 未検証・best-effort。
  実物到来時に受け入れ検証する。bug報告のEnvironment欄で生成器系統を
  申告してもらう運用とする

12月世界公開準備時はこの三層（保証対象／検証済み／best-effort）を
明示する。未翻訳定量の解釈枠（`docs/design/pathcards-language-policy.md`
5節）が指すツールチェーン世代差はこの5系統・三層構造の具体例として
接続する。
