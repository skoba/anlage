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
