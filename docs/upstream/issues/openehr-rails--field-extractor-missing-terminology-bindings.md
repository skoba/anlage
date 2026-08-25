# FieldExtractor never extracts external terminology bindings (value_set_binding / code_binding)

要約: `OpenehrRails::Opt::FieldExtractor`は`DV_CODED_TEXT`のローカル
`code_list`しか抽出せず、外部語彙への2種類のbinding（`C_CODE_REFERENCE`
の値集合参照＝value_set_binding、`term_bindings`の固定コード対応＝
code_binding）を一切抽出しない。この結果、`ProfileGenerator`が生成する
FHIR StructureDefinitionの`DV_CODED_TEXT`要素は`binding: {strength:
'required'}`のみで`valueSet`キーを持たず（既存バグ）、FSHエクスポート
機能（`skoba/anlage#17`）が外部語彙bindingを表現する上でのブロッカー
にもなっている。

> **RESOLVED UPSTREAM（2026-08-26確認）** — このドラフトを人間中継で
> 送付する前に、openehr-rails側で**同一内容のIssueが独立に起票・実装・
> リリース済み**であることが判明した。`skoba/openehr-rails#30`
> （同名タイトル）としてCLOSED、`openehr-rails` 0.5.0（2026-08-25
> rubygems公開）に同梱。実装経路: `c586a8c`起票→`5470d29`設計
> （`docs/design/binding-extraction-plan.md`）→`c571bf5`（openehr依存
> フロア`>= 2.3.1`引き上げ）→`0bbbc47`（`problem_list.opt`fixture、
> anlageの`ProblemList.opt`を出所明記の上でコピー）→`6efc161`
> （`FieldExtractor`/`ProfileGenerator`実装、Codex）→`7e7e2f0`
> （PR・merge）→`7c2d4d8`（`skoba/openehr-ruby#31`へのupstreamコメント）
> →`69db63f`（0.5.0リリース）。
>
> 実装形は本ドラフトの提案と概ね一致するが1点差分がある:
> `code_binding`の投入経路は`FieldExtractor`自身への直接移植ではなく、
> `OpenehrRails::Opt::Parser#parse`の`populate_term_bindings!`
> （parse時のenrichment、`lib/openehr_rails/opt/parser.rb:24,43-60`）が
> OPT文書のterm_bindings XMLを独自に再パースし、上流
> `ArchetypeOntology#term_bindings`（既存だが従来nilだったslot）へ
> 投入する形。`skoba/openehr-ruby#31`解消後にメソッド2つの削除で
> 撤去できる設計（撤去条件コメントが`parser.rb`に明記済み）。
> `FieldExtractor#build_field`は常に`value_set_uri`（nilあり）・
> `code_bindings`（`[{system_uri:, code:}]`、空配列あり）を持つ。
>
> **本ファイルは起票せず、調査時点の要求仕様・実測根拠の記録として
> 保存する**（`openehr-ruby--field-extractor-wrong-terminology-scope.md`
> の前例と同型の扱い）。詳細は`docs/reports/fsh-log.md` R3参照。
> 以下は起票用に準備していた原文のまま。

**起票: 人間中継でopenehr-railsへ提出予定（本ファイルはその下書き。
`skoba/anlage#17`「FSHエクスポート」裁定2026-08-26で承認済み、
Anlage側での起票が下記の段取りで許可されている）**

## Suggested labels

`bug`, `enhancement`, `field-extractor`, `fhir`

## Summary

- `FieldExtractor#coded_text_constraints`（`lib/openehr_rails/opt/
  field_extractor.rb:191-203`）は`defining_code`直下の`code_list`
  （ローカル列挙コード、例: `openEHR-EHR-EVALUATION.problem_diagnosis.v1`
  `at0073`のローカル診断確度コード）のみを抽出する。
- 外部語彙への2種類のbindingは一切抽出されない:
  1. **value_set_binding**: `defining_code`制約が`C_CODE_REFERENCE`
     （ローカル列挙ではなく外部値集合への参照）の場合の
     `reference_set_uri`（例: ICD-11の`terminology:http://id.who.int/
     icd/release/11/mms`）
  2. **code_binding**: 同archetype内のELEMENTを外部語彙の固定コードへ
     対応させる`term_bindings`（例: SNOMED-CTの`[SNOMED-CT(2003)::
     271649006]`、LOINC等）
- 直接の結果として、`ProfileGenerator#apply_value_constraints`
  （`lib/openehr_rails/fhir/profile_generator.rb:125-129`）の
  `DV_CODED_TEXT`分岐は`element[:binding] = { strength: 'required' }`
  のみを設定し、**`valueSet`キーを含まない**——FHIR
  StructureDefinitionのbinding要素として不完全（`valueSet`無しの
  `binding`はFHIR仕様上有効だが実用上は無意味に近い）。

## Environment

- `openehr-rails`（本リポジトリのローカルチェックアウト、
  `/home/skoba/src/openehr-rails`）
- `openehr` 2.4.2（rubygems.org、`RMJSONSerializer`のArchetypeID
  ラウンドトリップ修正済みバージョン）

## Evidence: 実際のOPTに両binding形式が存在する（Anlage側での実測）

Anlageの`Opt::PathcardExtractor`（`app/lib/opt/pathcard_extractor.rb`、
本リポジトリの下流アプリ、参照実装として下記）が実際に抽出した値
（`spec/fixtures/pathcards/*.golden.json`実測、2026-08-25）:

- `ProblemList.opt`の`openEHR-EHR-EVALUATION.problem_diagnosis.v1`
  `at0002`: `{"kind":"value_set_binding","system_uri":
  "terminology:http://id.who.int/icd/release/11/mms","code":null,
  "display":null}`
- `CardiologyEncounter.opt`の`openEHR-EHR-OBSERVATION.blood_pressure.v2`
  `at0004`: `{"kind":"code_binding","system_uri":"SNOMED-CT","code":
  "[SNOMED-CT(2003)::271649006]","display":null}`

いずれもCKM公開archetype・Archetype Designer経由で人間作成された実
OPT由来（合成データではない）。本リポジトリ自身の`spec/templates/
bmi_calculation_without_uid.opt`（`bmi_calculation.opt`の別variant）
にも同型のSNOMED-CT・LOINC `term_bindings`が実在する
（`spec/templates/bmi_calculation_without_uid.opt:1683-1697`実測、
`at0004`にSNOMED-CT`60621009`・LOINC双方のbindingを保持）——リポジトリ
内に既にcode_binding形式のテスト対象が存在する。value_set_binding
（`C_CODE_REFERENCE`）形式の実例は本リポジトリのspec fixtureには現状
無い（grep実測、2026-08-26）。

## Root cause

`coded_text_constraints`（`field_extractor.rb:191-203`）:

```ruby
def coded_text_constraints(constraint, archetype_id)
  defining_code = (constraint.attributes || [])
                  .find { |a| a.rm_attribute_name == 'defining_code' }
  code_phrase = defining_code&.children&.first
  return {} unless code_phrase

  codes = (code_phrase.code_list || []).reject { |c| c.nil? || c.empty? }
  {
    code_list: codes,
    code_labels: codes.to_h { |code| [code, term_text(archetype_id, code) || code] },
    terminology_id: code_phrase.terminology_id&.value
  }
end
```

`code_phrase`は`CODE_PHRASE`（ローカル列挙、`code_list`を持つ）か
`C_CODE_REFERENCE`（値集合参照、`reference_set_uri`を持つ）のいずれか
になりうるが、上記コードは`CODE_PHRASE`の形しか想定していない
（`C_CODE_REFERENCE`の場合`code_phrase.code_list`は空配列または存在せず、
`reference_set_uri`は一切参照されない）。加えて、`term_bindings`
（ontologyセクション、`defining_code`制約の外側にある独立した
XML要素）はこのメソッドの走査対象にすら入っていない
——`FieldExtractor`はOPTの`content`ツリーのみを歩き
（`content_roots`/`entry_roots`、`field_extractor.rb:65-97`）、
ontology側の`term_bindings`セクションは一切参照しない構造になっている。

## 参照実装: Anlageの`Opt::PathcardExtractor`

`app/lib/opt/pathcard_extractor.rb:243-280`（本リポジトリの下流
アプリ、`skoba/anlage`）が両binding形式を実際に抽出しているロジック:

```ruby
def bindings_for(element, archetype_id)
  code_reference_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Text::CCodeReference
  value_constraint = defining_code_constraint(primary_value_alternative(element))
  bindings = []
  if value_constraint.is_a?(code_reference_class)
    bindings << {
      "kind" => "value_set_binding",
      "system_uri" => value_constraint.reference_set_uri,
      "code" => nil,
      "display" => nil
    }
  end

  bindings.concat(@code_bindings.fetch([archetype_id, element.node_id], []))
end

def extract_code_bindings(document)
  bindings = Hash.new { |hash, key| hash[key] = [] }

  document.xpath("//*[local-name()='term_bindings']").each do |term_binding|
    archetype_id = nearest_archetype_id(term_binding)
    next unless archetype_id

    term_binding.xpath("./*[local-name()='items']").each do |item|
      code = item.at_xpath("./*[local-name()='value']/*[local-name()='code_string']")&.text
      next unless code

      bindings[[archetype_id, item["code"]]] << {
        "kind" => "code_binding",
        "system_uri" => term_binding["terminology"],
        "code" => code,
        "display" => nil
      }
    end
  end

  bindings
end
```

**重要な非対称性**: `value_set_binding`（`C_CODE_REFERENCE#reference_set_uri`）
は`openehr`gemの**パース済みオブジェクトモデル経由**で取得できる
（`skoba/openehr-ruby#30`「OPTParser crashes with NoMethodError on
`C_CODE_REFERENCE` children」がCLOSED済みのため、`C_CODE_REFERENCE`
ノード自体は正常にパースされ`reference_set_uri`アクセサも機能する）。
一方`code_binding`（`term_bindings`）は**`OpenEHR::Parser::OPTParser`が
そもそもontology側の`term_bindings`を読まずに捨てている**
（`skoba/openehr-ruby#31`「OPTParser drops `term_bindings`」、
現在も**OPEN**）ため、gemのパース済みオブジェクトモデルには
一切現れない。これが`Opt::PathcardExtractor`が`term_bindings`だけ
`Opt::SafeParser.safe_document`（生XML、Nokogiri直接）を別途読んで
迂回している理由——`extract_code_bindings`はOPTParserの出力を経由
せず、OPT XMLを独立に再パースしている。

**本Issueへの含意**: `FieldExtractor`が同じ2種のbindingを追加する場合、
- `value_set_binding`はgemのオブジェクトモデル（`constraint`）から
  直接取得可能（`skoba/openehr-ruby#31`を待つ必要なし）
- `code_binding`は`skoba/openehr-ruby#31`が解消されるまで、
  `Opt::PathcardExtractor`と同じ迂回（生XML再パース）を`FieldExtractor`
  内に持ち込む必要がある。これは`skoba/openehr-ruby#31`が将来解消
  すれば単純化できる暫定実装であることをコード注釈に明記すべき

## Expected

`FieldExtractor#entries[].fields[]`が以下のキーを追加で持つ:

- `value_set_uri`: `C_CODE_REFERENCE`の場合の`reference_set_uri`
  （文字列、無ければ`nil`）
- `code_bindings`: `term_bindings`から解決した`[{system_uri:, code:}]`
  の配列（複数terminology対応、無ければ空配列）

`ProfileGenerator#apply_value_constraints`の`DV_CODED_TEXT`分岐が
`field[:value_set_uri]`を`element[:binding][:valueSet]`へ反映する
（既存の`valueSet`欠落バグの解消、1行修正）。

## Suggested test

- `FieldExtractor`spec: `spec/templates/bmi_calculation_without_uid.opt`
  （既存fixture、実SNOMED-CT/LOINC term_bindings保持済み）で
  `code_bindings`が正しく抽出されることを検証
- value_set_binding側は本リポジトリに現状fixtureが無いため、新規
  fixtureの要否・出所（real/reduced/synthetic、本リポジトリの
  フィクスチャ規約に従う）はrails側のexplore→planで判断
- `ProfileGenerator`spec（`spec/openehr_rails/fhir/
  profile_generator_spec.rb`）に`valueSet`が反映されることを確認する
  ケースを追加

## Workaround

なし（Anlage側は`Opt::PathcardExtractor`が独立実装として両binding
形式を抽出済み。`FshGenerator`（FSHエクスポート、`skoba/anlage#17`）
のbinding写像部分は本Issueの解消をブロッカーとして待機中——
`docs/design/fsh-plan.md`裁定反映節「実装順序」参照）。
