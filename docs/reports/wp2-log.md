# WP2進行ログ

WP2（パスカード抽出器）実装フェーズでチャットへ送信した中間報告・区切り報告・完了報告の全文を、
R1〜R8として時系列に転記する（2026-08-23導入の報告規約〔CLAUDE.md「報告の3種別」〕の遡及適用）。
本ログはWP2の進行記録として完結しており、以後の参照はチャット履歴ではなく本ファイルを一次とする。

---

## R1: Issue起票・Codex分業規約（WP2計画承認直後）

CLAUDE.mdへCodex分業規約を追補（`99d0948`）。

Issue起票: [#7](https://github.com/skoba/anlage/issues/7)（canonical混在problem）→ [#8](https://github.com/skoba/anlage/issues/8)（WP2実装goal）

`wp2-plan.md`の関連Issue欄・プレースホルダーを実Issue番号に更新（`c72a8a1`）。

origin/main SHA: `c72a8a1`

---

## R2: 中間報告（3コミット区切り、TODO 1〜3）

コミット列（`bbfd7d9..a1d51f6`）:
```
a1d51f6 feat: identity block via self-walked definition tree (TODO 2+3)
bbfd7d9 Record CObject#path node_id-bracket omission for embedded C_ARCHETYPE_ROOT
cfc59a4 spec+feat: PathcardExtractor returns schema-v1 shaped cards (TODO 1)
```

origin/main SHA: `a1d51f6`

**進捗**: TODO 1〜3完了。`bundle exec rspec` 59 examples, 0 failures。

**特筆事項**: TODO 2着手前の実測で、`CObject#path`が埋め込みC_ARCHETYPE_ROOT自身のnode_idブラケットを欠落させる実バグを発見（`docs/upstream-candidates.md` 8項に記録）。これによりFieldExtractorが`.path`を使わず自前でpath構築している理由が裏付けられ、抽出器も同方式（`.path`不使用）で実装した。また、実測したLabResultReportのpathがスキーマv1文書のカード2記載値と完全一致したため、TODO 11で予定していた「実測差異があればschema文書2節を更新」は不要と判明。

Codexの1回目の応答は計画確認で停止したため、承認を明示して再開した（`codex exec resume --last`）。納品後、rubocop 1件（配列括弧内スペース）を自動修正。

---

## R3: 中間報告（TODO 6、occurrences意味論の裁定を含む）

コミット列（`a1d51f6..82818bb`）:
```
82818bb feat: DV_QUANTITY constraints, ELEMENT-scoped occurrences (TODO 6)
```

origin/main SHA: `82818bb`

**進捗**: TODO 1〜3、6完了（TODO 4・5〈DV_CODED_TEXT関連〉は未着手のままTODO 6を先行）。`bundle exec rspec` 59 examples, 0 failures。

**特筆事項**: `constraints.occurrences`の意味論（ELEMENT自身 vs value制約自身）で実測値の食い違いを発見し、ご裁定をいただいた。反映内容:
- `wp2-plan.md` 1.3節・`pathcards-schema-v1.md` 1節へ定義を明記
- カード2・カード3の`occurrences`値と引用行を訂正（カード3: `{1,1}`→`{0,1}`、カード2: `{0, null}`）
- WP0未確認事項3（occurrences欠損時の挙動）もカード2の実データで固定: 例外なく`upper: null`になることを確認

---

## R4: 中間報告（3コミット区切り、TODO 4・5・7・8）

コミット列（`82818bb..3a26bcb`）:
```
3a26bcb feat: value_set_binding from parsed CCodeReference (TODO 8)
d484e22 feat: DV_CODED_TEXT local code_list constraints (TODO 7)
dbd9a05 feat: labels/descriptions with 2-stage untranslated detection (TODO 4+5)
```

origin/main SHA: `3a26bcb`

**進捗**: TODO 1〜8完了（TODO 9〜14が残り）。`bundle exec rspec` 66 examples, 0 failures。

**特筆事項**: TODO 7実装中、Codexが「DV_CODED_TEXTのvalue制約は`CCodePhrase`/`CCodeReference`が直接ではなく、`DV_CODED_TEXT`の`C_COMPLEX_OBJECT`に`defining_code`属性でラップされている」という構造を発見（`ProblemList.opt:563-575`で実データ確認）。この`defining_code_constraint`ヘルパーはTODO 8（CCodeReference）でも再利用でき、設計が綺麗に収束した。

---

## R5: 区切り報告（TODO 11完了 — 必須報告ポイント）

コミット列（`de402ac..99c2dcd`）:
```
99c2dcd feat: provenance + full-card golden equality against WP1 samples (TODO 11)
de402ac feat: code_binding via term_bindings re-parse merged into cards (TODO 10)
2fb6581 feat: Opt::SafeParser.safe_document (TODO 9)
```

origin/main SHA: `99c2dcd`

**TODO 11の結果**: サンプルカード3枚（CardiologyEncounter at0004・LabResultReport at0001（埋め込みCLUSTER）・ProblemList at0002）すべてで、抽出器の実測値がWP1手作業抽出カードと**完全一致**した。TODO 6で修正した`occurrences`以外に新たな食い違いは発見されず、`pathcards-schema-v1.md` 2節への追加修正は不要だった。

`bundle exec rspec` 74 examples, 0 failures。

---

## R6: 区切り報告（TODO 12完了 — 必須報告ポイント）

コミット列（`99c2dcd..b67284e`）:
```
b67284e Add WP2 TODO 12 demo evidence: ProblemList registration saves pathcards
14dc963 feat: pathcards column + registration hook in TemplatesController#create (TODO 12)
```

origin/main SHA: `b67284e`

**TODO 12の結果**: `templates.pathcards`（JSONカラム）を追加し、`TemplatesController#create`の登録成功時に`Opt::PathcardExtractor`を呼ぶフックを実装（fail-soft設計、preview非対象、checksum重複時は非再抽出、supersede時は新版に新カード）。`bundle exec rspec` 75 examples, 0 failures。

**デモ実演**: 実際にProblemList.optをドロップゾーンへ投入し、登録後に`pathcards`が保存される（6カード抽出）ことを確認。証跡を`docs/evidence/`へ追加（README索引更新込み）。

---

## R7: WP2実装 完了報告（TODO 14完了）

コミット列（`3a26bcb..1f1c802`）:
```
1f1c802 test: golden snapshot regression net for all 3 fixtures (TODO 14)
fcae9f5 feat: extraction report of untranslated suspects (TODO 13)
b67284e Add WP2 TODO 12 demo evidence: ProblemList registration saves pathcards
14dc963 feat: pathcards column + registration hook in TemplatesController#create (TODO 12)
99c2dcd feat: provenance + full-card golden equality against WP1 samples (TODO 11)
de402ac feat: code_binding via term_bindings re-parse merged into cards (TODO 10)
2fb6581 feat: Opt::SafeParser.safe_document (TODO 9)
```

origin/main SHA: `1f1c802`

`wp2-plan.md`のテストTODOリスト（1〜14）が全て完了。`bundle exec rspec` 79 examples, 0 failures。`bundle exec rubocop`（実装＋spec関連14ファイル）オフェンスなし。

**主な設計上の決定（実装中に発見・確定したもの）**:
- `CObject#path`の埋め込みC_ARCHETYPE_ROOTブラケット欠落バグを発見（`docs/upstream-candidates.md` 8項）→ FieldExtractor方式で自前path構築
- `constraints.occurrences`はELEMENT自身のもの（裁定どおり）。スキーマ文書の該当箇所を訂正
- DV_CODED_TEXTの値制約は`defining_code`属性でラップされている構造を発見・実装
- CardiologyEncounterに2件のSNOMEDリテラルコードが実在することが判明し、C2ルール（合計1件まで）に従ってat0005側をマスク

`skoba/anlage#8`（WP2実装Issue）のAcceptance criteria（TODO 1〜14のspec緑＋デモ経路通過）は満たされているが、Issueのクローズは人間確認の上で依頼した。

---

## R8: Issue #8/#6 クローズ報告（「続けてください」応答）

Issue状態を整理。

- **Issue #8**（WP2実装本体）→ **CLOSED**（Fixes #8コメント付き）
- **Issue #6**（WP2 goal旧マイルストーン）→ **CLOSED**（#8への引き継ぎ完了を明記）

**残っているOPEN Issue**（いずれも意図的に未解決のまま、正常な状態）:
- #7 canonical混在時のpath不一致（WP2計画で意図的に切り出した留保事項）
- #5 デモクエリの実行可能spec化
- #4 診療情報提供書OPTの受け入れスモーク（fixture入手待ち）

WP2（パスカード抽出器）はこれで完全に完了。
