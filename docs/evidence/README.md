# 証跡（Evidence）

デモ・リリース・upstream修正の視覚的証跡を保存する。
命名: `YYYY-MM-DD--<対象>--<内容>.png`。
出所（OPT名・gem版数・関連Issue/PR）を本ファイルの表に1行記録する。

## 索引

| ファイル | 出所 | 備考 |
|---|---|---|
| [2026-08-22--labresultreport--cluster-labels-after-rails-0.4.1.png](2026-08-22--labresultreport--cluster-labels-after-rails-0.4.1.png) | `spec/fixtures/opt/LabResultReport.opt`、openehr-rails 0.4.1（[skoba/openehr-rails#25](https://github.com/skoba/openehr-rails/issues/25) / [PR#26](https://github.com/skoba/openehr-rails/pull/26)）| Part B スモーク(a)。#25修正効果の直接実証（宿主アーキタイプ誤解決の既知バグを保有するfixtureで、0.4.1適用後に試着室が正しいラベルで描画されることを確認）。beforeのスクリーンショットは未取得だが、`docs/design/pathcards-schema-v1.md` カード2の記録（0.4.0時点の誤解決の実測）が文書上のbeforeとして機能する |
| [2026-08-22--problemlist--c-code-reference-parse-after-openehr-2.3.1.png](2026-08-22--problemlist--c-code-reference-parse-after-openehr-2.3.1.png) | `spec/fixtures/opt/ProblemList.opt`、openehr 2.3.1（[skoba/openehr-ruby#30](https://github.com/skoba/openehr-ruby/issues/30) / [PR#34](https://github.com/skoba/openehr-ruby/pull/34)）| Part B スモーク(b)。従来`NoMethodError`でクラッシュしていたOPTが、gem 2.3.1適用後に試着室まで到達することを確認。beforeは未取得（クラッシュ自体はupstream Issue #30に再現手順として記録済み） |
