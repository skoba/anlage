# 帳票に入力欄の無い RM の属性（設計）

裁定 ID: R-20261124-5（D の設計への条件）、R-20261124-10（作業列 4）。状態: **案**。
6 節の「narrative の作り方」だけはゲート（人間の判断）。ほかは 5 節の順に、この設計書のとおり進める。

- 基準点: anlage main `c09d72f`（openehr 2.4.3、openehr-rails 0.8.0）
- 「実測」は anlage のツリーで実行したもの。gem の行番号は、インストール済みの openehr 2.4.3 の
  `lib/openehr/` からの相対パス（読み取りのみ）

## 1. 何の話か

RM には、アーキタイプの ELEMENT ではないために帳票に入力欄が出ないが、値が要る属性がある
（INSTRUCTION の `narrative`、ENTRY の `language`、HISTORY の `origin` など）。
これは jp_referral に限らない。INSTRUCTION を含むどのテンプレートを取り込んでも同じことが起きる。
そこで、テンプレートごとのコードではなく、**クラスと属性ごとの一般の規則**として決める。

## 2. 値の出どころの規則

属性ごとに、次の順で最初に当てはまるものを使う。

1. **OPT の制約**: OPT がその属性を 1 つの値に絞っていれば、その値（例: `category` の `code_list` が 433 だけ）
2. **テンプレートの用語**: ノードの名前は、OPT の term_definitions のそのノードの text
3. **入力からの組み立て**: 帳票に入力された値から決まるもの（6 節の narrative の候補）
4. **実行時の事実**: 保存した時刻、ログインしている記録者（いまは無い。M3）
5. **設定の既定値**: `config/initializers/openehr.rb`（言語、地域、文字コード、記録者名）
6. **入力欄**: 上のどれでも決まらず、利用者が決めるべきもの。アーキタイプの ELEMENT と同じ帳票に出す

生成系（LLM）は、どの段でも値を作らない（絶対規律 7）。

## 3. 一覧（いまの埋め方は実測）

「必須」は RM 1.0.4 の必須。gem が nil を拒否する箇所を添えた。

| クラス | 属性 | 必須 | いまの anlage の埋め方（実測） | 案（出どころ） |
|---|---|---|---|---|
| LOCATABLE（全ノード） | `archetype_node_id` | ○（`rm/common/archetyped.rb:168`） | path の述語から取る | 変えない |
| LOCATABLE（全ノード） | `name` | ○（同 `:175`） | ノードごとに下の行 | 規則 2 |
| アーキタイプのルート | `archetype_details` | ○（RM の不変条件） | COMPOSITION・SECTION・ENTRY・埋め込み CLUSTER に付ける（`#54`・`#80`・`#38`） | 変えない |
| ARCHETYPED | `rm_version` | ○（同 `:218`） | 定数 `"1.0.4"`（`composition_builder.rb:21`） | 変えない（上流候補 12 項） |
| COMPOSITION | `name` | ○ | OPT の `concept`（例: `jp_referral`） | 規則 2（ルートの at0000 の text）。**5 節の 3** |
| COMPOSITION | `language` | ○（`rm/composition.rb:28`） | 設定 `ja` | 規則 5。変えない |
| COMPOSITION | `territory` | ○（同 `:48`） | 設定 `JP` | 規則 5。変えない |
| COMPOSITION | `category` | ○（同 `:38`） | **値とコードが逆**: `value` が `"433"`、`code_string` が `"event"` | 規則 1（OPT の `code_list`）、無ければ設定。**5 節の 2** |
| COMPOSITION | `composer` | ○（同 `:55`） | 設定 `PARTY_IDENTIFIED`、name は `"unknown"` | M3 までは規則 5。M3（患者と EHR）で規則 4 |
| COMPOSITION | `context`（EVENT_CONTEXT） | event なら要る（`start_time`・`setting` が必須、同 `:87`・`:94`） | **付けていない** | 規則 4（`start_time` は保存時刻）と規則 1（`setting`）。上流候補 16 項が 0.9.0 に入ってから。**5 節の 5** |
| SECTION | `name` | ○ | テンプレート上の名前（`section_labels`、`#80`） | 変えない |
| ENTRY（共通） | `name` | ○ | OPT の concept（英字の識別子。例: `blood_pressure`、`problem_diagnosis`） | 規則 2（ルートの at0000 の text。例: 「傷病名」）。**5 節の 3** |
| ENTRY（共通） | `language` | ○（`rm/composition/content/entry.rb:30`） | 設定 `ja` | 規則 5。変えない |
| ENTRY（共通） | `encoding` | ○（同 `:39`） | 設定 `UTF-8` | 規則 5。変えない |
| ENTRY（共通） | `subject` | ○（同 `:46`） | `PARTY_SELF`（`external_ref` 無し） | 変えない（患者本人。M3 で EHR と結ぶ） |
| OBSERVATION | `data`（HISTORY） | ○（同 `:92`） | field の path から組む | 変えない |
| HISTORY | `name` | ○ | 固定文 `"history"` | 規則 2。**5 節の 3** |
| HISTORY | `origin` | ○（`rm/data_structures/history.rb:33`） | 保存した時刻（UTC） | 規則 4。変えない |
| POINT_EVENT | `name` | ○ | 固定文 `"event"` | 規則 2。**5 節の 3** |
| POINT_EVENT | `time` | ○（同 `:68`） | 保存した時刻（UTC） | 規則 4。測定時刻の入力欄は範囲の外（7 節） |
| ITEM_TREE | `name` | ○ | ENTRY の concept（英字） | 規則 2。**5 節の 3** |
| CLUSTER（埋め込み） | `name` | ○ | テンプレート上の名前（`root_label`、`#38`） | 変えない |
| ELEMENT | `name` | ○ | 入力欄のラベル | 変えない |
| CODE_PHRASE（全箇所） | `terminology_id` | ○ | **値が空**: `{"_type":"TERMINOLOGY_ID"}` | 値を入れる。**5 節の 1** |
| INSTRUCTION | `narrative` | ○（`entry.rb:127`） | 組んでいない（INSTRUCTION は未対応） | **6 節（ゲート）** |
| INSTRUCTION | `activities` | 空は不可（同 `:134`） | 同上 | field の path から組む（D。0.9.0 のあと） |
| INSTRUCTION | `expiry_time`・`wf_definition` | 任意 | 同上 | 付けない |
| ACTIVITY | `description` | ○（同 `:153`） | 同上 | field の path から組む（D） |
| ACTIVITY | `action_archetype_id` | ○（同 `:167`） | 同上 | 規則 1。制約が無ければ `/.*/`（R-20261124-5。jp_referral.opt には制約が無い。実測） |
| ACTIVITY | `timing` | 任意（RM 1.0.4） | 同上 | 付けない（R-20261124-5） |
| ACTION | `time` | ○（同 `:188`） | 組んでいない（ACTION は未対応） | 規則 4（保存した時刻）。ACTION を組む作業は M2 に無い |
| ACTION | `description` | ○（同 `:195`） | 同上 | field の path から組む |
| ACTION | `ism_transition`（`current_state`） | ○（同 `:253`） | 同上 | 規則 1（OPT が 1 つに絞っていれば）、でなければ規則 6（入力欄）。臨床の判断なので、着手のときにゲート |

## 4. いまの欠陥（実測、main `c09d72f`）

1. **`terminology_id` の値が空**。保存される CODE_PHRASE はすべて `"terminology_id":{"_type":"TERMINOLOGY_ID"}` になる
   （言語、地域、文字コード、category、選択肢の DV_CODED_TEXT）。
   - 原因: `composition_builder.rb` の `code_phrase` が `TerminologyID.new(name: …)` で組む。
     `RMJSONSerializer` は `value` を出すが、`name:` で組んだものは `@value` を持たない
   - 実測: `TerminologyID.new(name: "ISO_639-1")` は `{"_type":"TERMINOLOGY_ID"}`、
     `TerminologyID.new(value: "ISO_639-1")` は `{"_type":"TERMINOLOGY_ID","value":"ISO_639-1"}`
   - 影響: 保存した記録から、コードがどの用語体系のものか読めない。直接コミットする経路
     （`app/lib/demo/sample_compositions.rb:65`）は値を持つので、同じ傷病名でも経路で形が違う
2. **`category` の値とコードが逆**。`"value":"433"`、`"code_string":"event"` になる。
   - 原因: 設定は `[コード, 表示]` の順（`OpenehrRails.default_category` の既定は `%w[433 event]`）。
     `composition_builder.rb` の `dv_coded_text(value, code, terminology)` に、そのままの順で渡している
   - gem の検査は通る。`TerminologyService.has_code_for_group?` は既定の実装が常に true を返す
     （`terminology_service.rb:21-23`。実測: `'zzz'` でも true）
3. **ノードの名前がテンプレートの用語でない**。HISTORY は `"history"`、POINT_EVENT は `"event"`、
   ITEM_TREE と ENTRY は英字の concept。直接コミットした構造骨格は「傷病名」「サービス依頼」を持つ
   （`spec/fixtures/compositions/jp_referral/skeleton.canonical.json`）
4. **`context` が無い**。どの OPT も `context` を制約している（6 つの fixture のうち 5 つ。実測）が、
   フォーム経路の Composition には付かない。openehr-rails 0.8.0 は `context` を保存しない（上流候補 16 項）

## 5. 進め方（1 Issue = 1 PR、Red から）

| # | 内容 | 待つもの | Red から始める spec の見出し |
|---|---|---|---|
| 1 | `terminology_id` に値を入れる | なし | 「保存した Composition の言語・地域・文字コード・category・選択肢の terminology_id が値を持つ」 |
| 2 | `category` を正しい向きにし、OPT の制約から取る | なし | 「category は value が event、code_string が 433」「OPT が category を絞っていれば、そのコードを使う」 |
| 3 | ノードの名前をテンプレートの用語から取る（COMPOSITION・ENTRY・HISTORY・EVENT・ITEM_TREE） | openehr 2.5.0 の #58 が入れば gem から、入らなければ `Opt::TemplateTerms` から | 「ENTRY の name はテンプレート上の名前（傷病名）」「HISTORY と EVENT の name は、そのノードの at-code の text」 |
| 4 | 自動で入る値を、保存の前に帳票の上で見せる（下の 5.1） | 1〜3 のあと | 「帳票に『自動で記録される項目』の欄があり、言語・地域・記録者・記録日時の扱いが読める」（文言は `docs/demo/ui-vocabulary.md` と同じコミット） |
| 5 | `context`（`start_time`・`setting`） | openehr-rails 0.9.0（16 項） | 「紹介日（context/start_time）で引ける」（M2 の F と同じ見出し） |
| 6 | INSTRUCTION・ACTIVITY（M2 の D） | openehr-rails 0.9.0（17 項）と、6 節の裁定 | M2 の計画書の D |

- 1〜3 は、保存される Composition の形を変える。A（`#54`）と同じ扱いにする:
  既に保存済みの記録は変えない。FHIR ファサードと `spec/demo/` を regression pin にする。
  開発機のデータの作り直し（`rake demo:reset`）は、セッションは実行しない
- 3 は ENTRY の name を変えるので、name 述語を使う AQL と、検索（引く側のレーン）に影響しうる。
  着手の前に `spec/demo/` と `docs/demo/aql-queries.md` で name を使う箇所を洗い、ログに書く
- 上流に送る観察（`docs/upstream-candidates.md` に追記する）:
  `TerminologyID.new(name:)` が `value` を持たずに直列化されること、
  `has_code_for_group?` の既定の実装が常に true を返すこと

### 5.1 自動で入る値を、保存の前に見せる

- 帳票の末尾（保存ボタンの上）に、読み取り専用の欄「自動で記録される項目」を置く
- 中身は、3 節の表のうち規則 1・3・4・5 で決まる値。たとえば、言語（日本語）、地域（日本）、
  記録者（未設定）、記録日時（保存した時刻）、記録の種類（event）
- 入力から組み立てる値（6 節の narrative で B を採った場合）は、同じ欄に、いまの入力から作った文を出す。
  入力のたびに作り直す（サーバーの同じ規則を使う。規則を JavaScript に二重に持たない）
- 閲覧専用の帳票（`preview_only`）でも同じ欄を出す

## 6. ゲート: INSTRUCTION の narrative の作り方（人間の判断）

`narrative` は RM で必須の DV_TEXT で、「その指示を人が読める文で書いたもの」。帳票に入力欄は出ない。
jp_referral に限らず、INSTRUCTION を含むどのテンプレートでも同じ規則を使う前提で、候補を 4 つ挙げる。

| 案 | 作り方 | 良い点 | 困る点 |
|---|---|---|---|
| A. 1 項目の写し | INSTRUCTION 配下の、決めた 1 つの要素の値を写す | 単純 | どの要素かをテンプレートごとに決める必要がある（一般の規則にならない）。その要素が空だと作れない |
| **B. 複数項目からの組み立て（推奨）** | INSTRUCTION 配下で入力された要素を、文書順に「ラベル: 値」でつなぐ | テンプレートを問わない。入力した内容と必ず一致する。保存の前に見せられる（5.1） | 文が機械的になる。項目が多いと長くなる |
| C. 専用の入力欄 | INSTRUCTION ごとに、必須の入力欄「指示の要約」を帳票に足す | 人が書いた文になる | 入力が 1 つ増える。ほかの項目と食い違う文を書ける |
| D. 固定文 | テンプレート上の INSTRUCTION の名前（例: 「サービス依頼」）を入れる | いちばん単純 | 中身を表さない。記録ごとの違いが出ない |

推奨は B。理由は 3 つ:

- 一般の規則になる（A は要素の指定が、C は入力欄の文言が、テンプレートごとの判断を要する）
- 値の出どころが入力だけなので、記録の中で食い違いが起きない
- 生成系を使わずに、決まった手順で作れる

決めてほしい点:

1. A〜D のどれを採るか（B に C を重ねる形、つまり「組み立てた文を初期値にして、書き換えられる」もありうる）
2. B の場合、つなぎ方（区切り、含める型、空欄の扱い）は実装で決めてよいか
3. 「依頼内容」は v0.2 のテンプレートに無いラベル（R-20261124-5）。B なら、どの要素を指すかを決めなくて済む

## 7. 範囲の外

- 測定時刻・記録者・施設の入力欄（M3 の「患者と EHR」「カルテ記録」で扱う）
- ACTION を組む作業（M2 に無い。表は、組むときの規則だけを書いた）
- 保存済みの記録の書き換え
