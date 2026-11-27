# 記録を FHIR で読み出す道の計画（計画まで）

裁定 ID: R-20261127-9 の作業列 6。状態: **案（ゲート報告。実装には進まない）**。
基準点: anlage main `57f13b1`（openehr 2.6.1、openehr-rails 0.11.0）。gem の読み取りは openehr-rails 0.11.0 と 0.12.0
（RubyGems の版。`bundle exec gem contents openehr-rails` のパス）。

## 1. いまの状態（実測）

- anlage は、登録したテンプレートの StructureDefinition だけを FHIR で出す（`GET /fhir/r5/StructureDefinition/:id`、
  `app/controllers/fhir/profiles_controller.rb`）。記録（Composition）を FHIR のリソースとして読む入口は無い
- engine の FHIR の入口（`/openehr/fhir/Observation`）は、anlage ではいつも 0 件（既知の制限 19、上流候補 31 項、
  `docs/design/m3-plan.md` 9.3 の実測）

## 2. engine の入口が、なぜ実行時の記録を見ないか（gem のコードの読み取り）

| 段 | gem のコード | 前提にしているもの |
|---|---|---|
| どのリソースがあるか | `lib/openehr_rails/fhir/resource_registry.rb` の `discover_from_templates`・`entries_for` | gem の `OpenehrTemplate.operational` と、scaffold した model の定数 `FIELD_MAP` |
| 記録を集める | `app/controllers/openehr_rails/fhir_controller.rb` の `scoped_records`（`entry.model.all`、`where(ehr_id:)`） | scaffold した model の表（1 記録 = 1 行） |
| 記録をリソースにする | `lib/openehr_rails/fhir/serializer.rb` の `Serializer.new(record).observations` | `record.public_send(field[:name])`、`record.id`・`ehr_id`・`composed_at`（Storable の model の属性） |
| 1 件を引く | `fhir_controller.rb` の `resolve`（id は「<model の id>-<slug>」） | model の主キー |
| プロファイル | `lib/openehr_rails/fhir/profile_repository.rb` の `from_registry` | `::OpenehrTemplate` |

anlage は、テンプレートを自分の表（`Template`、`web_template` に field の一覧）に持ち、記録を RM グラフ
（`OpenehrRails::Rm::Composition`）と原本（`Composition`）に持つ。scaffold の model を作らない（実行時動的性が中核思想）。
このため、engine の FHIR の入口のどの段も、anlage の記録に届かない。届かないのは不具合ではなく、engine が
「コード生成した model の経路」のために書かれているから。

一方、意味の対応（どの ENTRY をどのリソースに、どの要素をどの FHIR の要素に）は、engine の中で
`Fhir::TypeMap`（`ENTRY_RESOURCES`、`DATA_VALUE_TYPES`、`ENTRY_ELEMENT_MAPS`、`resource_for_entry`・`datatype_for`。
`module_function` で公開）と `Fhir::ProfileGenerator`（OPT から作る）にあり、model に依らない。anlage はすでに
`ProfileGenerator` を使って StructureDefinition を出している。

## 3. 対応をどこから引くか（LLM 分業原理）

- ENTRY → リソースの種類、要素 → FHIR の要素と型: `Fhir::TypeMap` と、OPT から作るプロファイル（`ProfileGenerator`）。
  StructureDefinition と、読み出すリソースが同じ対応になる
- 項目の意味（ラベル、単位、選択肢の表示）: テンプレート（`web_template` の field。帳票と記録の中身〔#191〕と同じ）
- 値: 記録（`Opt::CompositionReader` で読み戻す。読み戻せない記録は出さない、または出せない理由を返す）
- LLM は使わない。対応の表を推測で足さない（`ENTRY_ELEMENT_MAPS` に無い、Observation 以外の ENTRY は出せない。
  プロファイルと同じ扱い〔`assert_supported!`〕）

## 4. 案

### 案 A: anlage の側に、読むだけの入口を出す

- `GET /fhir/r5/Observation?subject=Patient/<ehr_id>` と `GET /fhir/r5/Observation/<id>`（ほかの種類〔Condition など〕は
  `ENTRY_ELEMENT_MAPS` のある ENTRY だけ）。id は RM の composition の uid と ENTRY の slug から作る
- 記録は `Rm::Composition.latest.not_deleted`（患者の画面と同じ）、値は `Opt::CompositionReader`、
  対応は `Fhir::TypeMap` の公開の関数
- 良い点: anlage の中で閉じる。いま進められる。StructureDefinition の入口（`/fhir/r5/...`）とそろう
- 弱い点: engine の `Serializer` と同じ組み立て（value[x] と component、単位、コード）を anlage に二重に持つ。
  engine の側で形が変わると、二つが食い違う。CapabilityStatement は engine の `/openehr/fhir/metadata` のまま
  （anlage のリソースは載らない）

### 案 B: engine の側を広げる（上流の候補）

- engine の `Serializer` を、Storable の record ではなく「field の一覧と値と、患者・時刻」を受ける形に分け、
  `ResourceRegistry` に、ホストのアプリがテンプレートと記録を渡す口（source）を足す。anlage は source を 1 つ登録する
- 良い点: 組み立てが 1 か所。CapabilityStatement・検索・1 件・作成が、scaffold の経路と実行時の経路で同じ入口になる。
  「OPT を置けば FHIR が動く」が、gem の主張としても成り立つ
- 弱い点: gem の公開 API の追加（openehr-rails の minor）。公開を待つ。上流への提案は人間（上流候補 31 項から起票）

### 案 C: anlage が Storable の record に見えるものを作り、engine の `Serializer` に渡す

- `FIELD_MAP` を持つクラスを実行時に作り、record の属性を値で返す
- 弱い点: gem の内部の形（`FIELD_MAP` の鍵、`public_send`、`composed_at`）に依る。gem の版上げで黙って壊れる。
  No API guessing の規律に照らして、採らない

## 5. 推す案

**案 B を本筋にし、案 B の公開までの間は何もしない（既知の制限 19 のまま）**。理由:

- 案 A は動くが、`Serializer` の組み立てを anlage に写すことになる。写しは、engine の
  `ENTRY_ELEMENT_MAPS` が増えるたびに追随が要り、食い違いは spec でしか見つからない
- 案 B は、上流候補 31 項（観察）の答えそのもの。engine の利用者すべてに効く
- v0.2.x の範囲で FHIR の記録の読み出しを約束していない（README と台本は StructureDefinition と CapabilityStatement だけ）

案 B に進むなら:

1. 上流候補 31 項に、この計画の 2 節の表と案 B の形を書き足し、人間が openehr-rails に起票する
   （本文の案はセッションが用意する）
2. gem の公開のあと、anlage は source を 1 つ登録する PR（依存を変えるので、マージは人間）。
   Postman のコレクションに Observation の検索を戻す（R-20261127-5 の 1 で外した要求）

統括が案 A を選ぶなら、範囲は Observation の検索と 1 件だけ、`ENTRY_ELEMENT_MAPS` の写しは持たず、
Observation の ENTRY だけを出す、とするのを推す（写しを最小にする）。

## 6. 問い（ゲート）

1. 案 B（上流を広げる）を本筋にし、それまで既知の制限 19 のままでよいか。案 A のつなぎを先に作るか
2. 案 B を取るなら、上流候補 31 項を起票の案に書き直してよいか（起票は人間）
