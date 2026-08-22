# パスカード言語ポリシー: 全OPT lang=ja前提・未翻訳ノードの許容と検出容易化

**作成日**: 2026-08-21 ／ **改定**: 2026-08-21（Archetype Designer実測を受けて「lang=ja前提」に一本化。実OPTによる検出仕様の較正を記入）
**位置づけ**: セマンティックパスカード基盤（`claude-code-prompt_semantic-pathcards.md`）のWP1（スキーマ設計）・WP2（抽出器実装）への入力となる方針決定の記録。WP0レポート（[pathcards-wp0-exploration.md](pathcards-wp0-exploration.md)）の2.5節・2.9節・未確認事項9を前提とする。

## 0. 決定の要旨

1. **登録OPTはlang=jaであることを前提とする**（2026-08-21 人間決定）。オーサリング運用は「Archetype Designer上で全埋め込みアーキタイプにja言語定義を追加（内容は未翻訳でも可）→ jaでエクスポート」に一本化する。英語OPTへのフォールバック運用は行わない。
2. そのうえで、ja定義の**内容が未翻訳（原語のまま）のノードが混在することは許容**し、未翻訳ノードの**検出をできるだけ容易にする**設計をパスカード側に持たせる（驚き最小原則）。

理由: 全アーキタイプの翻訳完備（CKMへの翻訳貢献の往復）はデモマイルストーン（2026-11-05凍結）に対して現実的でない。一方、AD実測（1節）により「ja定義の追加」自体はAD内で完結でき、宣言言語をjaに固定できることが判明したため。

## 1. 技術的前提

### 1.1 ソース確認済みの事実

- OPT（ADL 1.4フラット化XML）は単一言語にフラット化され、`term_definitions` に言語属性は無い。gemパーサは全term_definitionsをOPTの `<language>` 宣言のキー下に一括格納する:

  ```ruby
  # openehr-2.3.0/lib/openehr/parser/opt_parser.rb:159-168
  def term_definitions(nodes)
    term_definitions = nodes.xpath 'term_definitions'
    term_items = term_definitions.map do |term|
      code = term.attributes['code'].value
      text = term.at('items[@id="text"]').text
      description = term.at('items[@id="description"]').text
      ...
    { language.code_string => term_items }
  ```

  したがって、未翻訳ノードの原語テキストは**「ja」として通り、OPT単独では真のja翻訳と機械判別できない**。
- パース・フォーム生成・保存は未翻訳混在でも壊れない。ラベル表示は言語を選ばず（`openehr-rails/lib/openehr_rails/opt/field_extractor.rb:10` 「display text from the template terminology (any language)」）、フィールド名（DBカラム名）は非ASCIIラベルをスラグ化せずat-codeへフォールバックする（同 `field_extractor.rb:218-227`）。
- 唯一の破壊ケース: term_definitionsノードに `items id="text"` / `items id="description"` が**欠落**した形でエクスポートされると、上記引用の `term.at(...)` がnilを返し `NoMethodError` でパースが落ちる（`opt_parser.rb:163-164`）。→ 5節のチェックリストで検収する。

### 1.2 Archetype Designer実測（2026-08-21 人間検証）

- テンプレートに含まれる**全アーキタイプにja言語定義が無いと、lang=jaでのOPTエクスポート自体ができない**。
- ただし、**ja定義の内容は未翻訳（原語のまま）でも構わない**。
- この2点から、「lang=jaのOPTだけを扱う」運用が追加の翻訳コストなしに成立する（0節の方針の根拠）。

### 1.3 実OPTによる観察

2点の実エクスポート品（いずれもAD lang=jaエクスポート、`openEHR-EHR-COMPOSITION.encounter.v1` + `openEHR-EHR-OBSERVATION.blood_pressure.v2` 構成）で確認:

**BloodPressureMonitoring.opt（2026-08-21。現在はリポジトリから撤去済み）**:

- `<language>` code_string = `ja`。全64 term_definitionsに `text`/`description` 両itemsあり（破壊ケース非発生）。
- 未翻訳マーカーの実例: `*state structure(en)` — 先頭 `*` + 末尾 `(en)`。
- マーカー無しの未翻訳残存も実在: `Tree`, `Extension`。一方 `mmHg` のように日本語運用でも正当なASCIIラベルも実在。
- SNOMED-CTバインディング（at0004 → `[SNOMED-CT(2003)::271649006]`）はOPT XML上に保持されている（gemパーサは読まないが、Anlage側補完抽出の余地はWP0 5節-3のとおり）。

**CardiologyEncounter.opt（2026-08-22。現行fixture `spec/fixtures/opt/CardiologyEncounter.opt`）**:

- `<language>` code_string = `ja`。全832 term_definitionsに `text`/`description` 両itemsあり。
- 記念碑ノード at0004 は「収縮期」の日本語textで取得できる（WP1サンプルカード素材1点目を確保）。
- 日本語textは832件中60件のみ（未翻訳が大半 — 本方針の許容ケースの実物）。
- **マーカーの変種を確認**: `*Any event(en)` のような「先頭 `*` + 末尾 `(en)`」形に加え、**`*Bloeddruk` のように末尾 `(<lang>)` を持たない `*` マーカーも実在**する。
- 本fixtureで `Template.build_from_opt_xml` → `Opt::CompositionBuilder#build` が通ることをスペックで確認済み（`spec/lib/opt/composition_builder_spec.rb`）。

**LabResultReport.opt / ProblemList.opt（2026-08-22。現行fixture）**:

- 両者とも `<language>` code_string = `ja`、`text`/`description` 両items完備（96/96、60/60）。
- LabResultReportでマーカーのさらなる変種を確認: `*Appended (en)` — **括弧の前に空白**が入る形。4節の正規表現案（`.+?` が空白ごと吸収）でマッチすることは確認済み。
- ProblemListには `*` マーカーが1件も無く、未翻訳はマーカー無しの原語残存のみ → 段階2（no_ja_script）が必要な実例。
- **term_bindingsは両者とも0件**（3点中、保持しているのはCardiologyEncounter.optのSNOMED-CT 1件のみ）。
- 抽出実測（`Template.build_from_opt_xml` 経由、2026-08-22）: 3点ともパース成功。FieldExtractorが抽出したフィールドのラベルは**全て日本語** — CardiologyEncounter 2/2（収縮期・拡張期）、LabResultReport 2/2（検査名・結果診断）、ProblemList 13/13（プロブレム・診断名 ほか）。

## 2. 方針宣言

1. パスカード基盤が扱うOPTは**lang=ja宣言であることを前提**とする。lang≠jaのOPTの多言語対応は現時点のスコープ外（7節）。
2. lang=ja OPTにおける未翻訳ノード（原語テキスト・マーカー付きテキスト）は受け入れる。取り込みを拒否しない。
3. **ラベルを装わない**: パスカードは「OPTが申告した言語」と「未翻訳の疑い」を分けて記録する。機械はフラグ付けまでを担い、未翻訳の確定判定は人間が行う（勝手に欠落扱い・除外・翻訳補完をしない）。

## 3. パスカードスキーマへの要件（WP1で正式化）

- `labels` エントリは `lang`（OPT宣言言語）+ `text` に加え、未翻訳検出フィールドを持つこと。案:
  - `untranslated_suspect`: boolean
  - `untranslated_evidence`: `"fallback_marker"` | `"no_ja_script"` | null（検出根拠）
- フィールド名・型の確定はWP1スキーマ設計の責務。本ノートは要件のみを定める。

## 4. 検出ヒューリスティック仕様（2段階。実装はWP2のTDDで）

- **段階1（確度高）— fallbackマーカー検出**【較正済み】: 実観察（1.3節）でマーカーは「**先頭 `*`**」が本体で、末尾の `(<ISO 639-1コード>)` は**付く場合と付かない場合がある**（`*state structure(en)` / `*Bloeddruk`）。正規表現案: `/\A\*(.+?)(?:\(([a-z]{2}(?:-[a-z]{2})?)\))?\z/i` — 先頭 `*` で `fallback_marker` と判定し、末尾括弧があれば原語コードを検出根拠に添える。
- **段階2（疑い）— 日本語文字種の不在**: テキストが日本語文字種（ひらがな・カタカナ・漢字 `/[\p{Hiragana}\p{Katakana}\p{Han}]/`）を1文字も含まない → `no_ja_script`。
- 段階2が「疑い」止まりである根拠も実データで裏付けられた（1.3節）: `Tree`/`Extension` は実質未翻訳だが、`mmHg` は日本語運用でも正当。両者は機械では区別できないため、フラグを理由にカード化を止めたり値を書き換えたりしない。

## 5. OPTエクスポート検収チェックリスト（人間のOPT作成作業用）

作成するOPT（血圧v2・傷病名・検査値の3点、2026-08-20依頼分）に適用する:

- [ ] **AD上で全埋め込みアーキタイプにja言語定義を追加**（内容は未翻訳でも可）してからlang=jaでエクスポートすること（1.2節。jaが欠けているとエクスポート自体が失敗する）
- [ ] `<language>` の code_string が `ja` であること
- [ ] 各 `term_definitions` ノードに `items id="text"` と `items id="description"` の両方が存在すること（欠落するとパースが `NoMethodError` で落ちる。1.1節）

検収実績:

- [x] 血圧OPT: 全項目クリア。BloodPressureMonitoring.opt（2026-08-21、撤去済み）→ CardiologyEncounter.opt（2026-08-22、現行fixture）の2版とも検収済み。fallbackの実形式の観察も完了（1.3節に記録 → 段階1の較正に反映済み）
- [x] 傷病名OPT（ProblemList.opt、2026-08-22）: チェックリスト3項目クリア。ただし**WP1素材の残課題**: term_bindingsが0件のため、プロンプトWP1指定「コード化要素・bindingsの実例」の素材が不足。AD上で傷病名要素（at0002）へのSNOMED CT等のバインディング追加を人間に依頼中
- [x] 検査値OPT（LabResultReport.opt、2026-08-22）: チェックリスト3項目クリア。ただし**WP1素材の残課題**: DV_QUANTITY制約が0件（分析項目のCLUSTERスロットが未充填のため、プロンプトWP1指定「DV_QUANTITY: 単位・基準範囲の実例」の素材が不足）。CKM実在のlaboratory_test_analyte系CLUSTERをスロットに埋め、単位・基準範囲付きのDV_QUANTITYを具体化するよう人間に依頼中

fixtureは日本語訳等を適宜更新予定（2026-08-22 人間申告）のため、上記は同日時点のスナップショット。更新版が届いたら本チェックリストを再適用する。

## 6. 抽出時レポート（WP2で実装）

- OPT投入時のカード化サマリに**未翻訳疑いノード一覧**（アーキタイプパス・at-code・テキスト・検出根拠）を含める。
- WP2 DoD「日本語ラベルが取得できている（取得できないノードは欠落として報告する）」の解釈: 未翻訳疑いノードを欠落相当としてこの報告に含める。プロンプト本文の改定が必要なら人間が判断する（規律の正本はCLAUDE.md、プロンプトは追随）。

## 7. スコープ外

- lang≠ja OPTの受け入れ・多言語term_definitionsの実行時補完・CKM問い合わせ・自動翻訳は行わない。着想が生じたら `docs/ideas-2027.md` へ記録する（規律8）。
- gem（openehr-ruby / openehr-rails）側の変更は行わない（規律5）。多言語保持の必要が確定した場合は `docs/upstream-candidates.md` への追記で扱う。
