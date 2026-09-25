# 計画: 外部用語束縛の DV_CODED_TEXT がフォームで空 select になる（`skoba/anlage#33`）

- Issue: `skoba/anlage#33`（problem、解決形 (a) bug）。関連: `#23`（jp_referral の受入）、`#30`（保存経路の INSTRUCTION 未対応——本件とは別）
- 状態: **実装済み**（2026-09-25 裁定 A〜D。A は「rm_type 書き換え」不採用→ `input_kind` を唯一の方針属性として登録時に一度だけ導出、B は coded_manual の code 未入力を validation error、C・D 承認）。as-built はコミット `94b59fd`・`99f2298`、`docs/reports/referral-intake-log.md` R12
- 指示（2026-09-25、統括）: explore → 修正（anlage 側で可能なら anlage）→ 実ブラウザ system spec 1 本 → backlog 相互参照

## 0. 探索結果（実測、file:line）

1. **描画層は anlage**: `app/views/templates/_field.html.erb:18-24`。`field["rm_type"] == "DV_CODED_TEXT"` で無条件に `<select>`、options は `field["code_list"]` のみ。`forms/show.html.erb:5-8` が `@template.fields` を回してこの partial を描く。
2. **field の由来は gem**: `Template.build_web_template`（`app/models/template.rb:63-69`）が `OpenehrRails::Opt::FieldExtractor#entries` をそのまま JSON 化。gem の `value_constraint`（openehr-rails 0.7.0 `lib/openehr_rails/opt/field_extractor.rb:179-187`）は代替制約から `C_CODE_REFERENCE` を持つものを主型に選び（[0.5.0] の変更）、`coded_text_constraints`（`:200-210`）が `code_list: []`／`value_set_uri` を返す。**DV_TEXT 代替の存在は field に無い**（実測: ProblemList／jp_referral の at0002 field = `rm_type DV_CODED_TEXT, code_list [], value_set_uri ICD-11, code_bindings []`）。
3. **代替の実態**: パスカード v1.2 で両 at0002 とも `rm_type_alternatives: [DV_TEXT, DV_CODED_TEXT]`（`Opt::PathcardExtractor#value_attribute_children`、`app/lib/opt/pathcard_extractor.rb:133-138`。同じ走査で anlage 側から代替を取れる）。
4. **下流**: `Opt::FormValidator#coded_text_error`（`app/lib/opt/form_validator.rb:58-62`）は code_list が空なら nil（素通し）。`Opt::CompositionBuilder#build_value`（`app/lib/opt/composition_builder.rb:141-150`）は DV_CODED_TEXT 分岐で raw 値を `code_string` に、terminology `local` の DvCodedText を組む——`spec/demo/aql_queries_spec.rb:37,115` は POST 直叩きでこの経路を通っていた（壇上のブラウザ操作は未検証）。
5. **退行の有無**: ProblemList も同症状 → 退行ではなく、[0.5.0] の C_CODE_REFERENCE 優先以降の既存挙動（anlage の bump は 2026-08-26）。
6. **system spec の現状**: `spec/system/forms_spec.rb` は rack_test（patient_blood_pressure、数値 3 項目）。`js: true` の system spec は dropzone 系 4 本（`spec/rails_helper.rb:87-88`、selenium_chrome_headless）で、フォーム入力→保存→AQL の実ブラウザ操作列は無い。
7. **既存 fixture に「コード化必須（DV_TEXT 代替なし）＋外部値集合」の ELEMENT は無い**（dev 全 active テンプレートの DV_CODED_TEXT で code_list 空は at0002 の 2 件のみ、どちらも DV_TEXT 代替あり）。この分岐は partial 単体（field ハッシュ）と builder（crafted web_template）で固定する。
8. **再構築の必要**: web_template は登録時に固定される。同一 checksum の再投入は `TemplatesController#create:69-71` で「already registered」→ 再構築されない。dev／デモ DB の既登録テンプレートに修正を効かせるには rake が要る。
9. **AQL への影響**: 保存値が DV_TEXT になる。`spec/demo/` の 4 クエリは at0002 を SELECT／WHERE に使っていない（クエリ 2 は at0073、4 は at0003）。`ProfileGenerator`／FSH は OPT を読むので無関係。`Opt::CompositionReader`（composition ドロップの表示）は実装時に実測。

## 1. 設計（anlage 側で完結、gem は変更しない）

**A. web_template の補強（登録時）** — `Template.build_web_template` で、gem の field に anlage 側の 2 キーを additive に足す:

- `rm_type_alternatives`: OPT を `PathcardExtractor#value_attribute_children` と同じ規則で走査し、field `path` をキーに引く（新ヘルパー `Opt::ValueAlternatives.call(opt)` → `{ path => [rm_type, ...] }`。path 書式は FieldExtractor と PathcardExtractor（#29 後）で一致——実測済み）
- `input_kind`: `"text"`（DV_TEXT 等）／`"select"`（code_list あり）／`"coded_free"`（code_list 空・value_set_uri あり・DV_TEXT 代替**あり** → **rm_type を "DV_TEXT" に書き換え**、元の主型を `coded_alternative: "DV_CODED_TEXT"` に退避）／`"coded_manual"`（code_list 空・DV_TEXT 代替**なし** → rm_type は DV_CODED_TEXT のまま）

rm_type を書き換えるので view／validator／builder は既存の DV_TEXT 分岐がそのまま効き、保存値は DV_TEXT（OR 制約の正規の一方）。

**B. view（`_field.html.erb`）** — `coded_manual` の分岐を追加: テキスト入力＋「用語サービス未接続（${value_set_uri}）。コードが分かる場合は system／code を入力」＋任意欄 `values[<name>__system]`／`values[<name>__code]`。select 分岐は code_list がある時だけ。

**C. builder／validator** — `coded_manual`: code があれば `DvCodedText(value: raw, defining_code: code@system)`（system 既定は value_set_uri）、無ければ現行どおり raw を code にした DvCodedText（挙動不変、暫定）。validator は変更なし。

**D. rake `templates:rebuild_web_template`** — 全テンプレートの `web_template` を `source_xml` から再構築（checksum 不変）。dev／デモ DB に修正を効かせる手段。

**E. system spec（実ブラウザ）** — `spec/system/demo_problem_list_spec.rb`（`js: true`）: `/forms/ProblemList` を開く → 傷病名（text）・発症日時・臨床的に認識された日時・治癒日時・診断確度（select「疑い」）を入力 → 送信 → composition ページ表示 → `OpenehrRails::Aql::Executor` でクエリ 2 と同じ MATCHES を実行し 1 行。壇上の操作列の固定。

**F. backlog** — 13 項「外部用語のコード化入力（ICD-11 検索）は WP5／$lookup（12 月）」、schema v1 の `display: null`／WP2 $lookup 境界と相互参照。

## 2. テスト TODO（TDD、解決形 (a)）

- [ ] Red: request spec「GET /forms/ProblemList と /forms/jp_referral の `problem_diagnosis_at0002` が `input[type=text]` である」（現状 select）→ Green（A＋B の coded_free）
- [ ] Red: `Opt::ValueAlternatives` spec（ProblemList at0002 → [DV_TEXT, DV_CODED_TEXT]、at0073 → [DV_CODED_TEXT]）→ Green
- [ ] Red: Template spec「build_web_template が input_kind／rm_type_alternatives を付け、coded_free は rm_type DV_TEXT」→ Green
- [ ] Red: partial spec（field ハッシュ直渡し）「coded_manual は text＋注記＋system/code 欄」→ Green
- [ ] Red: builder spec「coded_free は DV_TEXT で保存」「coded_manual は code 指定で DvCodedText(code@system)」→ Green
- [ ] Red: rake spec「templates:rebuild_web_template が既登録テンプレートの field を更新し checksum 不変」→ Green
- [ ] system spec（E）。selenium はローカルでも動く（既存 js: true 4 本が全 suite で green）
- [ ] 全 suite green・rubocop 0。`spec/demo/` 4 クエリが緑のまま（at0002 の保存型変更の非影響を確認）
- [ ] docs: backlog 13 項、upstream-candidates 19（FieldExtractor が代替型を field に載せない／code_list 空のときの主型選択——gem 側で解くならこの 2 点、還流候補として記録）、intake-log R11 で dev の rebuild 実施

## 3. 承認が要る判断

- **A**: rm_type の書き換え（coded_free → DV_TEXT）で進めてよいか。代案は rm_type を保ち view／validator／builder の 3 箇所に `input_kind` 分岐を足す（保存値は同じ DV_TEXT）。書き換えの方が変更箇所が少なく、web_template を読む側（`Opt::CompositionReader` 等）も自然に DV_TEXT として扱う
- **B**: coded_manual の暫定保存（code 無しなら raw を code にした DvCodedText、現行挙動）を許容するか。fixture に該当 ELEMENT が無く、デモ動線にも無い
- **C**: rake `templates:rebuild_web_template` を入れるか（dev／デモ DB の既登録分に効かせる唯一の手段。運用は opt-catalog の版管理規約に追記）
- **D**: system spec は `js: true`（selenium）で 1 本。CI の test ジョブ時間が伸びる（既存 4 本＋1）
