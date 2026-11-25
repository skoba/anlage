# openehr 2.6.0・openehr-rails 0.10.0 への版上げ: ログ

裁定 ID: R-20261124-20（作業列 3）。Issue: #146。基準点: anlage main `79ebcc4`。

## R1（2026-11-25）版上げ、紹介日、出所の表示

### 版上げ（自己承認。マージは人間: `Gemfile.lock` を変える PR）

- `Gemfile` の制約（`openehr-rails ~> 0.4`）は 0.10.0 を許すので、`Gemfile` は変えない。
- `bundle lock --update openehr openehr-rails --conservative` を試した。
  - lock の PLATFORMS に `ruby` が無いので、Bundler 4.0.18 が汎用 platform の 3 gem
    （nokogiri・sqlite3 の汎用版と mini_portile2）も外した。
  - これまでの版上げ（`cac54bd`・`b8abce6`）は、該当の gem の行だけを変えている。
- 採った案: lock は 2 gem の版と checksum の 4 行だけを変える。
  - `BUNDLE_FROZEN=true bundle install` が通ることを確かめた。
  - checksum は Bundler が解決した値で、台帳に記録された RubyGems の値（`e6c40403…4d410ee4`・`1a31d85e…fa396c1a`）と一致する。
  - 捨てた案: Bundler の出力をそのまま使う。汎用 platform の掃除は、別の変更として切り出すべきだから。

### 版上げだけでの全 suite（Red の記録）

490 examples、6 failures、2 pending。

- 5 件は FHIR の profile id の変更（rails #55、上流候補 23 項）。0.10.0 の CHANGELOG の Upgrade note どおり:
  - `spec/models/template_spec.rb:184`・`:188`
    （例: `expected: ["openehr-evaluation-problem-diagnosis-v1"]`、`got: ["openehr-problemlist-evaluation-problem-diagnosis-v1"]`）
  - `spec/requests/template_detail_spec.rb:80`
  - `spec/tasks/fsh_spec.rb:55`・`:76`
- 1 件は `spec/lib/evaluation/aql_scorer_spec.rb:48`（`expected: :unexecutable`、`got: :mismatch`）。
  - `archetype_details` が例外にならなくなった。
  - 「実行できない」の例を `c/uid/value` に替えた（0.10.0 の Known limitations。実測で `unsupported path attribute "uid"`）。
- 公開している URL への影響: `/fhir/r5/StructureDefinition/<id>` の id が変わる。
  - gem の版上げに伴う変更で、上流 23 項として anlage が求めたもの。
  - anlage の画面のリンクは gem の id から組むので、追随は不要（spec で確かめた）。

### 実測: 出所の表示（template_id）は切り替えられない

`rake demo:reset` の状態で測った。

| AQL | 結果 |
|---|---|
| `SELECT c/name/value, c/archetype_details/template_id/value …` | 6 行とも template_id が `nil` |
| `SELECT c/context/start_time/value …`（anlage の修正前） | 6 行とも `nil` |
| `SELECT c/uid/value …` | `unsupported path attribute "uid"` |

- `Rm::Composition` の `template_id` 列には値がある（6 件とも）。
- AQL は `to_rm` の結果を見る。openehr-rails 0.10.0 `rm_object_builder.rb:74-95` の `build_composition` は
  `archetype_details` を組まない。
- 裁定の「template_id に切り替える」は、ここで止まる。上流候補 25 項に追記した。
- 出所の表示は `c/name/value` のまま。

起票の文面の案（openehr-rails。起票は人間）:

> **AQL `c/archetype_details/template_id/value` returns nil although the composition row has template_id**
>
> With openehr 2.6.0 the path is accepted, but every row returns nil. `Rm::Composition#template_id` is populated
> (GraphBuilder reads `archetype_details.template_id`), but `RmObjectBuilder#build_composition`
> (`lib/openehr_rails/rm/rm_object_builder.rb:74-95`) does not pass `archetype_details`, and the AQL dataset
> walks `to_rm`. Proposal: build an `Archetyped` from `template_id` and `rm_version` in `build_composition`.

### 紹介日（context/start_time）で引ける（Red → Green）

- 規則: `start_time` は保存した時刻（`docs/design/rm-attributes-without-inputs.md` 2 節の規則 4、5 節の 5）。
  - 修正の版は、元の記録の時刻を引き継ぐ。理由: EVENT_CONTEXT は記録した場面の時刻で、修正しても場面は変わらない。
  - 削除の版も、元の記録の時刻を引き継ぐ。
- `setting` は渡さない。
  - OPT 5 本に `context/setting` の制約が無い（`grep '<rm_attribute_name>setting'` が 0）。
  - `config/initializers/openehr.rb` に既定値も無い。
  - コードを選ぶのは意味の判断なので、anlage では決めない。gem が固定の `other` で組む。
- Red（`spec/requests/referral_date_query_spec.rb`）:
  - 期間で絞る例と修正の例は、どちらも `expected: [["2026-04-15T00:00:00Z", …]]`、`got: []`。
  - 削除の例は `expected: 2026-04-15 00:00:00 +0000`、`got: nil`。
- Green:
  - `Opt::RmCompositionCommitter` が `context_start_time:` を渡す（新しい記録は `Time.current`、修正は head の値）。
  - `CompositionsController#destroy` は head の値を渡す。
