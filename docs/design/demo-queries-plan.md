# #5 実装計画: デモクエリの実行可能spec化

**作成日**: 2026-08-23
**位置づけ**: [skoba/anlage#5](https://github.com/skoba/anlage/issues/5) の実装計画。11/5デモビルド凍結の受入条件「デモクエリ spec green」を構造で実現する。explore→planフェーズの成果物であり、本文書自体はコード変更を含まない。
**進行ログ**: `docs/reports/demo-queries-log.md`（R1）

---

## 1. 背景（Step 0/1実測のまとめ）

- 全suite: 79 examples, 0 failures（#3は既に解消済み、本タスクの対象外）
- デモで使われた`height`不等号クエリは、実は**Anlageの実パイプラインを一度も通っていない**。同一クエリ文字列がopenehr-rails gem側のテスト専用モデル（`BmiCalculation`、`OpenehrRails::Storable`を直接include）に対して実行されたものと推定される（詳細: 進行ログR1）
- Anlageの現有4 OPT fixtureに`openEHR-EHR-OBSERVATION.height.v2`は含まれない
- AQL実行経路（`OpenehrRails::Aql::Executor.execute` / `OpenehrRails::Aql.execute`）はAnlageアプリ本体で未使用。#5がAnlage初のAQL利用箇所になる
- `templates.pathcards`（WP2成果）はクエリパスの事前検証に使える（進行ログR1 Step1-3）

## 2. シードデータ設計: 2案

### 案A（推奨）: 実OPT駆動（Anlageの中核思想に整合）

`openEHR-EHR-OBSERVATION.height.v2`のOPT fixtureをCKM/Archetype Designer経由で入手し、`spec/fixtures/opt/`へ配置。`Opt::CompositionBuilder`（既存クラス、`app/lib/opt/composition_builder.rb`）を使い、`spec/demo/`のシードで実際にCompositionを構築・保存する。デモの実演そのもの（OPT投入→フォーム入力→保存→クエリ）に最も近い経路になり、Anlageの「クリニカルモデルを置けば動くEHR」という思想とも整合する。

**必要な人間供給物**: height.v2 OPT fixture（CKM公開束縛由来、実物主義）。ゲート報告に依頼として含める。

### 案B: Storable直接定義（gem側テスト方式の流用）

`BmiCalculation`相当の軽量`OpenehrRails::Storable`モデルをAnlage内（`spec/demo/`限定、または`spec/support/`）に定義し、OPT登録を経由せずクエリ対象データを作る。新規OPT fixture入手が不要で着手が速いが、Anlageの実パイプラインを通らないため「デモの再演可能性」という#5の目的とは半歩ずれる（型定義がOPTと独立に存在するため、OPTを差し替えてもこのシードは追随しない）。

**推奨**: 案Aを採用する。ただし人間供給物（height.v2 OPT）の到着待ちで#5全体がブロックされるのを避けるため、**案Bを暫定シードとして先に`spec/demo/`の骨格（構造・実行フロー）を組み、案Aのfixtureが届き次第差し替える**という段階移行を提案する（承認事項1）。

**実装時の補足（2026-08-23、R2で確定）**: 実装した案Bは軽量`Storable`モデルではなく、`OpenehrRails::Rm::CompositionCommitter.commit`（canonical composition hashを直接投入、`owner: nil`）を`spec/demo/support/height_seed_provisional.rb`から呼ぶ形にした。新規ActiveRecordモデル・migrationを追加せずに済み、案A差し替え時に削除するファイルの範囲もこの1ファイル＋specファイルに閉じるため、より軽量な足場になっている。

### 案A移行手順（height.v2 OPT到着後）

1. **検収**（`docs/design/pathcards-language-policy.md` 5節の手順に従う）: 届いたOPT fixtureの
   出所（CKM公開archetype由来）・SHA-256・lang=ja/未翻訳許容の前提を確認する
2. **fixture配置**: `spec/fixtures/opt/`へ配置し、出所コメント（他fixtureと同様の慣行）を付す
3. **シード差し替え**: `spec/demo/support/height_seed_provisional.rb`を、`Template.build_from_opt_xml`
   （または`Opt::CompositionBuilder`直接呼び出し）による実OPT駆動の新シードヘルパーへ置き換える。
   手作業canonical hashを組む場合（暫定シードと同様の直接投入を続ける場合）は、**R2で判明した
   以下2点のAPI要件を必ず満たすこと**（`CanonicalSerializer`の出力形と一致させる。gemの正規
   canonical JSON契約であり、省略するとバリデーションエラーまたは`TypeError`になる）:
   - ENTRY系ノード（OBSERVATION等）の`archetype_details.archetype_id.value`を、`archetype_node_id`
     とは別に必ず設定する（`OpenehrRails::Rm::EntryNode`が`archetype_id`のpresenceを検証するため）
   - `origin`（HISTORY）・`time`（POINT_EVENT等）は`{"value" => "...", "_type" => "DV_DATE_TIME"}`
     形式のHashで渡す（プレーン文字列不可）
   - ただし`Opt::CompositionBuilder`経由（Anlageの実フォーム保存経路と同じ）で構築する場合は、
     これらのAPI要件はビルダー内部で吸収されるため、シード側で意識する必要はない。**案Aの
     実装では`Opt::CompositionBuilder`経由を優先し、手作業canonical hashは避ける**（実物主義・
     実パイプライン踏襲の趣旨に沿う）
4. **案Bファイルの削除**: `spec/demo/support/height_seed_provisional.rb`と、`spec/demo/
   aql_queries_spec.rb`内の「暫定・実パイプライン非経由」describe/コメントを削除し、案Aの
   シードを指す形に書き換える（新規specへの全面置換でよい。差分は1コミット）
5. **`docs/demo/aql-queries.md`更新**: 1節の「シード（案B暫定）」の記載を実OPT駆動の内容に
   差し替え、冒頭の「案A到着後、シードを差し替える」という前置きを削除する
6. **凍結受入条件への算入**: 上記1〜5完了後にのみ、height不等号クエリが`CLAUDE.md`
   マイルストーン節の受入条件（5節）に算入される

**チェックリスト**（案A移行コミットのレビュー観点）:
- [ ] 検収記録（language-policy 5節）が残っているか
- [ ] fixtureに出所コメントが付いているか
- [ ] 案Bのファイル（`height_seed_provisional.rb`等）が削除されているか
- [ ] `docs/demo/aql-queries.md`の「案B暫定」表記が除去されているか
- [ ] `bundle exec rspec spec/demo/`がgreenか
- [ ] `Opt::CompositionBuilder`経由（手作業canonical hashを避けている）か

## 3. `docs/demo/aql-queries.md`の構成案

デモ使用クエリ全件を期待件数付きで固定する。1本目はheight不等号クエリ（原文は人間供給、下記4節参照）。

```markdown
# デモ使用AQLクエリ一覧

各クエリは `spec/demo/aql_queries_spec.rb` で全実行され、期待件数と照合される。
クエリ本文の変更はこのファイルへの追記・修正を経て行う（壇上での手打ち編集はしない）。

## 1. height不等号クエリ
- 由来: 医療情報学連合大会チュートリアル、事故再発防止の直接対象
- クエリ: <人間供給待ち。以下は実測済みの参考形（gem側spec、openehr-rails/spec/openehr_rails/aql/executor_spec.rb:10-13,26）>
  ```
  SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height
  FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
  WHERE o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude > 170
  ```
- 期待件数: <シード件数確定後に記入>
- pathcards照合: `Template.find_by(template_id: "...").pathcards`に上記パスの`identity`が実在することをspec setupでpinする

## 2. （以降、人間供給のクエリを追加）
```

## 4. `spec/demo/`の構成案

```
spec/demo/
  aql_queries_spec.rb   # docs/demo/aql-queries.md を読み込み、シード投入→全クエリ実行→件数一致を検証
  seeds/                # 案A: OPT登録+Composition構築ヘルパー。案B: Storableモデル定義（暫定）
```

- `bundle exec rspec spec/demo/` が「デモリハ」を代替する
- 1クエリ=1 `it`（`docs/demo/aql-queries.md`をパースして動的に`it`を生成する形、またはYAML/JSONに分離してデータ駆動にする形のどちらかをTDD着手時に確定する）
- 期待件数はマジックナンバーを避け、シード投入件数から導出できるものは導出し、導出できない（クエリ固有のWHERE条件による絞り込み等）ものは明示的にコメントで根拠を書く

## 5. 凍結受入条件への接続

`CLAUDE.md`「進行中のワークストリーム」節（マイルストーン行）に以下を追記する（**承認後、別コミットで実施**。本計画文書はdocsのみで実施しない）:

```
- 11/5凍結の受入条件: `bundle exec rspec spec/demo/` green（デモクエリ全件の期待件数一致）
```

## 6. TDD手順・コミット分割案

1. `docs/demo/aql-queries.md`骨格作成＋案Bの暫定シード＋height querying spec 1件（Red→Green）。人間供給のクエリ原文が届く前でも、gem側spec実測値を参考形として使い、着手できる
2. 案Aのfixture到着後、seedsを案Aへ差し替え（Red→Green、docsのみのコミットにはしない——シード変更はコードレベルの変更のため）
3. 人間供給の残りクエリを`docs/demo/aql-queries.md`へ追記するたびに、対応する`it`を追加（1クエリ=1コミット、Red→Green）
4. `CLAUDE.md`マイルストーン節への受入条件追記（docsのみ、最後）

## 7. 承認が必要な判断

1. **シード設計**: 案A（実OPT駆動、推奨）を採用し、height.v2 OPT到着までは案B（Storable直接定義）を暫定シードとして先行着手してよいか
2. **height.v2 OPTの入手**: CKM/Archetype Designer経由での入手を人間に依頼してよいか（実物主義。捏造不可）
3. **デモ使用クエリ全件の原文**: height不等号クエリ以外のクエリ本文は本計画では未供給。人間から順次供給いただき、供給されたものからTDDサイクルを回す運用でよいか
4. **凍結受入条件への追記文言**（5節）: この文言・追記位置でよいか
