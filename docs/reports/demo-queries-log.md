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
