# #5（デモクエリの実行可能spec化）進行ログ

explore→planフェーズの実測記録。R1〜。

---

## R1: Step 0（前提実測）・Step 1（explore）

### Step 0: 全suite現状確認

`bundle exec rspec`（フルスイート）: **79 examples, 0 failures**。

#3（`patient_blood_pressure.opt`欠落）は本セッション内の別タスク（Part B/gem bump作業、コミット`f29b3e5`）で既に解消済みであり、WP2フェーズ開始時点で既に全suite green（56/0）だった。したがって本タスクのStep 0で新たに対応すべき#3関連の残作業は無い。

### Step 1-1: heightクエリの再現条件

`spec/fixtures/opt/*.opt`（CardiologyEncounter / LabResultReport / ProblemList / patient_blood_pressure）を`grep -c height`で確認 → **全fixtureで0件**。Anlageの現有fixtureに`openEHR-EHR-OBSERVATION.height.v2`archetypeを含むOPTは存在しない。

**height_queryの出典を特定**: `/home/skoba/src/openehr-rails/spec/openehr_rails/aql/executor_spec.rb:10-13`に、デモで使われたものと**完全に同一のクエリ文字列**が実在する:
```ruby
let(:height_query) do
  'SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height ' \
    'FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]'
end
```
このspecは`BmiCalculation`という、`OpenehrRails::Storable`を直接includeした**軽量ActiveRecordモデル**（`spec/openehr_rails/storable_spec_model.rb`、gem側のテスト専用モデル）に対して実行されている。**OPT登録→Opt::CompositionBuilder経由のRMグラフ構築、というAnlageの実際のドロップゾーンパイプラインは一切通っていない**。

**結論**: デモで実行できたheightクエリは、Anlageの実データ経路ではなく、**gem（openehr-rails）側のテスト専用Storableモデルに対して**（おそらくrails runner/consoleで直接）実行されたものと推定される（実行時点の記録がAnlage側に無いため「推定」）。Anlage側に`height.v2`のOPT fixtureも、対応するCompositionも存在しない。

**Step 2への含意**: #5の`spec/demo/`をAnlageの実パイプライン（OPT登録→フォーム経由の保存、またはOpt::CompositionBuilder直接呼び出し）で構築する場合、**`openEHR-EHR-OBSERVATION.height.v2`のOPT fixtureをCKM/Archetype Designer経由で新規に入手する必要がある**（実物主義。捏造不可）。gem側の`BmiCalculation`方式（Storable直接定義）を流用する代替案もあるが、Anlageの中核思想（「クリニカルモデルを置けば動くEHR」、OPT駆動）とは異なる経路になる。両案をStep 2計画で提示する。

### Step 1-2: AQL実行経路とシード設計

- 実行エントリポイント: `OpenehrRails::Aql::Executor.execute(aql_string, params: {}, ehr_scope:, composition_scope:)`（`/home/skoba/src/openehr-rails/lib/openehr_rails/aql/executor.rb:10-21`）、または `OpenehrRails::Aql.execute(...)`（同ファイル24-26のモジュール関数）
- 戻り値: `result.rows`（配列の配列。gem側spec実測: `expect(result.rows).to eq([[170.0]])`）
- WHERE句のパラメータバインドは `params: { 'min' => 175.0 }` のようなHashで`$min`プレースホルダに対応（gem側spec実測、executor_spec.rb:23-31）
- Anlageアプリ本体（`app/`・`lib/`）にはAQL関連コードが一切無い（`grep -rln "Aql::" app/ lib/`が空）。ルーティングにもAQLコンソール等は無い（`config/routes.rb`にaql関連ルート無し）。#5はAnlage初のAQL利用箇所になる
- シードデータ設計: `spec/demo/`配下で、対象OPT登録（またはCompositionBuilder直接呼び出し）→期待件数を伴うAQLクエリ実行、という構成にする（Step 2で具体化）

### Step 1-3: WP2成果（templates.pathcards）の活用可否

`templates.pathcards`は登録済みテンプレートの全ELEMENTについて`identity.path`（AQLパスと同一構文、`content[archetype_id]/...`）を持つ（WP2 TODO 2/3実測、`docs/design/wp2-plan.md` 1.2節）。デモクエリのSELECT/WHERE句が参照するパスが、対象テンプレートの実在するpathcardと一致するかを事前検証する用途に使える（例: クエリのパス文字列が`Template.find_by(template_id: ...).pathcards.map { _1.dig("identity","path") }`に含まれるかを`spec/demo/`のセットアップ時にpin）。これは今回の事故（SELECT別名の消し忘れがWHERE句に残存）の直接の防止策ではない（別名はpathcards外の話）が、**パス自体のタイプミス**という別クラスの事故を防ぐ副次効果がある。#5がpathcardsの初の消費者になる、という見立ては妥当。

---

## R2: 裁定反映・Plan B暫定シード実装（TDD手順1）

裁定（4事項）を反映し、`docs/design/demo-queries-plan.md`のコミット分割案1（案B暫定シード＋height query spec、Red→Green）を実施した。

### 実装内容

- `docs/demo/aql-queries.md`: クエリ一覧の骨格。1本目はheight不等号クエリ（会話記録の原文、供給済み）。2本目はAQL新機能（LIKE/MATCHES/CONTAINS述語/混合集計）からの候補を「意図のみ・原文未供給」のプレースホルダ行として記載（裁定3準拠）
- `spec/demo/support/height_seed_provisional.rb`: 案Bシードヘルパー。`OpenehrRails::Rm::CompositionCommitter.commit`を直接呼び、`openEHR-EHR-OBSERVATION.height.v2`の実archetype構造でcanonical hashを組み立てる
- `spec/demo/aql_queries_spec.rb`: height不等号クエリの実行spec。ファイル冒頭・describe文双方に「暫定・実パイプライン非経由」を明記（裁定1(a)準拠）

### 実データでの構造確認（Composition構築前の実測）

`openEHR-EHR-OBSERVATION.height.v2`の実RM構造を、openehr-rails gem側の実fixture（`spec/generators/templates/bmi_calculation.opt`、Ocean Template Designer出力の実archetype）から実測して確認した:
- 定義木の位置: 同fixtureの最初の`C_ARCHETYPE_ROOT`（251行目〜）。archetype_id宣言（658行目）はこの定義木より**後**に置かれる（他OPTと同じ「定義木→archetype_id/term_definitionsが後続の兄弟」構造。2つ目の`C_ARCHETYPE_ROOT`〔735行目〜〕はarchetype_id 1142行目の`body_weight.v2`であり、height.v2ではない——property code 124/units kgという値から誤認しかけたため、実測で訂正した）
- ELEMENT at0004: `property.code_string = "122"`、`units = "cm"`、`magnitude_range 0.0-1000.0`

### Composition構築時に判明したAPI要件（2点、実測して確定）

1. `OpenehrRails::Rm::EntryNode`（`Observation`等のENTRY系サブクラス）は`archetype_id`のpresence検証を持つ（`nodes.rb:7`）。`GraphBuilder#build_node`はこれを`hash.dig('archetype_details', 'archetype_id', 'value')`から読むため、ENTRY要素（OBSERVATION）のhashには`archetype_node_id`だけでなく`archetype_details.archetype_id.value`も必要（無いと`ActiveRecord::RecordInvalid: Archetype can't be blank`）
2. `origin`（HISTORY）・`time`（POINT_EVENT）は`GraphBuilder#special_columns`が`hash.dig('origin', 'value')`のように**Hash形式**（`{"value" => ...}`）を前提とする。プレーン文字列を渡すと`TypeError: String does not have #dig method`になる

いずれも実行時エラーから実測して確定した（推測せず）。

### 検証結果

- Red: `spec/demo/aql_queries_spec.rb`が`HeightSeedProvisional`未定義で`LoadError`
- Green: シード実装後、`bundle exec rspec spec/demo/aql_queries_spec.rb` 1 example, 0 failures
- 全体: `bundle exec rspec` 80 examples, 0 failures（79+1）
- `bundle exec rubocop spec/demo/` 2 files, no offenses

### 次に必要な人間供給物（既報告のとおり、変更なし）

- `openEHR-EHR-OBSERVATION.height.v2`のOPT fixture（CKM/AD経由、単位・値域入りlab OPT改訂と同一作業で人間が用意）
- height不等号クエリ以外のデモ使用クエリ原文（AQL新機能候補1本を含む）

到着次第、`docs/design/demo-queries-plan.md`のコミット分割案2以降（案Aへの差し替え、追加クエリのTDD、CLAUDE.mdマイルストーン節への受入条件追記）を進める。

---

## R3: bmi_calculation.opt取り込み・#5案Aブロック解除

タスク「デモOPT整備 — bmiコピーで#5解除+カタログ新設」を実施。

### fixture取り込み

`openehr-rails/demo_assets/templates/bmi_calculation.opt`（commit `0f88392d7c890a39fa82bebf26f42410d5c9b9af`、sha256
`d72b6d50b33b2a40d22fce2dad0269f84bb348096e0fda2508b122170df8c272`）を`spec/fixtures/opt/bmi_calculation.opt`へ
出所コメント付きでコピー。lang=en（jaではない）ため、`docs/design/pathcards-language-policy.md` 5節の検収チェックリストは
「対象外の意図的例外」として記録した（AQLのpath照会用途にはラベル言語が本質的でないため）。

height.v2の実archetype構造（`openehr-rails/spec/generators/templates/bmi_calculation.opt`、別配置の同一archetype）を
実測して確認: property code=122（openehr）、units=cm、magnitude_range 0.0-1000.0。**当初、property code=124/units=kg
の別C_ARCHETYPE_ROOTブロック（735行目〜）をheight.v2の定義木と誤認しかけたが、実測（archetype_id宣言の行番号と
定義木の前後関係）で訂正した——これは実際はbody_weight.v2（archetype_id宣言1142行目）だった**。

### ドロップゾーン実演

`Template.build_from_opt_xml`→`Opt::PathcardExtractor`の直接実行、および実際のドロップゾーン（system spec）経由の
両方でheight.v2 at0004のpathcard抽出を確認（4カード中1件、`docs/evidence/2026-08-23--bmi_calculation--height-v2-pathcard-after-dropzone.png`）。

### #5案A: 実パイプラインシードへの移行

`Opt::CompositionBuilder`→`RMJSONSerializer`→`OpenehrRails::Rm::CompositionCommitter.commit`という実フォーム保存経路
準拠のchainを試したところ、2つの構造的ギャップを実測で発見した（いずれも推測せず、エラーから実際に特定）:

1. **`Opt::CompositionBuilder`がENTRYへ`archetype_details`を設定しない**（`archetype_node_id`のみ）。
   `OpenehrRails::Rm::EntryNode`（`nodes.rb:7`）が`archetype_id`のpresenceを検証するため、
   `ActiveRecord::RecordInvalid: Archetype can't be blank`で失敗する。Anlage側の欠陥と判定し、
   **[skoba/anlage#9](https://github.com/skoba/anlage/issues/9)として起票**
2. **`RMJSONSerializer`が出力するENTRY hashの`language`/`encoding`/`subject`キーを、`OpenehrRails::Rm::GraphBuilder`が
   構造子ノードと誤認してクラッシュする**（`RESERVED_KEYS`にこれらが含まれないため。`ArgumentError: unknown RM node
   type "CODE_PHRASE"`）。gem側の欠陥と判定し、**`docs/upstream-candidates.md` 9項へ観察追記**

いずれも実測で確定した後、`spec/demo/support/height_seed.rb`で該当2点を明示コメント付きで回避（archetype_details補完・
非構造キー削除）し、実パイプライン経由でheight不等号クエリのRed→Greenを達成した。案B（`height_seed_provisional.rb`）は
裁定どおり削除。

**この発見自体の副次的な重要性**: Anlage独自の`compositions`テーブル（`CompositionsController#create`が保存する経路）は
`OpenehrRails::Rm::*`のRMグラフテーブルへ一切連携されておらず、**通常のフォーム保存経路で登録されたCompositionは、
そもそもAQLで照会できない**という構造上の事実が判明した。現状AQLはAnlage内で#5以外に使用箇所が無いため今は無害だが、
WP3（索引と検索）着手時に同じ壁に当たる見込み。`skoba/anlage#9`のAcceptance criteriaに含めている。

### 検証結果

- `bundle exec rspec spec/demo/aql_queries_spec.rb`: 1 example, 0 failures（案A、height>170で`[[180.0]]`）
- `bundle exec rspec`（全体）: 80 examples, 0 failures
- `bundle exec rubocop spec/demo/`: 2 files, no offenses

---

## R4: Q2/Q3/Q4原文供給・実測訂正・spec化完了

人間供給のQ2（MATCHES値リスト）・Q3（CONTAINS nodePredicate）・Q4（日付範囲WHERE）原文を、
実測で通る形に訂正した上でspec化した（`docs/demo/aql-queries.md`に差分注記済み）。

### Q2: MATCHES 値リスト

- at-codeプレースホルダ（`at0.63`/`at0.64`）を実値（`ProblemList.opt` at0073「診断確度」の
  ローカル値集合、WP2 TODO 7実測選定分と同一）へ差し替え。パスも`items[at0002]`→`items[at0073]`
  （**パスカードが実際に最初の消費者になった**——`Opt::PathcardExtractor.call`の出力から
  `identity.path`をそのまま引用して確認）
- `value/defining_code/code_string`は現行AQLエンジンの`ALLOWED_TERMINAL_HOPS`
  （openehr gem `lib/openehr/aql/engine/path_evaluator.rb:21`。許可は`magnitude`/`name`/`value`のみ、
  設計コメントに「実クエリが必要とするまで拡張しない」と明記されたスコープ限定）で
  `unsupported path attribute`。`value/value`（DvCodedTextの表示ラベル自体）でのMATCHESに
  訂正して実行確認（2件）

### Q3: CONTAINS nodePredicate

- 原文どおりで実行可能（ELEMENT直接CONTAINS・WHERE EXISTS ともに実測で問題なし）。訂正不要

### Q4: 日付範囲WHERE

- `events[at0002]/time`は現行AQLエンジンで**そもそも到達不能**と判明（`Event`系クラスの
  `path_attribute`宣言に`time`が無く〔openehr gem `lib/openehr/rm/data_structures/history.rb:21`〕、
  `ALLOWED_TERMINAL_HOPS`にも含まれない）。OBSERVATIONの測定時刻という切り口自体が現行AQLエンジンでは
  成立しないため、対象をProblemListのELEMENT値保持DV_DATE_TIMEフィールド（at0003「臨床的に
  認識された日時」）へ差し替えた。AND複数条件は実測で問題なく通った（原文の想定どおり）

### シード拡充

`spec/demo/support/problem_diagnosis_seed.rb`を新設（ProblemList用、`height_seed.rb`と同じ
2回避策——`archetype_details`補完・非構造キー削除——を適用）。

### 検証結果

- `bundle exec rspec spec/demo/aql_queries_spec.rb`: 4 examples, 0 failures
- `bundle exec rspec`（全体）: 83 examples, 0 failures
- `bundle exec rubocop spec/demo/`: 3 files, no offenses

### 凍結受入条件

4クエリ全件が案A（実パイプライン駆動）でgreenになったため、`docs/design/demo-queries-plan.md`
5節の凍結受入条件を満たした。CLAUDE.mdマイルストーン節への反映を実施する。
