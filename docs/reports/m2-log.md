# M2（書き込みの完成）の進行ログ

計画: `docs/design/m2-plan.md`（承認済み、R-20261124-5）。作業列: R-20261124-10（anlage、書く側）。
進め方: R-20261124-8（`CLAUDE.md`「全開の進め方」）。

## R1 A（`skoba/anlage#54`）: ルートの archetype_node_id と archetype_details（2026-11-24）

ブランチ `fix/54-composition-root-archetype`。基準点は main `6c100e0`。

### 自己承認した判断

1. **ルートの archetype_id は登録時に `web_template["root_archetype_id"]` に入れ、キーが無い登録済みの
   テンプレートでは `source_xml` から引く**（`Template#root_archetype_id`）。
   - 採った理由: `web_template` は登録時に固定され、開発機には #54 より前に登録したテンプレートがある。
     フォールバックが無いと、それらで保存するたびに nil のルートを組む。データの移行は「必ず止まる」に
     当たるので、移行なしで動く形にした
   - 捨てた案: (a) 毎回 `source_xml` を解析する（保存のたびに OPT を解析する。登録時に固定する既存の
     方針と合わない）。(b) `rake templates:rebuild_web_template` を前提にする（開発機のデータを書き換える操作を
     利用者に求めることになる）
   - 根拠（実測）: `Opt::SafeParser.parse(jp_referral.opt).definition.archetype_id.value` は
     `"openEHR-EHR-COMPOSITION.request.v1"`、`definition.rm_type_name` は `"COMPOSITION"`
     （openehr 2.4.3、`lib/openehr/parser/opt_parser.rb:117-119` の `definition` が `c_archetype_root` を返す）
2. **Composition の JSON のドロップ（`TemplatesController#preview_composition`）の照合を
   `archetype_details.template_id` に改め、以前の形も受け付ける**。
   - 理由: これまではルートの `archetype_node_id` を template_id として引いていた
     （`app/controllers/templates_controller.rb:106`）。A のあとは COMPOSITION アーキタイプの ID が入るので、
     そのままだと「記入済みの帳票」のプレビューが必ず失敗する。計画書の「触るファイル」には無いが、
     A の変更がそのまま壊す箇所なので同じ PR で直した
   - 以前の形（`archetype_details` 無し、`archetype_node_id` が template_id）の受け付けは spec で pin した

### Red（実装の前、`bundle exec rspec` 3 ファイル、25 例 4 失敗）

```
1) Opt::CompositionBuilder 日本語前提の既定値 ルート（COMPOSITION） archetype_node_id は COMPOSITION アーキタイプの ID になる（template_id ではない）
     expected: "openEHR-EHR-COMPOSITION.encounter.v1"
          got: "CardiologyEncounter"
2) … archetype_details に archetype_id、template_id、RM version を持つ
     NoMethodError: undefined method 'archetype_id' for nil
3) … root_archetype_id を持たない登録済みの web_template（#54 より前の登録）でも、OPT から引いて組む
     expected: "openEHR-EHR-COMPOSITION.encounter.v1"
          got: "CardiologyEncounter"
4) Forms and Compositions POST /compositions/:template_id フォームから保存すると、RM グラフの template_id 列に template_id が入る
     expected: ["patient_blood_pressure.v1"]
          got: [nil]
```

以前の形のドロップを受け付ける spec は、実装の前から緑（regression pin）。

### Green

- 開発機の全 suite: 249 例 0 失敗、3 pending（pending は `#23` (4) の 3 件で、前から変わらない）
- regression pin: `spec/demo/`、`spec/requests/fhir_profiles_spec.rb`、`spec/tasks/demo_reset_spec.rb` の 11 例 0 失敗
- `spec/tasks/demo_reset_spec.rb` は、RM 側を template_id 列でも見るように足した
  （6 件すべてに template_id が入る。これまでは「nil になる既存の欠陥」と注記していた）

### 開発機のデータ

- 既に登録済みのテンプレートは、そのまま使える（上の判断 1 のフォールバック）
- 既に保存済みの Composition は以前の形のまま残る。新しい形にそろえるには `rake demo:reset`。
  セッションは実行していない（R-20261124-5）

### 残り

- 上流候補 25 項（AQL から `c/archetype_details/template_id/value` に届かない）は別件で、この PR では変わらない。
  `docs/demo/aql-queries.md:116` の「出所の並記は Composition 名」はそのまま
