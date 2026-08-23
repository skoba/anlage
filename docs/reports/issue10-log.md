# #10（フォーム保存経路のAQL合流）進行ログ

explore→planフェーズの実測記録。R1〜。

---

## R1: Step 1（explore、3エージェント並列実測）

### 調査1: 二経路の全容と#9後の実態

- **フォーム保存経路**: `app/controllers/compositions_controller.rb:10-26`
  `#create`。:21で`Opt::CompositionBuilder.new(@template, values).build`、
  :22で`RMJSONSerializer`シリアライズ、:24で`@template.compositions.create!
  (rm_composition: JSON.parse(json))` — canonical JSON hashを1カラムに素通し
  保存。uid生成なし、EHR紐付けなし、バージョニングなし。
  `app/models/composition.rb:1-7`は`belongs_to :template`のみ。
  `db/schema.rb:14-20`の`compositions`テーブルにuid/ehr_id/owner/
  latest_version列は存在しない。
- **CompositionCommitter経路**（現状demo seed専用）: gem
  `lib/openehr_rails/rm/composition_committer.rb:12`
  `commit(canonical_hash, uid:, ehr: nil, owner: nil, context_start_time: nil)`。
  トランザクション内でGraphBuilder→`Rm::Composition.create!`→グラフ構築。
  書き込み先: `openehr_rm_compositions`・`openehr_rm_nodes`・
  `openehr_rm_data_values`・`openehr_rm_versions`・`openehr_rm_contributions`
  （すべて`db/schema.rb`で実在確認）。
- **AQL Executorのデータソース**: gem`lib/openehr_rails/aql/executor.rb:10-11`
  既定scope`OpenehrRails::Rm::Ehr.all`＋`OpenehrRails::Rm::Composition.latest`。
  `lib/openehr_rails/aql/dataset_adapter.rb:33-43`が`ehr_id`ごとに
  `compositions_for`＋`ehr_id: nil`のunlinkedバケットもDatasetに含める。
  各Compositionは`#to_rm`（RmObjectBuilder）でグラフから再構築（JSONキャッシュ
  ではない、`dataset_adapter.rb:8-13`のコメントで明記）。`aql/`配下で
  `Composition`参照は`OpenehrRails::Rm::Composition`の2箇所のみ（grep実測）。
  Anlageの`compositions`テーブル・トップレベル`::Composition`への参照はゼロ。
- **#9修正の効き**: `compositions_controller.rb:21`とdemo seed両方
  （`height_seed.rb:46`・`problem_diagnosis_seed.rb:33`）は完全に同一の
  `Opt::CompositionBuilder.new(template, values).build`を呼ぶ。`build_entry`の
  `archetype_details`設定（`composition_builder.rb:55-61`、コミット`3b10d7a`）は
  呼び出し元による分岐が一切ない共通コード。フォーム保存経路のcanonical JSON
  には既に正しい`archetype_details`が含まれることを確認済み。
- **書き込み先合流「以外」の構造的差異**（実測で2点確認）:
  1. uid未生成（`compositions`テーブルにuid列なし、Builderもuid未設定。
     Committerは`uid:`必須キーワード引数）
  2. GraphBuilder RESERVED_KEYS未対応キー（`language`/`encoding`/`subject`が
     gem`graph_builder.rb:10-11`の`RESERVED_KEYS`に含まれずクラッシュ、
     `docs/upstream-candidates.md` 9項。demo seed両方が個別に回避策を実装済み
     で2箇所に重複）
- `ehr:`/`owner:`は両方nil可（`owner: nil`はgem自身のコメントで正当な使用形態と
  明記）。`DatasetAdapter`のunlinkedバケットによりEhr/Patientモデル不在の現状
  でもAQL可視（demo spec 4件で実証済み）。**一本化にEhr整備は前提条件ではない**。

### 調査2: 合流方式3案の実測比較

- **(a)一本化**: `compositions`テーブルの用途は全量把握済み（index/show、
  `#concept`はデッドコード、依存spec 2本のみ`spec/requests/compositions_spec.rb`・
  `spec/system/forms_spec.rb`、FactoryBot不使用）。技術的障害2点はdemo seedの
  パターン複製で解決可能。ただしラウンドトリップが非可逆（Compositionルートの
  `language`/`territory`/`category`/`composer`はGraphBuilder側でカラム保存
  されず、ENTRY側`language`/`encoding`/`subject`も回避策で削除される）ため、
  `compositions`テーブル完全廃止＋RMグラフからの再構成という設計にすると
  showページの原本表示忠実性が失われる。
- **(b)二重書き**: 同一DBのため外側トランザクションでAnlage内のみ原子化可能
  （層規律適合）。uid対応関係を保持する仕組みが現状皆無——`compositions.uid`列
  追加（クリーン）か`owner:`転用（契約外使用、実行未検証）のいずれかが必要。
  Committer側のみ版管理概念があり、将来update/delete UI実装時に非対称が
  顕在化するリスクがある。
- **(c)AQL側拡張**: `Executor.execute`/`DatasetAdapter.build`は
  `composition_scope:`を既に受け付けており、scope注入自体はgem無改変で
  可能（層規律5には抵触しない、`executor.rb:10-11`・`dataset_adapter.rb:14-15`で
  確認）。ただし`DatasetAdapter#compositions_for`の契約（`.where(ehr_id:)`＋
  各レコードが`#to_rm`で実RMオブジェクトを返す）を満たすには、gemが
  正規化グラフ経由の設計にした理由そのもの（JSON→RM復元の困難さ、
  `dataset_adapter.rb:8-13`）をAnlage側で丸ごと再発明する必要があり、
  (a)に対して実装コスト・脆弱性の両面で明確に劣後する。3案中もっとも
  実現性が低いと判断。

### 調査3: 既存データ・デモ台本・#5波及

- **開発DB実測**（sqlite3 readonly接続で直接カウント）: `compositions`
  （フォーム経由）**0件**。`openehr_rm_compositions`**9件**（うち1件は削除済み
  Plan B暫定seedの残骸`template_id="demo-height-provisional"`、残りは
  bmi_calculation/ProblemListの計測作業残骸で無害）。testDBはtransactional
  fixturesで常に空。`db/seeds.rb`は空。
- **再投入で足りる**: 移行対象データが0件のため移行作業自体が不要。
- **デモ台本の実配線**: `config/routes.rb`実測で`templates#index`（dropzone）→
  `forms#show`（`GET /forms/:template_id`）→`compositions#create`
  （`POST /compositions/:template_id`）が実ルート。現状`compositions#create`は
  `compositions`テーブルへの保存のみ。
- `spec/demo/aql_queries_spec.rb:5`は`type: :model`でHTTPを一切経由せず、
  demo seedヘルパから`CompositionCommitter.commit`を直接呼ぶ（構築ロジックは
  controllerと共有、最終段のみ相違）。
- **実演と同じ経路でspecが回る形は現実的**: `spec/requests/compositions_spec.rb:47`
  に流用可能なPOSTパターンが既存。demo seedヘルパのvalues
  （`height_seed.rb:39-44`・`problem_diagnosis_seed.rb:25-31`）はフォーム形式の
  まま流用可能。前提条件はRESERVED_KEYS回避策の同等物を合流実装側が
  引き取ること。
- **docs整合**: `docs/design/demo-queries-plan.md:21`は案Aを「実演に最も近い
  経路」と説明するが実装手順`:52-54`はフォームPOSTを含まない。`CLAUDE.md:98`・
  `README.md:48-55`は「シード経路で検証済み、フォーム経路合流は#10未解消」と
  正直に開示済みで齟齬なし。

### Step 2への引き継ぎ

計画書は`docs/design/issue10-plan.md`に作成。推奨方針（(a)採用＋`compositions`
テーブルを非権威archivalとして無変更維持、uid列追加、共有クラスへのリファクタ）
と、TDD対象をQ1相当1本に限定する判断、承認事項3点を明記し、ゲート報告で
承認を仰ぐ。

---

## R2: 裁定（2026-08-23）— 3判断すべて承認、uid形式の実測調査

3判断とも承認。判断1に条件2点（非権威archival地位の明文化、RESERVED_KEYS
撤去条件コメントの共有クラスへの集約）、判断2に付帯決定（「#5 specの
フォーム経路化」は別problem Issueとして起票）、判断3にuid形式・生成層の
指定が付いた。詳細は`docs/design/issue10-plan.md`「裁定反映（R2）」節参照。

### uid形式の実測調査（判断3の裏付け）

`OpenEHR::RM::Support::Identification::HierObjectID`（gem`openehr-2.4.2`
`lib/openehr/rm/support/identification.rb:334-336`）は`UIDBasedID`の
エイリアス的サブクラスで独自ロジックを持たない。`value`は`root[::extension]`
形式の非空文字列を受理するのみで、UUID形式チェックは無い（`UIDBasedID#value=`、
同`:226-235`）。**当初の調査依頼で前提としていた「HIER_OBJECT_IDは
`root::creating_system_id::version`の3分割拡張形式を許す」は誤りで、それは
別クラス`ObjectVersionID`（同`:242-294`）の仕様と判明**（実測で訂正）。

`CompositionCommitter.commit`の`uid:`引数（gem`composition_committer.rb:12`）は
plain Stringをそのまま`openehr_rm_compositions.uid`文字列カラムへ格納するのみ
（`.value`抽出等の型変換なし。gem側spec`composition_committer_spec.rb`が
`uid: 'uid-1'`等の任意文字列で検証していることで裏付け）。

gem内部の独自uid生成箇所3箇所（`lib/openehr_rails/storable.rb:126`・
`lib/openehr_rails/rm/contribution.rb:29`・
`app/controllers/openehr_rails/openehr_api/compositions_controller.rb:31`）は
いずれも拡張子なしの素の`SecureRandom.uuid`をHIER_OBJECT_ID値として使う
（`HierObjectID`インスタンスとして明示的にラップしているのは、DB→RMオブジェクト
変換方向の`rm_object_builder.rb:39`の1箇所のみで、値生成方向ではない）。

**決定**: `SecureRandom.uuid`をHierObjectIDのroot値としてそのまま使う（明示的な
`HierObjectID`インスタンス化はしない）。採番は新設共有クラス側で1回行い、
`compositions`行・Committer呼び出しの両方に同一値を渡す（両者を橋渡しする層が
生成責務を持つのがもっとも凝集度が高いため）。

### 次のアクション

1. 「#5 specのフォーム経路化」を別problem Issueとして起票、#10側へ相互参照
2. `docs/design/issue10-plan.md`・本ログを裁定反映してコミット・push
3. Codex起動（TDD: Red→Green、共有クラス抽出、uid列migration）
4. 独立レビュー→`Implemented-by: Codex`トレーラーでコミット→`Fixes #10`
5. README「今どこまで動くか」節・コードコメントで非権威archival地位を明文化
6. `CLAUDE.md`の#5凍結受入条件行を更新

---

## R3: 実装（Codex納品→独立レビュー→コミット、#10クローズ）

Codexが計画・裁定どおりに実装。新設共有クラス`Opt::RmCompositionCommitter`
（`app/lib/opt/rm_composition_committer.rb`）が「Builder→Serializer→
RESERVED_KEYS回避策→Committer.commit」を集約し、uid生成（1回、共有クラス側）
も担う。archival用`canonical_hash`はCommitter用コピーとは別に`deep_dup`で
保持し、回避策適用前の原本のまま`compositions.rm_composition`へ保存する
設計（指示より一段丁寧——showページの原本表示忠実性が回避策の影響を
受けない）。

### 実行結果（Codex報告→Claude Codeが独立に再実行して検証）

- リファクタ後回帰確認: `spec/demo/` **4 examples, 0 failures**（既存4クエリ
  の振る舞い不変）
- Red（`spec/requests/compositions_spec.rb`新規specのみ）: **6 examples,
  1 failure**（`expected [[180.0]], got []` — controller未変更のため
  AQLに合流せず、想定どおりの失敗）
- Green（controller実装後、同ファイル）: **6 examples, 0 failures**
- 全suite（Codexのsandbox内、Capybaraのlocal TCP socket作成がsandbox
  制約で拒否されたためsystem spec 6件のみ失敗）: 85 examples, 6 failures
  （`Errno::EPERM: socket(2) for 127.0.0.1 port 0`、コード起因ではない）。
  system spec除く79件相当の非system実行: 78 examples, 0 failures
- **Claude Codeによる独立再実行**（sandbox外、フルスイート）: **85 examples,
  0 failures**（system spec含め全green。#9実装時と同型のsandbox制約による
  偽陽性であることを確認）

### diff精査（Claude Code、コミット前）

- `app/lib/opt/rm_composition_committer.rb`: 新規。`Result = Data.define
  (:uid, :composition, :canonical_hash)`。`NON_STRUCTURAL_ENTRY_KEYS`と
  撤去条件コメントをここに一本化。
- `app/controllers/compositions_controller.rb#create`: `Opt::
  RmCompositionCommitter.call(@template, values)`を呼び、返ってきた
  `commit.canonical_hash`・`commit.uid`を`compositions.create!`に渡す形に
  変更。
- `app/models/composition.rb`: 権威/非権威の役割分担コメントを追加
  （裁定条件(i)）。
- `db/migrate/20260823000002_add_uid_to_compositions.rb`: `compositions`に
  `uid`（string、null許容）を追加。`db/schema.rb`は同migration適用分＋
  既存の無害な配列ブラケット表記差分（`[ "x" ]`→`["x"]`、過去セッションで
  既知の書式差分ノイズ）のみ。
- `spec/demo/support/height_seed.rb`・`problem_diagnosis_seed.rb`: 共有
  クラス呼び出しへリファクタ。`NON_STRUCTURAL_ENTRY_KEYS`・撤去条件
  コメントは削除（共有クラスへ参照コメントのみ残す）。
- `spec/requests/compositions_spec.rb`: フォームPOST→AQL CONTAINS統合
  spec（Q1相当）を追加。同一uidの検証（`Composition.last.uid == 
  OpenehrRails::Rm::Composition.latest.last.uid`）も含む。
- `README.md`・`CLAUDE.md`: Codexが計画書「裁定反映（R2）」節を読んで
  自発的に更新（本来Claude Code側で行う予定だったが、内容は裁定条件と
  完全に一致しており、精査の上でそのまま採用した）。

コミット`4296f8b`（`Implemented-by: Codex`、`Fixes skoba/anlage#10`）で
push、Issue #10は自動クローズ（確認済み）。
