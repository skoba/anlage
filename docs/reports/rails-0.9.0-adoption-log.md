# openehr-rails 0.9.0 の受け入れ（M2 の F）: 進行ログ

計画: `docs/design/m2-plan.md` の F（承認済み、R-20261124-5）。作業列: R-20261124-10 の 6。
（`docs/reports/m2-log.md` の末尾は、人間のマージ待ちの PR #105 が触っていて競合するので、ファイルを分けた）

## R1 `skoba/anlage#111`: 0.8.0 → 0.9.0（2026-11-24）

ブランチ `chore/111-openehr-rails-0.9.0`。基準点は main `0993e4c`。**マージは人間**（依存を変える PR）。

### 着手の条件（実測）

- RubyGems の openehr-rails 0.9.0: sha256 `2437f1c4644e3efd23f80ca760c35055f23d1cf441356a12bc796a5b2da75b2d`
  （`https://rubygems.org/api/v1/gems/openehr-rails.json`、公開は 2026-11-24T13:10:29Z）
- 台帳の R-20261124-13 の行に記録された値と一致
- 実行時の依存: `openehr ~> 2.5`（0.8.0 は `~> 2.3, >= 2.3.1`）、`nokogiri >= 1.10`、`rails >= 7.0, < 9.0`。
  anlage の lock は openehr 2.5.0 なので、そのまま解決できる

### `Gemfile.lock`

openehr-rails の 3 行だけを書き換えた（版、依存の行 `openehr (~> 2.5)`、checksum）。`bundle install` は lock を変えずに通った。

### Red（lock を 0.9.0 にした直後、全 suite 291 例 10 失敗）

原因は 2 つ:

1. **9 件: ProblemList が閲覧専用になった**。0.9.0 の `FieldExtractor` は ENTRY の protocol 配下も辿る
   （CHANGELOG の「`problem_list.opt` gains `problem_diagnosis_at0070` (最終更新日, under `protocol[at0032]`)」）。
   builder は data と protocol にまたがる entry を組めず、登録時の判定が preview_only になった:
   ```
   Template#36 form_capability ProblemList は saveable
     expected: ["saveable", nil]
          got: ["preview_only", "entry openEHR-EHR-EVALUATION.problem_diagnosis.v1 fields span more than one branch ([[[\"data\", \"at0001\"]], [[\"protocol\", \"at0032\"]]])"]
   ```
   連鎖して、デモクエリ 2・5、`#34` の空欄の spec 3 件、UI 語彙の「保存」ボタン、実ブラウザの ProblemList の動線、`demo:reset` が落ちた
2. **1 件: FSH の regression pin**。jp_referral の service_request の葉が 0 → 20
   （0.9.0 の「`INSTRUCTION` ... 0 fields before, 20 now」）

### 自己承認した判断

1. **builder が ENTRY の protocol を組むようにした**（OBSERVATION と EVALUATION。CARE_ENTRY の `protocol` 属性、
   openehr 2.5.0 `lib/openehr/rm/composition/content/entry.rb:69-71`）。
   - 理由: 組まないと、壇上の ProblemList の帳票が閲覧専用になる（デモ Q2・Q5、実ブラウザの動線が落ちる）。
     F（0.9.0 の受け入れ）の範囲で、0.9.0 が出す項目を保存できるようにするのは必要な追随と判断した
   - 計画書の F の一覧には protocol が書かれていなかった。**計画書に書いていない挙動の変更**に当たりうるので、ここに明記する。
     統括が差し戻すなら、protocol の項目を帳票から隠す案（`web_template` から外す）に切り替えられる
   - 規則: protocol は、値が入った要素があるときだけ付ける。protocol だけに値があるときは、data を要素の無い ITEM_TREE にする
     （入力を捨てない）。ADMIN_ENTRY と、data・protocol 以外の属性に値があれば `UnsupportedShape`（閲覧専用になり、理由が出る）
   - reader も protocol の要素を読み戻す
2. **FSH の pin は、0.9.0 の実測値（葉 20）に追随した**。ServiceRequest の写像表はまだ無く、skip-and-report に載ることは変わらない
3. **迂回の撤去は、この PR に混ぜていない**（2.5.0 のときと同じ。次の PR）。対象は R2 に書く
4. **engine の layout を確かめた**（`#95` の確認項目）: 0.8.0 と 0.9.0 の `app/views/layouts/openehr_rails/application.html.erb`、
   `app/views/openehr_rails/queries/show.html.erb` は差分なし。anlage の上書きはそのまま使える
5. **`README.md` の依存の行を 0.9.0 に直した**

### Green

- 開発機の全 suite: 296 例 0 失敗、2 pending（手写像の元が未供給の 2 件）。rubocop 違反なし、brakeman の警告 0
- 新しい spec（`#111 ENTRY の protocol`、5 例）のうち 4 例は実装の前に Red を確かめた:
  ```
  1) … ProblemList は protocol 配下の field（最終更新日）を持ち、保存可能のまま
       got: ["preview_only", "entry openEHR-EHR-EVALUATION.problem_diagnosis.v1 fields span more than one branch …"]
  2) … data と protocol の両方に値があれば、data の ITEM_TREE と protocol の ITEM_TREE を別々に組む
       Opt::CompositionBuilder::UnsupportedShape: … fields span more than one branch …
  3) … protocol だけに値があるときも、入力を捨てない（data は要素の無い ITEM_TREE）
       expected: "at0001"
            got: "at0032"
  4) … 組んだ Composition を RM グラフにコミットでき、reader が protocol の値も読み戻す
       Opt::CompositionBuilder::UnsupportedShape: … fields span more than one branch …
  ```

### 開発機のデータ

- 登録済みのテンプレートの `web_template` は登録時のまま（0.8.0 で作ったもの）。新しい項目（最終更新日、jp_referral の 20 項目）を
  出すには `rake templates:rebuild_web_template`。セッションは実行していない

## R2 `skoba/anlage#111`: 0.9.0 で要らなくなった迂回の撤去（2026-11-24）

ブランチ `chore/111-remove-field-workarounds`（R1 のブランチの上に積んだ。PR の base は R1 のブランチ）。
**マージは人間**（ファイルの削除が主な中身。R1 のあと）。

### 実測（撤去の前）

0.9.0 の `FieldExtractor` の素の出力と、anlage が訂正したあとの `web_template` の field を、6 つの fixture で比べた:

| キー | 結果 |
|---|---|
| path、name、archetype_id、root_path | 6 つすべてで一致（上流候補 22 項） |
| rm_type_alternatives | 一致（19 項） |
| min_occurrences | 一致（20 項） |
| units_list | 数量の field は一致。数量でない field は gem が nil、anlage が `[]` |
| required | 違う（gem は意味を変えていない。anlage の規則を残す） |
| label | jp_referral の 1 つめの clinical_synopsis だけ違う（gem は後勝ちで「治療経過」、anlage は「症状経過及び検査結果」） |

### 撤去したもの

- `app/lib/opt/element_constraints.rb`（OPT を自前で辿って、代替型・下限・単位・path の対応表を作っていた）
- `app/lib/opt/value_alternatives.rb` と、その spec（期待値は `spec/models/template_spec.rb` に移した）
- `Template.serialize_entry` の path の訂正（`by_gem_path`）と、`rewrite_embedded_field` の name・archetype_id・root_path の書き換え。
  残したのは anlage の規則だけ（required、インスタンス別の label、root_label、input_kind、units_list の空配列）

### TDD

この PR は振る舞いを変えない撤去（Refactor）。先に characterization の spec（「#111 web_template の field は 0.9.0 の FieldExtractor の値を
そのまま使う」、9 例）を足し、撤去の前に緑であることを確かめてから撤去した。撤去のあとも緑。golden 4 件と既存の `template_spec.rb` は無変更で緑

### Green

- 開発機の全 suite: 303 例 0 失敗、2 pending。rubocop 違反なし

### F のうち、この 2 つの PR に入れていないもの

- 16 項（context）: 0.9.0 で `context` が永続化されるようになった。anlage の builder はまだ `context` を付けない。
  付けるのは設計書（`docs/design/rm-attributes-without-inputs.md`）5 節の 5 で、別の PR。
  ただし 0.9.0 の既知の制限で、`c/context/start_time` は AQL でまだ引けない（openehr の path 評価が EVENT_CONTEXT を辿れない）。
  M2 の計画の「紹介日で引ける」は、openehr の次の版を待つ
- 23 項（FHIR プロファイル id の衝突）: 0.9.0 でも残る（実測）。anlage では直さない

## R3 `skoba/anlage#30`（M2 の D）: INSTRUCTION と多段 CLUSTER（2026-11-24）

ブランチ `feat/30-instruction`（R2 のブランチの上に積んだ）。裁定: R-20261124-5（timing・action_archetype_id）、R-20261124-14（narrative は案 B）。

### 自己承認した判断

1. **narrative の区切りは全角のセミコロン「；」**。改行でつなぐ案で実装したところ、DV_TEXT が改行を拒否した
   （`ArgumentError: value is not valid`、openehr 2.5.0 `rm/data_types/text.rb:102-106`。RM の不変条件）。
   決めた規則は設計書 6 節に書いた
2. **action_archetype_id は既定値 `/.*/` だけ**。OPT の制約から取る処理は書いていない。手元の実物の OPT 6 つには
   制約を持つものが無く（`grep -c action_archetype_id spec/fixtures/opt/*.opt` がすべて 0）、テストできない（実物主義）。
   **人間への依頼**: ACTIVITY に action_archetype_id の制約を持つ OPT が 1 つあれば、制約から取る処理を足す
3. **多段の埋め込み CLUSTER**: 骨格（ITEM_TREE まで）は「最初の埋め込みルートより手前」の segment とし、その奥はルートの並びで
   再帰的に CLUSTER にまとめる。ルートでない途中のノード（アーキタイプ内部の CLUSTER）は、これまでどおり `UnsupportedShape`
4. **保存可否の理由の重複を除いた**（ドライランと `unsupported_reasons` が同じ文を出していた）
5. **既存の spec 2 つを追随**: jp_referral の閲覧専用の理由（INSTRUCTION が消え、field 名の衝突 3 件だけ）。
   `#80` の pin「B だけでは保存可能に変わらない」は、理由の中身を変えて残した（C が済むまで閲覧専用のまま）

### Red（実装の前、8 例 6 失敗）

```
1)〜5) Opt::CompositionBuilder#30 INSTRUCTION と多段 CLUSTER …（5 例）
     Opt::CompositionBuilder::UnsupportedShape: entry rm_type INSTRUCTION is not supported yet
6) Template#36 form_capability jp_referral は、SECTION 配下の ENTRY と INSTRUCTION を組めるようになっても preview_only のまま（field 名の衝突）
     （理由に "entry rm_type INSTRUCTION is not supported yet" が残っていた）
```

### Green

- 開発機の全 suite: 309 例 0 失敗、2 pending。rubocop 違反なし
- 組んだ Composition を RM グラフにコミットし、`i/activities[at0001]/description[at0009]/items[at0062]/value/value` を AQL で引けた

### 見つけたもの（C で扱う）

- **2 つめの organisation（紹介先医療機関）の field の root_label が「紹介元医療機関」になる**。root_label を
  `terms.fetch(root_path).first`（同じ path の最初のルート）から取っているため。0.9.0 の field は `instance_index` を持つので、
  C（同じアーキタイプの複数ルートの区別）で、ルートのインスタンスに結び直す
- **reader（記入済みの帳票）は INSTRUCTION と多段 CLUSTER をまだ読み戻さない**。jp_referral が保存可能になる C のあとに足す

### Issue

- `#30` は開けたまま（reader と、C のあとの保存の通しが残る）
