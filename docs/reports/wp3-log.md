# WP3（パスカード索引・検索層）進行ログ

explore→planフェーズの実測記録。R1〜。

---

## R1: Step 0（前提確認）・Step 1（explore、3エージェント並列実測）

### Step 0: 前提の再確認

1. **WP0 5節-1の留保**（`docs/design/pathcards-wp0-exploration.md:790-796`）: 「WP3のpgvector前提とAnlage現行DB構成（全環境SQLite3）の矛盾」について、2026-08-22人間回答は「**WP3計画提示時に移行範囲・手順・コストの材料付きで決める。WP1/WP2はSQLiteのまま進行**」。つまりこの判断は本タスク（WP3計画提示）で確定させることが要求されている、先送りではなく今回の締切事項。
2. **台帳10・11項の再確認**（`docs/upstream-candidates.md:292,323`）: 現存確認済み。10項＝`defining_code`/`code_string`経由のコード値WHEREが現行AQLエンジンで到達不能、11項＝`events/time`経由のイベント時刻WHEREが到達不能。**WP3の検索設計がAQLクエリを提示・生成する機能を持つ場合、これら2つの到達不能パスへ誘導しない**（回避形: `value/value`でのラベル一致、ELEMENT保持DV_DATE_TIMEでの代替）ことを設計原則として明示する必要がある。

`claude-code-prompt_semantic-pathcards.md`（絶対規律プロンプト）3節WP3も再読: 「pgvectorによる埋め込み索引＋構造メタデータ検索。外部ミドルウェアの新規追加は禁止（Rails＋PostgreSQL内で完結）」「埋め込み呼び出しはプロバイダ抽象層経由」「内部検索API＋最小の開発用UI」「索引はOPT投入時に自動更新」。DoD:「日本語クエリで関連カードが返る」。

### Step 1-1・1-2: パスカード実データの棚卸しと検索水準見積り（実測）

**重大な発見1: 開発DBの`templates.pathcards`は登録済み3テンプレート全件でNULL。**
`storage/development.sqlite3`を`sqlite3 -readonly`で直接実測: `bmi_calculation`/`ProblemList`/`CardiologyEncounter`いずれも`pathcards`列が空。原因を`log/development.log`（全10159行）で追跡した結果、該当3件のINSERTはいずれも`TemplatesController#create`のリクエストログを伴わず、`Opt::PathcardExtractor`呼び出し（`templates_controller.rb:72`のみが唯一の呼び出し箇所）を経由していないパターンと一致（`Rails.logger.warn`の警告文字列もログ中0件——抽出失敗ではなく、そもそも呼ばれていない）。**説明**: 本セッション中の各種調査・実装作業で`Template.build_from_opt_xml(...).tap(&:save!)`という直接model save（`spec/demo/support/*.rb`と同型のパターン）が`bin/rails runner`経由で繰り返し使われており、これがコントローラを経由しないためフックが発火しない。**WP2実装のバグではない**（golden spec 3ファイルは全てgreenであり、抽出器自体は正しく動作する。実測: 同一checksumのfixtureに対し直接`PathcardExtractor.call`した結果はgolden.json 3ファイルと完全一致）。デモ実演（実際のdropzone経由POST）では正しくカードが生成されることは、`spec/requests/templates_spec.rb`相当の既存request specの成立から裏付けられる。**運用上の含意**: WP3のリハーサル前に、デモ用OPT群を実際のドロップゾーン経由で（再）登録し、開発DBのpathcardsを実体化させる一手順が必要（コード修正ではなく運用手順）。

**カード実データの棚卸し**: 4テンプレート（bmi_calculation・ProblemList・CardiologyEncounter・LabResultReport）で合計**15枚**のカードが実在する（golden fixture 3件＋bmi_calculationのrunner実測で確認）。

**重大な発見2: `semantics.rm_type`は設計文書には定義されているが実装に存在しない。**
`docs/design/pathcards-schema-v1.md:24`は`semantics.rm_type: string`を定義するが、`app/lib/opt/pathcard_extractor.rb:115-118`（`semantics_for`）の戻り値は`labels`/`descriptions`のみで`rm_type`キーは一切出力されない（grep実測: 抽出器コード・golden JSON 3ファイルいずれにも0件）。「構造メタデータ検索」（RM型でのフィルタ等）を設計するなら、この欠落はWP3着手前提として扱う必要がある。

**重大な発見3: `lang`フィールドは「OPT宣言言語」であって「テキストの実言語」ではない。**
`bmi_calculation`はOPT宣言言語が`en`のため全カードの`labels[0].lang`は`"en"`になるが、実テキストは「身長」「体重」「判定」という正真正銘の日本語（`untranslated_suspect: false`）。**検索実装で`lang == "ja"`によるフィルタは誤り**。

**検索水準の実測（18クエリでの部分一致probe）**:
- 単純部分一致（LIKE相当）で素直にヒット: 8/18（「収縮期」「身長」「体重」「診断」「検査」「分析」「発症」「判定」）— 短い単語クエリなら実用水準
- クエリ-カード間の粒度ギャップで完全ミス: 3/18（「収縮期血圧」「拡張期血圧」「身長体重」）— 分かち書き/n-gram一致があれば救えるタイプ
- 真の同義語・訳語ギャップ（形態素解析でも救えない）: 3/18（「BMI」対「Body mass index」未翻訳、「体格指数」、「既往」対「プロブレム」）— embedding/同義語辞書が必要
- フィールド範囲の見落とし: 1/18（「疑い」は`semantics.labels/descriptions`には無いが`constraints.value.code_list[].label`に実在——**検索対象フィールドにcode_list labelも含める必要がある**、当初想定の5フィールドの外）
- descriptionsの翻訳完成度: 15枚中13枚（87%）が未翻訳英語原文のまま。**descriptionは日本語検索の主戦場になり得ない**（labelsが主戦場）

### Step 1-3: DB基盤とpgvector移行コスト（実測）

- 全環境SQLite3（`config/database.yml`全41行確認）。pg/pgvector系gemはGemfile/Gemfile.lockに痕跡ゼロ。WP0調査時点との差分なし
- Anlage自作コード側（マイグレーション9本・`db/schema.rb`のRuby DSL形式）にSQLite固有記法は不検出。AQL実行系（openehr-rails gem）にも`json_extract`/`strftime`等のSQLite固有SQL関数は不検出——**Anlage側の移行自体は局所的な改修で済む見込み**（`templates.pathcards`等のjson→jsonb変更、pgvector拡張の有効化、ベクタ列追加migrationのみ）
- 一方、**Docker（`Dockerfile:19`はsqlite3のみ、PostgreSQLクライアント未対応）とCI（`.github/workflows/ci.yml`はrspecステップ自体が無く、DBに一切依存しない）はゼロからの追加作業**が必要。CIが現状rspecを実行していないこと自体がDB選択と無関係な既存ギャップとして判明
- **本調査実行機ではPostgreSQL 16が既にインストール・稼働中**（pgvectorはapt一発で追加可能）。ただしこの機体が実際のデモ会場の機体と同一かは未確認——**デモ実行環境の実体（development環境かDocker本番相当か、壇上の機体はどれか）がドキュメント上どこにも明記されていない**
- 既存デモデータ投入はActiveRecordベース（`Template.build_from_opt_xml`＋`Opt::RmCompositionCommitter`）でraw SQL不使用のため、DB切替に伴う「データ移行」コストは実質ゼロ（空DBから作り直せば足りる）

### Step 1-4: LLM統合境界（実測）

- LLM/埋め込みAPI関連gem・設定は現状ゼロ（`Gemfile`/`Gemfile.lock`/`config/`全域でヒット0件）
- 会場ネットワーク依存リスクへの既存言及は無し（新規に論点として立てる必要がある）
- カード1枚あたりのテキスト量は数十字程度と小さい（`docs/design/pathcards-schema-v1.md`サンプルカード3枚実測）。デモ用少数OPT登録時のみバッチ埋め込み→本番は索引検索のみ、という設計は量的には実現性が高いと見込める（推測。ただしこれ自体がpgvector/PostgreSQL採用が前提）

### Step 1-5: UI最小形（実測）

- 再利用可能な既存資産: `app/views/templates/_template.html.erb`（カードパーシャル）、`templates_controller.rb#create`の`turbo_stream.append`パターン（登録成功時にリロード無しでカード追加——「クエリ→上位カード表示」の直接的先例）、`dropzone_controller.js`のfetch+Turbo Stream/Frameパターン。Hotwire一式（importmap/turbo/stimulus）導入済みで新規ビルドパイプライン不要
- 検索関連ルートは現状ゼロ（`config/routes.rb`全28行に該当無し）
- **重大な発見4**: WP2計画（`docs/design/wp2-plan.md:28`）は「抽出時レポート（未翻訳疑い一覧等）はログ出力、UI表出はWP3以降」としていたが、実装（`templates_controller.rb:73`）は`Opt::PathcardExtractor.call(template).cards`と**`.cards`のみ**を取り出しており、`.report`（`missing_labels`/`untranslated_suspects`/`multi_unit_nodes`）は成功パスで一切参照されず事実上破棄されている。WP3でreportをUI表出するには、reportの永続化・出力経路自体を新規に追加する必要がある

### Step 2への引き継ぎ

上記4つの重大な発見（pathcards全件NULL＝運用手順の問題／rm_type欠落／lang誤解の危険／reportの事実上破棄）と、検索水準の実測（単純部分一致で単語クエリは実用域、複合語はn-gram必要、真の同義語ギャップはembedding必須）を踏まえ、Phase 1（SQLite内で完結する最小検索）／Phase 2（pgvector/embedding、人間ゲート）の段階設計を`docs/design/wp3-plan.md`に起こす。
