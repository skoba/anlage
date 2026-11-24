# M2 の残り（C・E・I）: 進行ログ

計画: `docs/design/m2-plan.md`（承認済み）。作業列: R-20261124-20 の 2。
D までの記録は `docs/reports/rails-0.9.0-adoption-log.md`（R1〜R3）。

## R1 C（`skoba/anlage#117`）: 同じアーキタイプの複数ルートを区別する（2026-11-24）

ブランチ `feat/117-multi-roots`。基準点は main `7e7b1f0`（openehr 2.5.0、openehr-rails 0.9.0、D まで入っている）。

### 実測

- 衝突していた field 名: `organisation_at0001` ×3（紹介元・紹介先・紹介先の中の診療科）、`person_at0001` ×2（医師・担当医）、
  `clinical_synopsis` ×2（症状経過及び検査結果・治療経過）
- OPT を前順に辿った ELEMENT の path（`node.path + "/value"`）は、0.9.0 の FieldExtractor の field の path と同じ書式。
  同じ path の ELEMENT の並びは、field の `instance_index` と一致する（jp_referral の 26 項目）
- ただし OPT には content の外（context）にも ELEMENT がある（LabResultReport）ので、並び順だけで結ぶとずれる。
  最初の実装はこれで LabResultReport の CLUSTER 名を落とした（全 suite で 2 件 Red、下の判断 2）

### 自己承認した判断

1. **field 名の付け方: 文書順で 2 つめ以降に `_2`・`_3`**（1 つめは gem の名前のまま）。openehr-rails 0.8.0 までの
   FieldExtractor の付け方（`…_at0001_2`）にならった。ルートの名前（日本語）から作る案は、form のキーが ASCII でなくなるので捨てた
2. **field と ELEMENT は path と `instance_index` で結ぶ**（`Opt::ElementRoots`、新規）。結べないときは `root_chain` を持たず、
   これまでの組み方（archetype_id だけで CLUSTER をまとめる）に落ちる
3. **web_template の field に `root_chain` を足した**（entry より奥の埋め込みルートの並び。各ルートは archetype_id・インスタンス・
   テンプレート上の名前）。builder はこれで CLUSTER をインスタンスごとに分けて名前を付ける。`root_label` はその末尾の名前
4. **jp_referral は保存可能になる**（R-20261124-5 問い 2 の条件「C と D が済むまで閲覧専用」がそろった）
5. **既存の spec の追随**: jp_referral を閲覧専用として使っていた 3 つ（`forms_capability_spec`、`template_detail_spec`、
   実ブラウザの `demo_pathcard_search_spec`）。手元の実物の OPT はすべて保存可能になったので、閲覧専用の画面の spec は、
   jp_referral の登録時の判定を閲覧専用に書き換えて確かめる形にした。デモの台本の「1' 閲覧専用」は、保存できる帳票に変わる
6. `docs/demo/opt-catalog.md` の jp_referral の保存可否を saveable に直した

### Red（実装の前、`spec/lib/opt/multi_roots_spec.rb` 7 例 7 失敗）

```
1) … field 名が衝突しない。2 つめ以降は文書順に _2・_3 を付ける
     （"clinical_synopsis" が 2 回）
2) … 埋め込みルートの項目は、属するルート（インスタンス）のテンプレート上の名前を root_label に持つ
     RuntimeError: no field organisation_at0001_2
3) … 2 つの clinical_synopsis は、それぞれのルートの名前でラベルされる
     RuntimeError: no field clinical_synopsis_2
4) … jp_referral の帳票は保存可能になる
     got: ["preview_only", "field name organisation_at0001 is shared by 3 fields; field name person_at0001 is shared by 2 fields; field name clinical_synopsis is shared by 2 fields"]
5) … 紹介元と紹介先の organisation を別々の CLUSTER に入れ、診療科は紹介先の中に入れる
6) … 2 つの clinical_synopsis に別の値を入れると、2 つの EVALUATION に分かれて入る
7) … 保存して、紹介先医療機関を name 述語の AQL で引ける
     expected: [["X病院"]]
          got: [[nil]]
```

### Green

- 開発機の全 suite: 385 例 0 失敗、2 pending。rubocop 違反なし

### 残り

- reader（記入済みの帳票）は、INSTRUCTION・多段 CLUSTER・同じアーキタイプの 2 つめの ENTRY をまだ読み戻さない（`#30` に残す）
