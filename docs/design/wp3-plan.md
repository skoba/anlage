# WP3 実装計画: パスカード索引・検索層

**作成日**: 2026-08-23
**対象Issue**: `skoba/anlage#12`（goal）
**位置づけ**: `claude-code-prompt_semantic-pathcards.md` 3節WP3。WP2（パスカード抽出器、`skoba/anlage#8`、完了済み）の成果物`templates.pathcards`を検索可能にする。
**ログ**: `docs/reports/wp3-log.md`（R1〜。本計画のexplore実測記録）

> **本文書はexplore→planのみの成果物**。WP3自体の実装（コード変更）は
> 本タスクでは行わない。承認後、別タスクとして着手する。

## Step 1 explore実測結果（要約。詳細は`docs/reports/wp3-log.md` R1）

### 前提の確認（Step 0）

1. WP0 5節-1（`docs/design/pathcards-wp0-exploration.md:790-796`）: PostgreSQL/pgvector移行方針は「WP3計画提示時に材料付きで決める」という留保。**本計画がその決定機会**。
2. 台帳10・11項（`docs/upstream-candidates.md:292,323`）: AQLエンジンの到達不能パス（コード値WHERE・イベント時刻WHERE）は現存。WP3の検索設計がAQLクエリ生成・提示機能を持つ場合、これらへ誘導しないことを設計原則とする。

### 4つの重大な発見

1. **開発DBの`templates.pathcards`は登録済み3テンプレート全件でNULL**。原因は本セッション中の調査作業が`Template.build_from_opt_xml(...).tap(&:save!)`という直接model saveを多用し、`TemplatesController#create`（`Opt::PathcardExtractor`の唯一の呼び出し箇所）を経由していないため。**WP2実装のバグではない**（golden spec 3ファイルは全green、抽出器自体は正しく動作することを実測確認済み）。運用上の含意: リハーサル前にデモ用OPT群を実際のドロップゾーン経由で（再）登録する一手順が必要（コード修正ではない）。
2. **`semantics.rm_type`は設計文書に定義されているが実装（`app/lib/opt/pathcard_extractor.rb:115-118`）に存在しない**。「構造メタデータ検索」を謳うWP3の前提として扱う必要がある。
3. **`lang`フィールドは「OPT宣言言語」であって「テキストの実言語」ではない**（`bmi_calculation`はOPT宣言`en`だが実ラベルは日本語）。検索実装で`lang=="ja"`フィルタは誤り。
4. **抽出時レポート（`Result#report`）は成功パスで事実上破棄されている**（`templates_controller.rb:73`が`.cards`のみ取得）。WP3でUI表出するなら永続化・出力経路の新設が必要。

### 検索水準の実測（15枚のカード、18クエリでのprobe）

- 単純部分一致で素直にヒット: 8/18（短い単語クエリ、例:「収縮期」「身長」「診断」）
- 粒度ギャップで完全ミス: 3/18（例:「収縮期血圧」——カード側は「収縮期」のみ。n-gram一致があれば救える）
- 真の同義語・訳語ギャップ: 3/18（例:「BMI」「体格指数」「既往」——形態素解析でも救えない、embedding/同義語辞書が必要）
- フィールド範囲の見落とし: 1/18（「疑い」は`constraints.value.code_list[].label`にのみ存在——検索対象フィールドに追加が必要）
- descriptionsは15枚中13枚（87%）が未翻訳英語のまま——**labelsが検索の主戦場**、descriptionは補助

### インフラ実測

- 全環境SQLite3、pg/pgvector gemはゼロ。Anlage自作コード側（マイグレーション・AQL実行系）にSQLite固有記法は不検出——**Anlage側の移行自体は局所改修で済む見込み**
- **Docker・CIはPostgreSQL未対応でゼロからの追加作業が必要**（CIは現状rspec自体を実行していないことも判明——DB選択と無関係な既存ギャップ）
- 調査実行機ではPostgreSQL 16が既に稼働中（pgvectorはapt一発）だが、**実際のデモ会場機体との同一性は未確認**。デモ実行環境の実体がドキュメント上どこにも明記されていない
- LLM/埋め込みAPI関連の実装・設定は現状ゼロ。カード1枚あたりのテキスト量は数十字と小さく、登録時バッチ埋め込み・実演時は索引検索のみという設計は量的には実現性が高い（推測、pgvector採用が前提）

## Step 2 計画

### 段階設計: Phase 1（デモ成立の最小）／ Phase 2（拡張、人間ゲート）

**Phase 1（WP3として今回実装。基盤変更なし、外部API呼び出しなし）**

SQLite上の既存`templates.pathcards`列に対する**その場スキャン**（別テーブルの索引を新設しない）で検索する。カード総数が現状15枚・デモ規模でも数十〜百枚程度に収まる見込みのため、事前索引無しの全件スキャンで性能上の問題は生じない（過剰設計を避ける、CLAUDE.mdの実装方針に合致）。索引の鮮度は自動的に保たれる（`templates.pathcards`自体がOPT投入時に更新されるため、別途の索引更新ロジックが不要）。

マッチング方式: **bigram（2文字n-gram）によるOR一致**。クエリと各カードの検索対象テキストをそれぞれ2文字ずつのn-gramに分解し、共通n-gramを持つカードをスコア順に返す。実測（検索水準probe）で確認した「収縮期血圧→収縮期」のような粒度ギャップはこれで救える（共有bigram「収縮」「縮期」）。形態素解析器（MeCab等のネイティブ依存）を導入せずSQLite/Ruby標準機能内で完結する。

検索対象フィールドは実測で判明した範囲に修正する: `semantics.labels[].text` / `semantics.descriptions[].text` / `constraints.value.code_list[].label`（探索前の想定に無かった、実測で発見）。

**Phase 1のスコープに含める小さな前提修正**（承認事項1・2参照）:
- `Opt::PathcardExtractor`に`semantics.rm_type`を追加する（WP2の既存golden回帰網の更新を伴う）
- 検索実装が`constraints.value.code_list[].label`も検索対象に含める

**Phase 1で解決しない既知の制約**（正直に開示、デモの質疑応答対応と同じ姿勢）: 「BMI」「体格指数」「既往」のような真の同義語・訳語ギャップは、bigram一致では原理的に救えない（字面上の手がかりが無いため）。ハンドロールの同義語辞書での回避は、LLM分業原理（CLAUDE.md規律7: 意味・構造・コード・制約は常にOPT・CKM・用語マスターから実行時に引く）に反する（捏造した意味対応をコードに埋め込むことになる）ため採らない。この制約はPhase 2（embedding）で解決する対象として明示し、デモ台本側では既知の限界として扱う。

**Phase 1の成果物**:
- 検索サービス（`Opt::PathcardSearch`等、既存`Opt::`サービスオブジェクト慣行に合わせる）
- 内部検索API（新設ルート、例: `GET /pathcards/search?q=...`）
- 最小の開発用UI（既存`_template.html.erb`パーシャル・Turbo Streamパターンを流用したクエリ入力→結果カード表示）
- （承認事項3次第で）抽出時レポートの最小限の永続化・表示

**Phase 2（凍結後 or 12月世界公開に向けて、人間ゲート事項——本計画では実装しない）**

- PostgreSQL移行（database.yml・Gemfile・`templates.pathcards`等のjson→jsonb・pgvector拡張の有効化・ベクタ列migration）。Docker・CIへのPostgreSQL対応も含む
- 埋め込みプロバイダ抽象層の実装（差し替え可能な設計。将来のローカル/オープンウェイト代替を見据える、プロンプト3節WP3の要求どおり）
- 登録時バッチ埋め込み（デモ実演中は索引検索のみで会場ネットワーク依存を避ける設計）
- 「BMI」「体格指数」「既往」のような同義語・訳語ギャップの解消

### TDD方針（Phase 1）

1. **Red/Green（`Opt::PathcardExtractor`拡張）**: `semantics.rm_type`が抽出結果に含まれることを検証するユニットspec（既存`spec/lib/opt/pathcard_extractor_spec.rb`相当への追加）。golden fixture 3ファイル（`spec/fixtures/pathcards/*.golden.json`）の再生成・差分レビューを伴う（実物主義に従い、実OPTから再抽出した値で更新）
2. **Red/Green（検索サービス）**: 実測で使った15枚（既存golden fixture＋bmi_calculation）を既知の入力として、「収縮期」→CardiologyEncounter at0004がヒット、「収縮期血圧」→同カードがbigram一致でヒット、「BMI」→ヒット無し（既知の限界を固定するregression pin）、「疑い」→code_list label経由でProblemList at0073がヒット、という代表ケースをspecで固定する
3. **Red/Green（内部検索API＋UI）**: request specでクエリ→カード一覧の表示を検証する
4. （承認事項3が承認されれば）**Red/Green（reportの永続化）**: 未翻訳疑い一覧がUIに表示されることを検証する統合spec

### 運用手順（コード変更ではない）

デモリハーサル前に、5 fixture OPT（`docs/demo/opt-catalog.md`）を実際のドロップゾーン経由で（再）登録し、開発DBの`templates.pathcards`を実体化させる。

### 承認が必要な判断（人間ゲート事項）

1. **Phase 1／Phase 2の段階設計そのもの**の採否。Phase 1はプロンプト3節WP3が明示する「pgvectorによる埋め込み索引」という機構要件を満たさない（bigram一致のみ）が、DoD「日本語クエリで関連カードが返る」は満たす設計である——この解釈のずれを承知の上での承認を求める
2. **PostgreSQL/pgvector移行（Phase 2）の実施可否・時期**: WP0 5節-1の留保に対する決定。選択肢: (a) 11/5凍結前に完了させる (b) 凍結後・12月世界公開に向けて実施 (c) 実施しない（Phase 1のbigram方式を恒久解とする）。実測材料: Anlage自作コード側の移行は局所改修で済む見込みだが、Docker・CIは未対応でゼロからの追加作業。**デモ実行環境の実体（development環境か、Docker本番相当か、壇上の機体はどれか）がドキュメント上不明**——この確認自体も本判断の前提として必要
3. **`semantics.rm_type`追加をWP3 Phase 1のスコープに含めるか**（WP2の既存golden回帰網を更新することになる）。含めない場合、Phase 1の検索はRM型でのフィルタ・ファセットを持たない設計になる
4. **抽出時レポート（未翻訳疑い一覧）のUI表出をWP3 Phase 1に含めるか**、それとも別Issueとして切り出すか（WP2計画が「UI表出はWP3以降」としていた経緯があるため、WP3側で引き取るのが自然だが、スコープを広げすぎない判断も可能）

## Verification（実装着手後）

- `bundle exec rspec spec/lib/opt/pathcard_extractor_spec.rb spec/lib/opt/pathcard_extractor_golden_spec.rb spec/lib/opt/pathcard_search_spec.rb spec/requests/pathcards_spec.rb`（実際のファイル名はTDD Green時に確定）が green
- 実際にドロップゾーン経由でOPTを登録し、検索UIで日本語クエリを入力して関連カードが返ることを目視確認
- Issue #12のAcceptance criteria（plan確定後に追記予定のもの）すべてにチェックが入る状態であることを確認
