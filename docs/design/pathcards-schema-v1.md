# パスカード・スキーマ v1（WP1成果物）

**作成日**: 2026-08-22
**位置づけ**: `claude-code-prompt_semantic-pathcards.md` WP1の成果物。スキーマv1の設計提案と、実OPTから手作業抽出したサンプルカード3枚。承認後、WP2（抽出器）のテストTODOリストの基礎となる。
**前提文書**: [pathcards-wp0-exploration.md](pathcards-wp0-exploration.md)（探索）／[pathcards-language-policy.md](pathcards-language-policy.md)（言語ポリシー: 全OPT lang=ja前提・未翻訳許容・2段階検出）

---

## 1. スキーマ v1

カードは1ノード（データ点）につき1枚。JSON表現を正とする（保存形態はWP2/WP3で確定。SQLite/PostgreSQLのJSONカラムを想定）。

```yaml
pathcard:
  schema_version: "1.0"

  identity:                    # ノードの一意識別（この4つ組が実質キー）
    template_id: string        # OPTのtemplate_id
    archetype_id: string       # ノードが属する直近のC_ARCHETYPE_ROOTのarchetype_id
    path: string               # COMPOSITIONルートからのRMパス（/content[...]/.../value）
    at_code: string | null     # ノードのnode_id（構造ノード経由で無い場合null）

  semantics:
    rm_type: string            # 値のRM型（DV_QUANTITY等）。ELEMENT自体でなく値制約の型
    labels:                    # 言語別ラベル。ja優先（配列先頭がja）
      - lang: string           # OPT宣言言語（lang=ja前提。language-policy 2節）
        text: string
        untranslated_suspect: boolean        # language-policy 4節の2段階検出
        untranslated_evidence: "fallback_marker" | "no_ja_script" | null
        source_lang: string | null           # fallback_markerの末尾(xx)から取れた原語。無ければnull
    descriptions:              # labelsと同形（descriptionにもマーカーが実在する。カード1参照）
      - { lang, text, untranslated_suspect, untranslated_evidence, source_lang }

  constraints:
    occurrences: { lower: integer | null, upper: integer | null }  # nullは無制約側
    value:                     # rm_type別の制約。該当キーのみ持つ（全てoptional）
      # DV_QUANTITY:
      property: { terminology: string, code: string } | null   # 例 openehr::125
      units: string | null                                     # UCUM
      magnitude_range: { lower: number|null, upper: number|null,
                         lower_included: boolean, upper_included: boolean } | null
      precision_range: { lower: integer|null, upper: integer|null } | null
      # DV_CODED_TEXT: code_list: [{code, label}] （ローカルat-code値集合）
      # DV_TEXT/其他: キー無し（制約なし）

  bindings:                    # 用語バインディング。空配列を許容
    - kind: "code_binding" | "value_set_binding"
      system_uri: string       # 用語システム/値集合のURI・名称
      code: string | null      # code_binding時のみ。value_set_binding（referenceSetUri）はnull
      display: string | null   # OPT単独では常にnull。WP5の$lookupで解決する前提の受け皿

  capture:                     # 帳票正規化規則の構造定義。v1では全カードで空
    rules:
      - kind: "era_date"            # 和暦→ISO日付
          | "zenkaku_digits"        # 全角数字→半角
          | "composite_split"       # 複合値分解（例: 血圧「120/80」→2ノードへ）
          | "checkbox_group"        # チェックボックス群→値集合コード
          | "other_with_freetext"   # 「その他（　）」→コード＋自由記載の混成
        config: object              # kind別の構造（分解先identity参照等）。v1では未定義

  reserved:                    # 2027年拡張用の予約枠（常に空で出力）
    voice_aliases: []

  provenance:
    source_template_id: string
    source_checksum: string    # source_xmlのSHA-256。templates.checksum（app/models/template.rb:33）と同一計算で、登録済みテンプレートとの突合を可能にする
    extracted_at: string       # ISO8601
    extractor_version: string  # WP2実装のバージョン。手作業抽出は "wp1-manual"
```

### 設計判断と根拠

1. **bindingsに `kind` 判別子を導入**: 実OPTでバインディングが2形式確認されたため。
   - `code_binding`: `<term_bindings>` によるat-code→外部コードの対応（実例: CardiologyEncounter.opt 1029-1035行、at0004→`[SNOMED-CT(2003)::271649006]`）
   - `value_set_binding`: `C_CODE_REFERENCE` の `referenceSetUri` による値集合参照。**特定コードを持たない**（実例: ProblemList.opt 323-334行、`terminology:http://id.who.int/icd/release/11/mms`）
2. **bindings空許容の根拠**（WP0 2.7節＋2026-08-22追加確認）: gemパーサはterm_bindingsを読まず、C_CODE_REFERENCEに至っては**パース自体が失敗する**（`docs/upstream-candidates.md` 6項）。人間決定（2026-08-22）により、WP2抽出器は `templates.source_xml` のOPT原文を独自再解析して両形式を補完抽出する。
3. **labels/descriptionsの未翻訳検出フィールド**: language-policy 3-4節の要件をそのまま組み込んだ。`source_lang` は実観察（`*state structure(en)` / `*Bloeddruk` / `*Appended (en)`）でマーカー末尾の言語表記が任意と判明したためnull許容。
4. **identity.archetype_idは「直近のC_ARCHETYPE_ROOT」**: 埋め込みCLUSTER配下ノードのat-codeは宿主アーキタイプと衝突し得る（実例: LabResultReport.optのat0001が宿主側「Event Series」と誤解決される。`docs/upstream-candidates.md` 7項）。カードの用語解決は必ず所属アーキタイプのcomponent_terminologyで行う。
5. **captureは構造のみ定義**: FieldExtractorがprotocol/state配下を対象外とする制約（WP0 2.9節）と整合。初期値は空、10月の帳票パイプラインが埋める。
6. **provenanceのchecksum**: fixtureが流動している実態（language-policy 5節）に対し、カードがどの版のOPTから抽出されたかを機械照合可能にする。

---

## 2. サンプルカード3枚（実OPTから手作業抽出）

抽出日: 2026-08-22。抽出元fixtureのSHA-256:

| fixture | SHA-256 |
|---|---|
| spec/fixtures/opt/CardiologyEncounter.opt | `57e6e93ec301d5f4dda779285ca48646a5ba0dad7662622672b4fd67aa07736b` |
| spec/fixtures/opt/LabResultReport.opt | `414bbd49996f5dfd2da5a3374ced6ada7e7fc32405a883d8f51808bb00554743` |
| spec/fixtures/opt/ProblemList.opt | `b821b98beebfba9e758cc0429a91bb98aedb7d50de684424f0eb58d51e4a47c1` |

各値の `#` コメントがソース引用（fixtureファイル:行番号、または実行時取得の別記）。

### カード1: 傷病名（コード化要素・値集合バインディングの実例）

```yaml
pathcard:
  schema_version: "1.0"
  identity:
    template_id: ProblemList                                # ProblemList.opt:43-45
    archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1   # 同:223-233（C_ARCHETYPE_ROOT）
    path: /content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0002]/value
      # XML構造から手作業導出: content(213行)→C_ARCHETYPE_ROOT(223)→at0000(233)→data(235)
      # →at0001(255)→items(257)→ELEMENT at0002(277)→value(279)
      # ※本OPTは現gemでパース不能のため抽出器実測パスではない（後述の承認事項1）
    at_code: at0002                                         # 同:277
  semantics:
    rm_type: DV_CODED_TEXT                                  # 同:302（value配下のC_COMPLEX_OBJECT）
    labels:
      - lang: ja
        text: プロブレム・診断名                             # 同:760
        untranslated_suspect: false
        untranslated_evidence: null
        source_lang: null
    descriptions:
      - lang: ja
        text: "*Identification of the problem or diagnosis, by name. (en)"   # 同:761
        untranslated_suspect: true                          # 段階1: 先頭`*`
        untranslated_evidence: fallback_marker
        source_lang: en                                     # マーカー末尾 (en)
  constraints:
    occurrences: { lower: 1, upper: 1 }                     # 同:269-276（ELEMENT at0002）
    value: {}                                               # DV_CODED_TEXT型別制約: ローカルcode_listなし（外部値集合参照のみ）
  bindings:
    - kind: value_set_binding
      system_uri: "terminology:http://id.who.int/icd/release/11/mms"   # 同:334（referenceSetUri）
      code: null                                            # C_CODE_REFERENCEは特定コードを持たない
      display: null
  capture: { rules: [] }
  reserved: { voice_aliases: [] }
  provenance:
    source_template_id: ProblemList
    source_checksum: b821b98beebfba9e758cc0429a91bb98aedb7d50de684424f0eb58d51e4a47c1
    extracted_at: "2026-08-22"
    extractor_version: wp1-manual
```

### カード2: 検査値（DV_QUANTITYの実例。暫定版）

> **暫定**: 現fixtureのC_DV_QUANTITYは単位・基準範囲の制約を持たない（裸のDV_QUANTITY化のみ）。単位・値域入りのOPT更新（AD作業・人間依頼中、2026-08-22決定）が届き次第、本カードを差し替える。単位・値域・精度の完全な実例はカード3が担う。

```yaml
pathcard:
  schema_version: "1.0"
  identity:
    template_id: LabResultReport                            # LabResultReport.opt:41-43
    archetype_id: openEHR-EHR-CLUSTER.laboratory_test_analyte.v1   # 同:619（直近のC_ARCHETYPE_ROOT。設計判断4）
    path: /content[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]/data[at0001]/events[at0002]/data[at0003]/items[at0000]/items[at0001]/value
      # FieldExtractor実測（2026-08-22、bin/rails runner経由でTemplate.build_from_opt_xmlの
      # web_template["entries"][0]["fields"]から取得）
    at_code: at0001                                         # 同:549
  semantics:
    rm_type: DV_QUANTITY                                    # 同:561（C_DV_QUANTITY）
    labels:
      - lang: ja
        text: 分析結果                                       # 同:622（CLUSTER.laboratory_test_analyte.v1のcomponent_terminology）
        untranslated_suspect: false
        untranslated_evidence: null
        source_lang: null
        # 注: FieldExtractorは本ノードを宿主OBSERVATION側のat0001「Event Series」（同:1039）と
        # 誤解決する（upstream-candidates 7項）。カードは所属アーキタイプ側を正とする
    descriptions:
      - lang: ja
        text: "*The value of the analyte result. (en)"      # 同:623
        untranslated_suspect: true
        untranslated_evidence: fallback_marker
        source_lang: en
  constraints:
    occurrences: { lower: 1, upper: 1 }                     # 同:563-570（C_DV_QUANTITYのoccurrences）
    value:
      property: null                                        # 制約未設定（暫定。差し替え待ち）
      units: null
      magnitude_range: null
      precision_range: null
  bindings: []                                              # 本OPTにterm_bindings/referenceSetUriなし（grep実測0件）
  capture: { rules: [] }
  reserved: { voice_aliases: [] }
  provenance:
    source_template_id: LabResultReport
    source_checksum: 414bbd49996f5dfd2da5a3374ced6ada7e7fc32405a883d8f51808bb00554743
    extracted_at: "2026-08-22"
    extractor_version: wp1-manual
```

### カード3: 収縮期血圧 at0004（記念碑）

```yaml
pathcard:
  schema_version: "1.0"
  # 本カードは本プロジェクトの記念碑である。かつて記憶からのat-code記載が誤りを生んだ。
  # at-codeは記憶から書かず、実行時にOPTから引く。
  identity:
    template_id: CardiologyEncounter                        # CardiologyEncounter.opt:140-142
    archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2 # FieldExtractor実測（entry archetype_id）
    path: /content[openEHR-EHR-OBSERVATION.blood_pressure.v2]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value
      # FieldExtractor実測（2026-08-22、web_template fields[0].path）
    at_code: at0004                                         # 同:417
  semantics:
    rm_type: DV_QUANTITY                                    # 同:429（C_DV_QUANTITY）
    labels:
      - lang: ja
        text: 収縮期                                         # 同:790
        untranslated_suspect: false
        untranslated_evidence: null
        source_lang: null
    descriptions:
      - lang: ja
        text: 全身の動脈血圧での最高値 - 心機図の収縮期で測定される   # 同:791
        untranslated_suspect: false
        untranslated_evidence: null
        source_lang: null
  constraints:
    occurrences: { lower: 1, upper: 1 }                     # 同:431-438（C_DV_QUANTITYのoccurrences）
    value:
      property: { terminology: openehr, code: "125" }       # 同:440-445（圧力）
      units: "mm[Hg]"                                       # 同:463
      magnitude_range: { lower: 0.0, upper: 1000.0,
                         lower_included: true, upper_included: false }   # 同:447-454
      precision_range: { lower: 0, upper: 0 }               # 同:455-462
  bindings:
    - kind: code_binding
      system_uri: SNOMED-CT                                 # 同:1029（term_bindings terminology属性）
      code: "[SNOMED-CT(2003)::271649006]"                  # 同:1035（code_string原文のまま。分解はWP2で検討）
      display: null                                         # OPT単独では取得不能。WP5 $lookupの解決対象
  capture: { rules: [] }
  reserved: { voice_aliases: [] }
  provenance:
    source_template_id: CardiologyEncounter
    source_checksum: 57e6e93ec301d5f4dda779285ca48646a5ba0dad7662622672b4fd67aa07736b
    extracted_at: "2026-08-22"
    extractor_version: wp1-manual
```

---

## 3. 未確認事項

1. **ProblemList.optのAnlage実行時動作**: C_CODE_REFERENCE非対応（upstream-candidates 6項）により現gemでパース不能のため、カード1のパスはXML構造からの手作業導出であり抽出器実測ではない。フォーム生成・保存の動作も未確認
2. **`terminology:` URIプレフィクスの出典**: referenceSetUriの `terminology:` スキームがADL/AOM仕様由来かAD独自かは未確認（仕様書の該当箇所を引けていない）
3. **code_bindingのcode_string分解**: `[SNOMED-CT(2003)::271649006]` を `{system, version, code}` に分解する正規形はWP2実装時に確定する（本カードでは原文のまま保持）
4. **precision 0..0 の解釈**（小数0桁=整数と推定されるが、仕様確認未了）

## 4. 承認が必要な判断

1. **スキーマv1本体の承認**（本文書1節）。承認後、WP2計画（対象ファイル・テストTODOリスト・コミット分割案）を提示する
2. ~~C_CODE_REFERENCEパース不能への対処をWP2計画に含めること~~ → **解消（2026-08-22）**: `openehr` gem 2.3.1 bumpで解決した。gem側がC_CODE_REFERENCEを`CCodeReference`（`reference_set_uri`保持）として正規にパースするようになったため、Anlage側`OpenehrRails::Opt::Parser`派生クラスへの`c_code_reference`ハンドラ追加は不要。ProblemList.optは素のgemで試着室まで到達することをスモーク確認済み（`Opt::SafeParser.parse`経由、`reference_set_uri: "terminology:http://id.who.int/icd/release/11/mms"`を検出）。なお`source_xml`再解析によるterm_bindings/referenceSetUri補完抽出（WP2本来のTDD項目）はopenehr-ruby#31の領域として引き続き残置
3. **カード2の差し替え**: 単位・基準範囲入りOPT更新の到着後、検収（language-policy 5節）→カード2更新、の運用でよいか
