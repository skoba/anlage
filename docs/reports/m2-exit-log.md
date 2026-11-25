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

## R2 E（`skoba/anlage#119`）: 帳票の入力欄をルートごとにまとめる（2026-11-24）

ブランチ `feat/119-form-roots`。基準点は main `e492e32`（C まで入っている）。

### 実測（R-20261124-5 問い 5 の「13 ルート」の数え方）

- jp_referral のパスカードは 26 枚、帳票の入力欄（`values[...]` のうち `__` の補助を除く）も 26 個で、一致している
- ロードマップの「13 ルート」は、テンプレートのルート（COMPOSITION）を除いた C_ARCHETYPE_ROOT の数と一致する:
  SECTION 1（紹介状の詳細情報）、ENTRY 5（サービス依頼・傷病名・既往歴及び家族歴・症状経過及び検査結果・治療経過）、
  CLUSTER 7（紹介元医療機関・紹介先医療機関・住所・電子的な連絡先・医師・診療科・担当医）。`Opt::RootTerms` で数えた

### 自己承認した判断

1. **入れ子の作り方は `Opt::FormLayout`（新規）**。SECTION は field の path から（名前は `section_labels`）、ENTRY は entry の並び
   （名前は entry の `label`）、埋め込み CLUSTER は C で入れた `root_chain`（インスタンスと名前）から作る。新しい登録時の情報は足していない
2. **見た目は fieldset と legend**。配置と名前までにして、デザインはしない（M3 の計画書 6 節と同じ方針）
3. **取り込みの確認画面（`templates/preview`）は変えていない**。登録の前で、`root_chain` がまだ無い経路もあるため
4. 新しい固定の文言は無い（legend はテンプレート上の名前）ので、`docs/demo/ui-vocabulary.md` は変えていない

### Red（実装の前、8 例 4 失敗。「入力欄 26 = パスカード 26」は実装の前から緑で、pin として残した）

```
1) 帳票のルートごとのまとまり（#119） SECTION も埋め込みルートも無いテンプレート（ProblemList）は、ENTRY の fieldset 1 つ
     expected: [["プロブレム・診断", []]]
          got: []
2) … jp_referral ルートの入れ子が SECTION → ENTRY → CLUSTER の順に fieldset になり、テンプレート上の名前が legend になる
3) … 同じアーキタイプの 2 つのルートの項目は、それぞれのルートの fieldset に入る
     expected: ["紹介状の詳細情報", "サービス依頼", "紹介元医療機関"]
          got: []
4) 統合レイアウト（実ブラウザ） jp_referral の帳票（ルートの入れ子が深い）でも、横スクロールが出ない
     expected to find css "fieldset.root-group legend" but there were no matches
```

### Green

- 開発機の全 suite: 390 例 0 失敗、2 pending。rubocop 違反なし、brakeman の警告 0
- 実ブラウザ（1280×720）で、jp_referral の帳票（入れ子 5 段）に横スクロールが出ない

## R3 I（M2 の出口の system spec）: ゲート報告（2026-11-24）

ブランチ `wip/i-referral-exit`（draft PR）。基準点は main `7011c22`（E まで入っている）。

### 何が起きたか

`spec/system/demo_referral_spec.rb`（新規）で、計画書の I のとおり「サービス名・紹介元・紹介先・傷病名」を入力して保存すると、
**422 で保存できない**。必須の検証に、次の 3 項目で止まる（実測、POST で同じ値を送って確かめた）:

| 項目 | 入れ物 | 要素の下限 | 入れ物の occurrences |
|---|---|---|---|
| 電子的な連絡先／値（`electronic_communication_at0002`） | 埋め込み CLUSTER（紹介元医療機関の中） | 1 | 0..1 |
| 症状経過及び検査結果（`clinical_synopsis`） | EVALUATION | 1 | 0..1 |
| 治療経過（`clinical_synopsis_2`） | EVALUATION | 1 | 0..1 |

原因は `#34` の規則「要素自身の occurrences の下限が 1 以上なら必須」（`app/models/template.rb` の `serialize_entry`、
`app/lib/opt/form_validator.rb:34`）。openEHR の意味は「**入れ物を書くなら**その要素は必須」で、入れ物が 0..1 なら、
入れ物ごと書かないことは許される。いまの規則は、入れ物を書かない場合も必須にしている。
（openehr-rails 0.9.0 の CHANGELOG も「mandatory if the entry is written at all」と書き、条件つきの必須は rails の #65 で扱うとしている）

### 実測: 入れ物の occurrences

- jp_referral: COMPOSITION 1..1 のほかは、SECTION・ENTRY 5 つ・CLUSTER 7 つがすべて 0..1（診療科の organisation だけ 0..*）
- ProblemList: COMPOSITION 1..1、problem_diagnosis（ENTRY）0..1

### 裁定を求める点

規則を「入れ物を書くなら必須」に改めるかどうか。利用者に見える結果が変わる:

| 案 | 何が変わるか |
|---|---|
| **A. 入れ物（ENTRY・埋め込み CLUSTER）に 1 つでも値があるときだけ、その中の下限 ≥1 の要素を必須にする（推奨）** | jp_referral は、書いた部分だけの入力で保存できる。**ProblemList は傷病名が空でも保存できる**（ENTRY が 0..1 なので、何も書かなければ ENTRY ごと書かない）。そのとき Composition の content は空になる。`#34` の pin「必須の傷病名が空なら 422」を変える |
| B. A に加えて、帳票全体で値が 1 つも無ければ保存させない | ProblemList の空の保存は止まる（「何か入力してください」）。傷病名だけ空で発症日だけ書いたときは、A と同じく傷病名で止まる |
| C. いまの規則のまま。I の spec は 3 項目も入力する | コードは変わらない。紹介状を書くたびに、連絡先の値と 2 つの経過を必ず書かせることになる |

推奨は B（A の正しさと、空の記録を作らない安全さの両方）。

### 待っているあいだ

- I の spec はこのブランチに置いたまま（いまは赤）。答えが出たら、A／B なら Red から規則を直し、C なら spec に 3 項目を足して緑にする
- 作業列の次（3: 版の公開待ち、4: M3 の残り）には進める

## R4（2026-11-25）I: 必須の規則を案 B で実装（R-20261125-1）

裁定 R-20261125-1 で案 B。規則は `docs/design/required-rule.md` に書いた。

### 実測: C_ARCHETYPE_ROOT の occurrences（テンプレートのルートを除く）

`Opt::SafeParser` で 6 つの fixture を読んで、`CArchetypeRoot#occurrences` を出した（rails runner）。
OPT から ENTRY・CLUSTER の両方の下限が取れる（取れない種類は無かった。`docs/upstream-candidates.md` への追記は無し）。

- CardiologyEncounter: blood_pressure 0..1
- LabResultReport: laboratory_test_result 0..1、laboratory_test_analyte（CLUSTER）0..1
- ProblemList: problem_diagnosis 0..1
- bmi_calculation: height・body_weight・body_mass_index 0..1
- jp_referral: SECTION 0..1、ENTRY 5 つ 0..1、CLUSTER 7 つ 0..1（診療科の外側の organisation だけ 0..*）
- patient_blood_pressure: heart_rate-pulse・blood_pressure 0..*

下限 ≥1 の入れ物は無い。規則 3-2 は合成の field の単体 spec で確かめる。

### 判断（自己承認、裁定の範囲内）

- 入れ物の下限は gem の entry の occurrences ではなく、OPT の C_ARCHETYPE_ROOT から一律に取る（ENTRY と CLUSTER を同じ経路で）。`Opt::ElementRoots` の各ルートに 4 つめの要素として足した
- 入れ物のインスタンスの key は「OPT 上の path#出現順」（`Opt::RootTerms` と同じ数え方）。紹介元と紹介先の organisation を区別する
- `containers` の無い field（古い登録）は従来の規則のまま（黙って任意にしない）
- 印: 常に書かれる枠の中の必須は「*」、任意の枠の中の必須は「※」（title「この枠に書くなら必須」）、帳票の先頭に凡例。捨てた案: fieldset の legend に「任意の枠」と書く（印が項目から離れ、どの項目が条件つきか分からない）
- 「値」に単位（`__units`）は数えない。単位が 1 つの数量は hidden で常に送られるため（`app/views/templates/_field.html.erb`）、数えると帳票全体が空でも「書かれた」になる

### Red

```
$ bundle exec rspec spec/lib/opt/required_rule_spec.rb spec/models/template_spec.rb -e "R-20261125-1" -e "入れ物を書くなら必須"
14 examples, 12 failures
（KeyError: key not found: "containers"／required_rule の 9 例が失敗）

$ bundle exec rspec spec/requests/compositions_blank_fields_spec.rb spec/requests/form_roots_spec.rb
9 examples, 2 failures
  expected ... to include "値が 1 つも入力されていません"
  expected "プロブレム・診断名 *" to include "※"
```

I の実ブラウザ spec（`spec/system/demo_referral_spec.rb`）は R3 から赤のまま。

### Green

全 suite（開発機）: `441 examples, 0 failures, 2 pending`（pending は人間供給待ちの既存 2 件）。
`spec/system/demo_referral_spec.rb`・`spec/system/demo_problem_list_spec.rb` も green。

`#34` の pin は書き換えた（`spec/requests/compositions_blank_fields_spec.rb`）: 発症日だけ書いて傷病名が空なら 422（項目のエラー）、全部が空なら 422（帳票のメッセージ、項目のエラーは出さない）。
