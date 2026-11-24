# openehr 2.5.0 の受け入れの棚卸し（計画）

裁定 ID: R-20261124-3（1 節）。状態: **案**。承認までは bump も実装もしない。

- anlage の基準点: main `86720a5`。`Gemfile.lock` は openehr 2.4.3、openehr-rails 0.8.0
- 読んだ上流（読み取りのみ。相手のツリーでは何も実行していない）:
  - openehr-ruby の手元のツリー `/home/skoba/src/openehr-ruby`、`ec07936`（#60 `0ef5b33`、#31 `c21af74`、#43 `ec07936`）
  - #48 は手元の追跡ブランチ `origin/feat/48-aql-time-hop` の `b8ed350` を読んだ。GitHub の master は
    2026-11-24 に `d5e3a90`（同じ件名のコミット）まで進み、Issue #48 は閉じている（`gh api` で確認）
  - 計画書 `docs/design/round2-2.5.0-plan.md`（`ec07936` 時点）
- 「実測」は anlage のツリーで実行または grep したもの。「推論」は根拠を添える。「未確認」は読むだけでは決まらないもの

## 1. 項目ごとの影響

| 項目 | 上流の状態 | anlage で影響を受ける箇所 | 撤去できる迂回 | bump のとき Red から始める spec |
|---|---|---|---|---|
| #60 name 述語 | master（`0ef5b33`） | `spec/integration/jp_referral_aql_spec.rb:39`・`:55` の `pending UPSTREAM_24`（解消すると pending が失敗に変わる） | pending 2 箇所と定数 `UPSTREAM_24`（`:18`）、冒頭コメント `:9-14` | 「構造骨格（実 at-code）を直接コミットし、紹介先医療機関を name 述語で引ける」（既存。pending を外すと Red になるはずのものが Green になる） |
| #48 イベント時刻 | master（`d5e3a90`） | コードには無い。デモ Q4 の暫定形: `docs/demo/aql-queries.md:76`、`spec/demo/aql_queries_spec.rb:106-117` | 迂回コードは無い。文書と spec コメントの「実行不能」の記述 | 「OBSERVATION のイベント時刻 `events[...]/time/value` の半開区間で期待件数を返す」（新規。Q4 の本来形） |
| #31 term_bindings | master（`c21af74`） | `app/lib/opt/pathcard_extractor.rb:327-345`（`component_terminologies` の `term_bindings` を読む。経路は変わらない） | anlage には無い（`skoba/anlage#19` で撤去済み。同 `:311-326` のコメントを現状に合わせる） | 新規は要らない。regression pin: golden 4 件が変わらないこと |
| #43 path の括弧 | master（`ec07936`） | 2 節。**anlage のコードは gem の `.path` を読んでいない**（実測） | 直接は無い | 新規は要らない。regression pin: golden 4 件と `spec/models/template_spec.rb` が変わらないこと |
| #58 ルート別 term_definitions | **未マージ**（Issue は open、ブランチも無い） | `app/lib/opt/template_terms.rb`（全 67 行）、`app/lib/opt/pathcard_extractor.rb:22`・`:145-166`、`app/models/template.rb:69`・`:105-125` | `Opt::TemplateTerms` と、それを前提にした「path＋出現順」のキー | 「同一アーキタイプ複数インスタンスの ELEMENT 改名」（`spec/lib/opt/pathcard_extractor_spec.rb:476-`）と container_labels（同 `:405-`）を、`source_xml` の再解析なしで通す |
| #49 コード値の終端ホップ | **未マージ**（Issue は open。最小形は `defining_code`・`code_string` の 2 名） | コードには無い。デモ Q2 の暫定形: `docs/demo/aql-queries.md:29`、`spec/demo/aql_queries_spec.rb:52-57` | 迂回コードは無い | 「診断確度を `value/defining_code/code_string MATCHES {...}` で絞れる」（新規。Q2 の本来形） |
| #59 日付のみの DV_DATE_TIME | **2.5.0 に入らない**（上流計画 D5） | `app/lib/opt/composition_builder.rb:232-243`（`instance_variable_set` の迂回） | 2.5.0 では撤去できない。そのまま残す | なし |

補足:

- **#60**: `spec/demo/cross_template_query_spec.rb:6-9` と `docs/demo/aql-queries.md:119-120` は
  「紹介先医療機関で引く形は #60 の解消後」と書いている。デモクエリ 5 を name 述語の形に
  変えるかは M2 の範囲（jp_referral のフォーム保存 `#30` が要る）。bump では文言だけ直す
- **#60 の残り**: name にアポストロフィを含む述語は 2.5.0 でも落ちる（openehr-ruby#65、2.5.0 の外）。
  anlage が使う name（「紹介先医療機関」「紹介元医療機関」）には含まれない
- **#49**: 最小形に `archetype_details/template_id` は入らない（上流計画 3.6）。
  デモクエリ 5 の出所の並記は `c/name/value` のまま（`docs/upstream-candidates.md` 25 項）
- **#31**: openehr-rails 0.8.0 の `populate_term_bindings!` は、上流が `term_bindings` を入れると
  nil ガードで no-op になる（rails 0.8.0 `lib/openehr_rails/opt/parser.rb:57-65`）。
  同じアーキタイプが複数回埋め込まれたときの件数は変わりうる（rails は積み、上流はルートごとに作り直す）。
  anlage の fixture では、`term_bindings` を持つ OPT は `CardiologyEncounter`・`bmi_calculation`・
  `patient_blood_pressure` の 3 件で、golden に binding の重複は 0 件（実測）。影響は出ない見込み（推論）

## 2. #43（path の文字列が変わる）の洗い出し

上流の変更: OPT をパースした制約ノードの `path` で、埋め込み C_ARCHETYPE_ROOT に `[archetype_id]` が付く。
`Archetype#physical_paths`・`#logical_paths` の文字列も変わる（`ec07936` のコミットメッセージ）。

**結論: anlage の path は gem の `.path` から作っていないので、#43 だけでは文字列は変わらない見込み。移行は要らない。**

| 箇所 | path の作り方 | 根拠 |
|---|---|---|
| パスカードの `identity.path` | 自前で連結。埋め込みルートは既に `[archetype_id]` | `app/lib/opt/pathcard_extractor.rb:40`・`:53-62`（`skoba/anlage#29`） |
| golden（4 件、37 枚） | 上の出力そのもの | `spec/fixtures/pathcards/*.golden.json`、`spec/lib/opt/pathcard_extractor_golden_spec.rb` |
| スキーマ v1.2 | path の書式を変える項目は無い | `docs/design/pathcards-schema-v1.md` |
| アーキタイプパスの導出 | `identity.path` と `identity.archetype_id` の文字列操作 | `app/lib/opt/pathcard.rb:8-16` |
| パスカード検索 | 保存済みの `templates.pathcards`（JSON 列）を読む。path では絞らない | `app/lib/opt/pathcard_search.rb:16-17`、`db/schema.rb:169` |
| 帳票の field の path | openehr-rails の `FieldExtractor` の path（埋め込みルートを `items[at0000]` で書く）を、anlage が `[archetype_id]` に訂正して `web_template` に保存 | `app/models/template.rb:138-143`、`app/lib/opt/element_constraints.rb:36-69` |
| 保存時の組み立て | `web_template` の field の path から wrapper を導く | `app/lib/opt/composition_builder.rb:85` |
| テンプレートの差分 | `web_template` の field の path をキーにする | `app/lib/opt/template_diff.rb:22-23` |
| AQL | app のコードは AQL を組まない。AQL の文字列は spec・デモ文書・rake の初期データだけ | `grep` で `app/`・`lib/`・`config/` に `SELECT`／`CONTAINS` が無い |
| 評価のゴールド | `expected_archetype_id` と `expected_at_code` で照合。path を持たない | `spec/fixtures/pathcards_eval_seed.yml`（18 件のキーを実測） |

- anlage の `app/`・`lib/` に、gem の制約ノードの `.path`、`physical_paths`、`logical_paths` の呼び出しは無い（grep、0 件）
- openehr-rails 0.8.0 の `lib/` にも、制約ノードの `.path` の呼び出しは無い
  （grep。`rm_object_builder.rb:19` の `node.path` は保存済みの RM ノードの列で、別物）
- **保存済みのデータ**: `templates.pathcards` と `templates.web_template` は登録時に固定される。
  #43 では作り方が変わらないので、再構築（`pathcards:backfill`、`templates:rebuild_web_template`）は要らない見込み
- **path が変わるのは openehr-rails 0.9.0 の側**: 上流候補 22 項（`FieldExtractor` が埋め込みルートを
  `items[at0000]` で書く）が直ると、`template.rb` の訂正（`by_gem_path`、`rewrite_embedded_field`）が
  二重になる。これは 0.9.0 の受け入れで扱う（本書の範囲外。M2 の計画に書く）

## 3. 未確認（読むだけでは決まらないもの）

bump のときに anlage のツリーで確かめられるもの:

1. #60: openehr-rails 0.8.0 の実行系（`OpenehrRails::Aql::Executor`）を通しても、name 述語が効くか。
   `jp_referral_aql_spec.rb:54-` が bump の直後に「pending が通ってしまう」失敗になれば効いている
2. #43: openehr-rails 0.8.0 の `FieldExtractor` の path が本当に変わらないか。
   `spec/models/template_spec.rb` と golden が無変更で通れば変わっていない
3. #31: `CardiologyEncounter` の code_binding が 2.5.0 でも同じ内容か（golden で分かる）

gem 側に頼む問い:

1. （openehr-ruby）#58 の `CArchetypeRoot#term_definitions` は、同じ path に同じアーキタイプが
   複数回埋め込まれたとき（jp_referral の clinical_synopsis ×2）、ルートごとに別の値を返すか。
   anlage の迂回は「path＋出現順」で引いているので、置き換えの形がこれで決まる
2. （openehr-ruby）#58 は 2.5.0 に入るか。入らないなら `Opt::TemplateTerms` は残す
3. （openehr-rails）0.9.0 は openehr の下限を 2.5.0 に上げるか。上げるなら anlage の bump は 1 回になる

## 4. bump の進め方（案）

1. **openehr 2.4.3 → 2.5.0 だけを先に上げる**（openehr-rails は 0.8.0 のまま。
   0.8.0 の依存は `openehr (~> 2.3, >= 2.3.1)` なので解決できる。`Gemfile.lock:227`）。
   1 Issue = 1 PR、`Gemfile.lock` だけが変わる
   - Red: `jp_referral_aql_spec.rb` の pending 2 件が失敗に変わる → pending を外して Green
   - 新規の spec: Q4 の本来形（#48）。#49 が入っていれば Q2 の本来形
   - regression pin: golden 4 件、`template_spec.rb`、`spec/demo/`、実ブラウザの system spec
2. **openehr-rails 0.8.0 → 0.9.0** は別の PR（M2 の計画で扱う）
3. #58 が 2.5.0 に入っていれば、`Opt::TemplateTerms` の撤去を 1 の次の PR にする（bump と混ぜない）

## 5. 裁定を求める点

1. bump を 2 段（openehr を先、openehr-rails を後）に分けてよいか。
   裁定の背景は「2.5.0 と 0.9.0 が公開されてから」と読める。分けると、#60 の pending 解除と
   Q4 の本来形を 12/5 より前に入れられる
2. デモ Q2・Q4 を本来形に**置き換える**か、暫定形を残して本来形を**足す**か。
   暫定形は 11/5 凍結の受入条件（`spec/demo/` の 4 クエリ）に入っている
3. #58 が 2.5.0 に入らなかった場合、`Opt::TemplateTerms` を残したまま M2 に進んでよいか
