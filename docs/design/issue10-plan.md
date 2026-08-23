# Issue #10 実装計画: フォーム保存経路のAQL合流

**作成日**: 2026-08-23
**対象Issue**: `skoba/anlage#10`
**位置づけ**: `skoba/anlage#9`（ENTRYの`archetype_details`欠落。解消済み）と対になる、
WP3（索引・検索）着手前の最後の構造的関門。
**ログ**: `docs/reports/issue10-log.md`（R1〜。本計画のexplore実測記録）

> **裁定済み（2026-08-23）**: 3判断すべて承認。実装（Codex起動）着手可。
> 条件・詳細は本文書末尾「裁定反映（R2）」節を参照。

## 解決区分（CLAUDE.md「ticket-driven workflow」）

**(b) enhancement**。フォーム保存経路自体は正常動作しており「バグ」ではなく、
AQLという新しい消費者への接続が未実装という位置づけ。新規仕様のspec（フォーム
POST→AQL照会）がまずredになり、その後greenになるenhancement型で進める。

## Step 1 explore実測結果

### 二経路の対比（確定事実）

| 経路 | 書き込み先 | データ形 | AQLから見えるか |
|---|---|---|---|
| フォーム保存（`app/controllers/compositions_controller.rb:24`） | `compositions`（Anlage独自） | canonical JSON hashを1カラムに素通し（uidなし） | **見えない**（AQL Executor/DatasetAdapterはこのテーブルを一切参照しない） |
| CompositionCommitter（現状demo seed専用） | `openehr_rm_compositions`+`openehr_rm_nodes`+`openehr_rm_data_values`+`openehr_rm_versions`+`openehr_rm_contributions` | 正規化RMグラフ | **見える**（`OpenehrRails::Rm::Composition.latest`→`#to_rm`） |

AQL Executorの既定scope: gem`openehr-rails-0.4.1` `lib/openehr_rails/aql/executor.rb:10-11`が
`OpenehrRails::Rm::Ehr.all`＋`OpenehrRails::Rm::Composition.latest`（=`openehr_rm_compositions`）。
`compositions`テーブル・Anlage`::Composition`への参照はgem内ゼロ（grep実測）。

### #9修正はフォーム経路に既に効いている（確認済み）

`compositions_controller.rb:21`とdemo seed両方（`spec/demo/support/height_seed.rb:46`、
`problem_diagnosis_seed.rb:33`）は完全に同一の`Opt::CompositionBuilder.new(template,
values).build`を呼ぶ。`build_entry`の`archetype_details`設定
（`app/lib/opt/composition_builder.rb:55-61`、コミット`3b10d7a`）は呼び出し元による
分岐が一切ない共通コード。**フォーム保存経路のcanonical JSONには既に正しい
`archetype_details`が含まれている**。欠けているのは書き込み先の合流だが、
それ以外にも2つの構造的差異がある:

1. **uid未生成**: `compositions`テーブルにuidカラムなし、Builderもuidを設定しない。
   `CompositionCommitter.commit`は`uid:`必須キーワード引数（gem
   `lib/openehr_rails/rm/composition_committer.rb:12`）。demo seedは
   `SecureRandom.uuid`で都度発行している。
2. **GraphBuilder RESERVED_KEYS未対応キー**: `RMJSONSerializer`出力のENTRYに含まれる
   `language`/`encoding`/`subject`が、gem`lib/openehr_rails/rm/graph_builder.rb:10-11`の
   `RESERVED_KEYS = %w[_type archetype_node_id archetype_details name uid feeder_audit
   links]`に含まれず構造ノードと誤解釈されクラッシュする（`docs/upstream-candidates.md`
   9項、gem側課題）。demo seed両方が`NON_STRUCTURAL_ENTRY_KEYS`削除で個別に
   回避済み（**2箇所に重複**）。

`ehr:`/`owner:`は両方nil可（gem`composition_committer.rb:12`のデフォルト、`owner: nil`は
gem自身のコメントで正当な使用形態と明記）。`DatasetAdapter`の"unlinked"バケット
（`ehr_id: nil`も対象に含む、`lib/openehr_rails/aql/dataset_adapter.rb:37`）により、
Ehr/Patientモデルが存在しない現状のAnlageでもAQL可視になることをdemo spec 4件
（4 examples, 0 failures）で実証済み。**一本化にEhr整備は前提条件ではない**。

### 既存データ・デモ台本

- 開発DB実測: `compositions`（フォーム経由）は**0件**。`openehr_rm_compositions`は
  9件（うち1件は削除済みPlan B暫定seedの残骸、残りはbmi_calculation/ProblemListの
  計測作業残骸で無害）。testDBはtransactional fixturesで常に空。`db/seeds.rb`は空。
- **再投入で足りる**（そもそも移行対象データが0件）。uid対応関係はどこにも
  保持されていないが、`compositions`テーブルが空である以上、移行作業自体が不要。
- デモ台本の実配線: `templates#index`（dropzone）→`forms#show`
  （`GET /forms/:template_id`）→`compositions#create`
  （`POST /compositions/:template_id`）が実ルート（`config/routes.rb`実測）。
  現状`compositions#create`は`compositions`テーブルへの保存のみ。
- `spec/demo/aql_queries_spec.rb`は`type: :model`でHTTPを一切経由せず、demo seed
  ヘルパから`CompositionCommitter.commit`を直接呼ぶ（controllerと構築ロジックは
  共有・最終段のみ相違）。
- **実演と同じ経路でspecが回る形は現実的**: `spec/requests/compositions_spec.rb:47`に
  流用可能なPOSTパターンが既存、demo seedヘルパのvalues（`height_seed.rb:39-44`等）は
  フォーム形式のまま流用可能。

### docsの現状開示は正確（要修正なし、ただし#10解消後に更新要）

`CLAUDE.md:98`・`README.md:48-55`とも「シード経路で検証済み。フォーム経路の合流は
#10未解消」と正直に開示済みで、齟齬なし。#10解消後にこの文言を更新する
（下記「#5受入条件への波及」参照）。

## 合流方式3案の比較

### (a) CompositionCommitter経由への一本化

- 影響範囲は小さい: `compositions`テーブルの用途は全量把握済み
  （`compositions_controller.rb`のindex/show、`app/models/composition.rb`の
  `#concept`はデッドコード〔呼び出し箇所ゼロ〕、`app/views/compositions/
  {index,show}.html.erb`、依存spec 2本のみ`spec/requests/compositions_spec.rb`・
  `spec/system/forms_spec.rb`）。FactoryBot不使用。
- 技術的障害2点（uid生成・RESERVED_KEYS回避策）はdemo seedで実証済みの
  パターンをそのまま複製すれば解決可能。
- **ラウンドトリップが非可逆**: `CanonicalSerializer`/`GraphBuilder`はCompositionルートの
  `language`/`territory`/`category`/`composer`をカラム保存せず、ENTRY側の
  `language`/`encoding`/`subject`もRESERVED_KEYS回避策で削除される。
  `compositions`テーブルを完全に廃止しRMグラフから再構成する設計にすると、
  現行showページの忠実な原本表示が失われる。

### (b) 二重書き（両テーブルへ、独立した2つのAQL権威ストアとして）

- 同一DBのため外側トランザクションでAnlage内のみで原子化可能（層規律適合）。
- uid対応関係を保持する仕組みが現状皆無。解決策は(i)`compositions.uid`列追加
  （Anlage内migrationで層規律適合、クリーン）か(ii)Committerの`owner:`polymorphic
  関連をAnlage`Composition`レコードに転用（型制約なく動作しそうだが、gem自身の
  コメントでは「scaffoldedレコード用」と意図されており転用は契約外の使用、
  実行未検証）。
- 恒常的コスト: Committer側にのみ版管理（Version/Contribution）概念がある。
  update/delete UIが将来実装されると非対称が顕在化する（現状update/delete UIは
  ないため今は未発現）。

### (c) AQL側の読み出し対象を`compositions`にも拡張

- 直接確認（`executor.rb:10-11`・`dataset_adapter.rb:14-15`）: `Executor.execute`/
  `DatasetAdapter.build`は`composition_scope:`をキーワード引数として既に
  受け付けており、**この注入自体はgemファイル無改変で技術的に可能**
  （層規律5には抵触しない）。`queries_controller.rb:28`が現状scopeを渡していない
  箇所のみAnlage側で拡張すれば注入経路は成立する。
- ただし`DatasetAdapter#compositions_for`（`dataset_adapter.rb:40-42`）の契約は
  「`.where(ehr_id:)`で絞り込め、各レコードが`#to_rm`で実`OpenEHR::RM::Composition`を
  返す」こと。gem自身のコメント（`dataset_adapter.rb:8-13`）が明記する通り、
  `OpenEHR::RM::CompositionFactory.create_from_json`は配列属性（content/events/items）を
  再帰変換しないため使えず、これを避けるために`Rm::Composition#to_rm`はJSON
  キャッシュではなく正規化グラフ（`openehr_rm_nodes`等）から再構築している。
  Anlageの`compositions`テーブルは生JSON 1カラムのみで正規化グラフを持たないため、
  `#to_rm`相当をAnlage側で独自実装する必要があり、これは事実上GraphBuilder相当の
  JSON→RM復元処理をAnlage側で再発明することを意味する（`ehr_id`列も無いため
  `compositions_for`の絞り込み契約自体も満たせない）。
- 結論: 層規律への抵触という理由ではなく、gemが正規化グラフ経由の設計にした
  理由（JSON→RM復元の困難さ）をAnlage側で丸ごと再発明することになり、(a)に対して
  実装コスト・脆弱性の両面で明確に劣後する。**3案中もっとも実現性が低い**。

## Step 2 計画

### 推奨方針

**(a)を採用するが、`compositions`テーブルは廃止せず非権威のarchival/表示ストアと
して無変更のまま残す**（index/showアクション・ビューは変更しない）。追加するのは
`compositions#create`に、Committer経由でRMグラフへも書き込む処理のみ。

- (a)が持つ「ラウンドトリップ非可逆」の懸念は、`compositions`テーブルを
  廃止しないことで無効化される（showページの原本表示はこれまで通り
  `rm_composition`カラムの生JSONから行われ、一切変更しない）。
- (b)が懸念する「独立した2つのAQL権威ストア」の整合性リスクは発生しない——
  `compositions`テーブルはAQLの照会対象にならない非権威ストアのままなので、
  仮にarchival書き込みだけ失敗してもAQLの正しさには影響しない（showページから
  当該1件が見えなくなるだけの軽微な劣化）。
- uid対応は`compositions`に`uid`列をAnlage側migrationで追加し、controller側で
  1回`SecureRandom.uuid`を発行して両方の書き込みに共通で使う（(b)の懸念への
  対処を(a)の枠内に取り込む）。
- RESERVED_KEYS回避策の重複（現状demo seed 2箇所）を3箇所目に増やさないため、
  「canonical hash構築→回避策適用→Committer.commit」を1つの共有クラス
  （既存の`Opt::TemplateDiff.call`等と同じ`Opt::`サービスオブジェクト`.call`慣行に
  合わせる。命名はTDD Green時に決定）に抽出し、controller・両demo seedヘルパの
  3箇所から呼ぶ形にリファクタする。

### 不採用理由

- **(b)二重書き（独立2権威ストアとして）**: uid対応の新設コストと将来の版管理
  非対称という恒常的コストに見合う利点がない——archival目的のみなら
  「(a)+非権威archival保持」で同じ結果がより低リスクに得られるため。
- **(c)AQL側拡張**: scope注入自体はgem無改変で可能（層規律5には抵触しない）だが、
  `#to_rm`契約を満たすにはgemが正規化グラフ経由に設計した理由そのもの
  （JSON→RM復元の困難さ）をAnlage側で丸ごと再発明する必要があり、(a)に対して
  実装コスト・脆弱性で明確に劣後するため。

### TDD方針

- **Red**: フォームPOST（`spec/requests/compositions_spec.rb`に追記、または新設）で
  保存したCompositionが、`OpenehrRails::Aql::Executor.execute`の`CONTAINS
  OBSERVATION`クエリで引けることを検証する統合spec。Q1（height不等号、
  最もシンプル）相当を対象にする。既存`spec/demo/aql_queries_spec.rb`の4本は
  変更しない（スコープ外、実演パリティの完全移行は将来のアイデアとして
  `docs/ideas-2027.md`へ）。
- **Green**: 上記の共有クラス抽出＋`compositions_controller.rb#create`からの
  呼び出し追加＋`compositions.uid`列migration。
- 既存データ影響: 開発DBの`compositions`0件のため移行作業不要（migrationで
  uid列を追加するのみ、NULL許容で開始しバックフィル不要）。

### #5受入条件への波及（更新案）

`CLAUDE.md:98`の凍結受入条件行を、#10解消後に「シード経路{+Q1相当のフォーム経路
統合spec}で検証済み。フォーム保存経路のAQL合流は#10で解消済み」に更新する
（既存4クエリのspecはシード経路のまま維持、フォーム経路は新設した1本の統合spec
でカバーする形）。

### 承認が必要な判断（裁定済み・2026-08-23、詳細は末尾「裁定反映（R2）」参照）

1. 推奨方針（(a)採用、`compositions`テーブルは非権威archivalとして無変更維持、
   uid列追加、共有クラスへのリファクタ）の採否 — **裁定: 承認（条件2点付き）**
2. TDD対象をQ1相当1本に限定し、既存4クエリの完全移行は範囲外とする判断の妥当性
   — **裁定: 承認（「#5 specのフォーム経路化」は別problem Issueとして起票）**
3. `compositions.uid`列追加（Anlage側migration）の実施 — **裁定: 承認
   （uid形式・生成層の指定付き）**

## 裁定反映（R2、2026-08-23）

### 判断1の条件2点

(i) **`compositions`テーブルの「非権威archival」地位の明文化**: 実装時、
    `app/models/composition.rb`（またはリファクタ後の該当箇所）にコードコメントで
    「権威ストア=CompositionCommitter経由のRMグラフ（AQL対象）、
    `compositions`=archival・原本表示専用（AQL非対象）」を明記する。加えて
    `README.md`の「今どこまで動くか」節（3節、AQL照会の行）を、#10解消後の
    実態に合わせて更新する（権威/非権威の役割分担を含めた記述に改める）。

(ii) **RESERVED_KEYS回避策の撤去条件コメントを共有クラスに集約**: 現状demo seed
     2箇所（`height_seed.rb`・`problem_diagnosis_seed.rb`）にある
     `NON_STRUCTURAL_ENTRY_KEYS`の撤去条件コメント（「openehr-rails側
     RESERVED_KEYS拡張〔docs/upstream-candidates.md 9項の解消〕後」）を、
     新設する共有クラス側に一本化して引き継ぐ。demo seed側のコメントは
     共有クラスへの参照に置き換える（コメント内容の重複を避ける）。

### 判断2: 「#5 specのフォーム経路化」を別problem Issueとして起票

TDD範囲はQ1相当1本に限定（承認どおり）。既存4クエリをフォーム経路相当に
寄せる作業は、本Issue #10のスコープに含めず、別途problem Issueとして起票する
（着手時期は起票後に裁定 — 台帳外の宿題を作らないため、本計画には着手時期を
記載しない）。**起票済み: `skoba/anlage#11`**（相互参照コメントを#10側にも
記載済み）。

### 判断3: uidの形式・生成層

**実測結果**（詳細: `docs/reports/issue10-log.md` R2）: `OpenEHR::RM::Support::
Identification::HierObjectID`（gem`openehr-2.4.2` `lib/openehr/rm/support/
identification.rb:334-336`）は`UIDBasedID`のエイリアス的サブクラスで独自ロジックを
持たず、`value`は`root[::extension]`という非空文字列であれば形式を問わず受理する
（UUID形式チェックは無い）。`CompositionCommitter.commit`の`uid:`引数
（gem`composition_committer.rb:12`）はplain Stringをそのまま`openehr_rm_compositions.uid`
文字列カラムへ格納するのみで、`.value`抽出等の型変換は行わない
（spec実測: gem側`composition_committer_spec.rb`が`uid: 'uid-1'`のような任意文字列で
検証している）。gem内部の独自uid生成箇所3箇所（`storable.rb:126`・
`contribution.rb:29`・`openehr_api/compositions_controller.rb:31`）はいずれも
拡張子なしの素の`SecureRandom.uuid`をHIER_OBJECT_ID値として使っている。

**決定**: `SecureRandom.uuid`（拡張子なしの素のUUID文字列）を、HierObjectIDの
`root`部分の値としてそのまま使う——これは形式要件を満たす最小構成であり、
gem内部の3箇所と同型のパターン。`HierObjectID`インスタンスとして明示的に
ラップする実装は採らない（`CompositionCommitter`がplain Stringしか要求せず、
ラップ→`.value`展開は往復するだけの無駄な間接化になるため）。

**採番層**: 新設する共有クラス側で1回`SecureRandom.uuid`を生成し、
`compositions.create!(uid: ...)`と`CompositionCommitter.commit(hash, uid: ...)`の
両方に同一値を渡す。controller側やモデルの`before_create`コールバックでの
生成は採らない——両方の書き込みが同一uidを共有する必要があり、両方を
橋渡しする層（共有クラス）が生成の責務を持つのがもっとも凝集度が高いため
（この根拠は実装コミットのメッセージに1行残す）。

## Verification（実装着手後）

- `bundle exec rspec spec/requests/compositions_spec.rb spec/demo/` が green
- `git diff`で共有クラスへのリファクタが両demo seedヘルパ・controllerの
  3箇所に反映されていることを確認
- Issue #10のAcceptance criteria（CompositionCommitter呼び出し・AQL照会specの
  固定・compositionsテーブルとRMグラフテーブルの関係の設計判断明記）すべてに
  チェックが入る状態であることを確認
