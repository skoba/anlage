# WP3 実装計画: パスカード索引・検索層

**作成日**: 2026-08-23
**対象Issue**: `skoba/anlage#12`（goal）
**位置づけ**: `claude-code-prompt_semantic-pathcards.md` 3節WP3。WP2（パスカード抽出器、`skoba/anlage#8`、完了済み）の成果物`templates.pathcards`を検索可能にする。
**ログ**: `docs/reports/wp3-log.md`（R1〜。本計画のexplore実測記録）

> **裁定済み（2026-08-24）**: 4判断すべて承認。実装（Codex起動）着手可。
> 条件・詳細は本文書末尾「裁定反映」節を参照。

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

### 承認が必要な判断（裁定済み・2026-08-24、詳細は末尾「裁定反映」参照）

1. **Phase 1／Phase 2の段階設計そのもの**の採否。Phase 1はプロンプト3節WP3が明示する「pgvectorによる埋め込み索引」という機構要件を満たさない（bigram一致のみ）が、DoD「日本語クエリで関連カードが返る」は満たす設計である——この解釈のずれを承知の上での承認を求める。**裁定: 承認**（DoDが契約であり、pgvectorは手段の先行指定という位置づけ）
2. **PostgreSQL/pgvector移行（Phase 2）の実施可否・時期**: WP0 5節-1の留保に対する決定。**裁定: 凍結後・12月世界公開に向けての判断点として確定**（pgvectorの価値はデモよりも公開後の実用に効くため）
3. **`semantics.rm_type`追加をWP3 Phase 1のスコープに含めるか**（WP2の既存golden回帰網を更新することになる）。**裁定: 含める**（承認済みスキーマと実装の乖離は正しさの負債であり、実装をスキーマに追いつかせる是正として実施）
4. **抽出時レポート（未翻訳疑い一覧）のUI表出をWP3 Phase 1に含めるか**、それとも別Issueとして切り出すか。**裁定: 別Issueへ切り出し**

## 裁定反映（2026-08-24）

### 判断1: Phase 1/2段階設計、承認（条件2点）

(i) `claude-code-prompt_semantic-pathcards.md` WP3節にas-built注記1行を追加済み:
    「機構はPhase 2へ、DoDはPhase 1で充足、2026-08-24裁定」
(ii) 真の同義語ギャップ（BMI↔体格指数等）はPhase 2の存在理由として明記する（下記）。
     デモ台本はカード語彙内のクエリで組む。手作りalias表は実需（台本上の必要）が
     出た場合のみ検討し、投機的には作らない——LLM分業原理（CLAUDE.md規律7:
     意味・構造・コード・制約は常にOPT・CKM・用語マスターから実行時に引く）に
     照らし、手作業での意味対応の捏造を避けるため。

**Phase 2の存在理由（明記）**: 実測（`docs/reports/wp3-log.md` R1）で確認した
「BMI」対「Body mass index」（未翻訳）、「体格指数」、「既往」対「プロブレム」の
ような真の同義語・訳語ギャップは、Phase 1のbigram一致では原理的に解決できない
（字面上の手がかりが皆無なため）。これがPhase 2（embedding）を要する具体的な
存在理由であり、投機的な機能ではなく実測済みの必要性に基づく。

### 判断2: pgvector/PostgreSQL移行時期、凍結後に確定

Phase 2の判断点は「デモ後・12月公開準備時」。前提として、デモ実行環境の文書化
（マシン/OS/DB/ネットワーク・オフライン前提の有無、`docs/demo/`へ1段落）が
人間供給事項として新設された。この情報は実物主義（CLAUDE.md規律3）により
Claude Codeが推測で作成できないため、本タスク完了後に別途依頼する
（Phase 2判断・LLM統合境界の判断材料となる）。

### 判断3: semantics.rm_type、Phase 1に含める（条件3点）

(a) 独立コミットとし、golden再生成は「スキーマ準拠追加による再生成」と
    コミットメッセージに明記する
(b) スキーマ文書2節のサンプル3枚へのrm_type追記——**実測の結果、既に記載済み
    であることを確認**（`docs/design/pathcards-schema-v1.md:112,157,210`）。
    追加作業不要
(c) shape specをフィールド水準に強化し、`semantics`の定義済みキー実在を
    assertする（「サンプル一致≠スキーマ準拠」ですり抜けた穴を構造的に塞ぐ、
    openehr-ruby #46の番犬拡張と同型）

`schema_version`は`"1.0"`のまま変更しない（スキーマ変更ではなく実装の追従）。

### 判断4: 抽出レポートのUI表出、別Issueへ切り出し

**起票済み: `skoba/anlage#13`**（problem Issue）。カード側の`untranslated_suspect`
フラグから大半のUIが導出可能（レポート永続化なしで成立し得る）という設計メモと、
永続化する場合の論点を明記済み。着手はWP3後に裁定。

### 発見1（pathcards全件NULL）への対処: Phase 1にbackfillを含める

`rake pathcards:backfill`（カード未生成テンプレートに抽出器を実行、冪等）を
小タスクとして同梱。フック位置の再議論はしない（候補B却下の裁定は不変——
これは運用補完）。「controller非経由の直接saveはカード未生成になる」旨を
運用注記として`docs/demo/opt-catalog.md`に追記する。

### 発見3（langの意味）への対処

Phase 1検索は`lang`でフィルタしない（全テキスト横断＋`untranslated_suspect`は
表示メタデータとして利用）。

## Verification（実装着手後）

- `bundle exec rspec spec/lib/opt/pathcard_extractor_spec.rb spec/lib/opt/pathcard_extractor_golden_spec.rb spec/lib/opt/pathcard_search_spec.rb spec/requests/pathcards_spec.rb`（実際のファイル名はTDD Green時に確定）が green
- 実際にドロップゾーン経由でOPTを登録し、検索UIで日本語クエリを入力して関連カードが返ることを目視確認
- Issue #12のAcceptance criteria（plan確定後に追記予定のもの）すべてにチェックが入る状態であることを確認
