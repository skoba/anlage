# CLAUDE.md — Anlage

## プロジェクト概要

Anlageは、openehr-rails-startupから生成されたopenEHRベースEHRの参照実装である。

- 4層構成: openehr-ruby → openehr-rails → openehr-rails-startup → **Anlage**（本リポジトリ）
- 中核思想: **クリニカルモデルを置けば動くEHR**。価値の源泉はコード生成ではなく実行時動的性である
- OPTを実行時に投入すると、フォーム生成・検証・保存・FHIR R5ファサードが即座に機能する

## 絶対規律（全セッション・全作業に適用。違反したらその場で停止して報告）

本節が規律の**正本**である。各 `claude-code-prompt_*.md` に記載された規律は写しであり、改定時は本ファイルを先に更新し、プロンプト側を追随させる。

1. **探索→計画→承認→実装**: 計画の承認前にコードを書かない
2. **No API guessing**: openehr-ruby / openehr-rails / Anlage のAPIは、ソースコード引用（ファイルパス＋該当コード断片）で確認してから使う。推測でメソッドを呼ばない。確認できないものは「不明」と申告する
3. **実物主義**: テスト用OPT・アーキタイプID・at-code・パスは、CKM公開アーキタイプ由来の実物のみを使う。捏造は禁止。必要なOPTが手元にない場合は捏造せず、人間にArchetype Designer経由での作成を依頼する
4. **TDD（t-wada方式）の徹底**: すべての実装コードは、RSpecで書かれた失敗するテストから始める
   - サイクル: テストTODOリスト作成 → 一つ選ぶ → **Red**（失敗するテストを書き、実行して失敗を確認）→ **Green**（最小の実装で通す。仮実装→三角測量→明白な実装を使い分ける）→ **Refactor**（テストが緑のまま整理）→ TODOリスト更新
   - テストが先、実装が後。順序の逆転とRedの実行確認のスキップは禁止
   - リファクタリングはテストが緑の状態でのみ行う
   - テストのフィクスチャ・at-code・パスも規律3（実物主義）に従う
   - コミットはGreenまたはRefactor完了時点。1コミット＝おおむね1サイクルの薄切り＋テスト。テストを伴わない実装コミットは禁止
   - テストは仕様の実行可能なドキュメントとして書く（describe/contextの記述に日本語を使ってよい）
5. **層規律**: 変更はAnlage内に限る。gem（openehr-ruby / openehr-rails）とopenehr-rails-startupのコードは変更しない。汎用的価値のある発見は `docs/upstream-candidates.md` に追記する（追記のみ）
6. **コンテンツ防火壁**: 用語マスター等のライセンス対象コンテンツをリポジトリにコミットしない。コード化するのはローダーと取得手順のみ。ライセンスコンテンツを埋め込みベクトル化・外部API送信しない
7. **LLM分業原理**: 生成系（LLM）が供給してよいのは対応付けと値の抽出のみ。意味・構造・コード・制約は、常にOPT・CKM・用語マスターから実行時に引く
8. **スコープ規律**: 指示外の新機能・改善案は実装せず `docs/ideas-2027.md` に記録して先へ進む

## Codexとの分業（openehr-ruby CLAUDE.mdと同旨）

- **Codexはworking treeの納品のみ行う。コミットはしない。** Claude Codeが
  承認済み計画との差分をレビューした上で、出所を示すtrailer（例:
  `Implemented-by: Codex`）付きでコミットする
- **複数著者にまたがるコミットは両方のtrailerを持つ**: Claude Codeが
  Codexの納品物を再構成・分割する場合（同じ行に乗った無関係な修正を
  別コミットへ切り出す等、Codexが単体では生成していない中間コード状態を
  構成する場合）、結果のコミットは `Implemented-by: Codex` と
  `Restructured-by: Claude Code` の両方を持つ。Codexの納品に無い
  コード状態を含むコミットにCodex単独のtrailerを付けない

## Issue-driven visibility

Anlageでは「1 issue = 1 branch」は要求しない（WP駆動の進行と両立させる）。
ただし以下は着手前・発覚時にGitHub Issueを立てる:

- **(a) 実装目標**: WP・スライス級の目標。Acceptance criteriaを明記し、
  関連するplan文書（`docs/design/`）と相互参照する。クローズはcriteria充足時
  （spec green・デモ経路通過など検証可能な条件）
- **(b) 課題**: バグ・障害・設計上の未解決。specで閉じられるものは
  red-green（またはregression pin）で解決する
- **(c) upstream観察**: 従来どおり `docs/upstream-candidates.md` が一次置き場。
  根拠が揃ったらgem側リポジトリへ起票する（Anlageには立てない）。台帳に
  起票先リンクを残す

コミットメッセージ・PRには関連Issueを `Refs #N` で記載する
（`Fixes #N` はその変更単独でcriteriaを満たす場合のみ）。
docsのみ・軽微修正はIssue不要（従来どおり）。

タスクの完了報告は origin への push 後に行い、報告に push 済みの SHA を
含める。ローカルのみの状態（コミット済みだが未push）で「完了」と報告
しない。

push報告には `git log --oneline <before>..<after>` によるコミット列
そのものを含める。「〜を含む」等の要約語だけで複数コミットをまとめない。

push を含む報告には当該 SHA の CI run 結果（run ID・green/red）を含める。
red は例外報告として扱う（2026-08-24導入。CI整備後、凍結受入条件の
機械検証が実効化したことを受けて追加）。

## 報告の3種別（中継コスト削減。2026-08-23導入）

チャットへの報告は以下の3種に分け、種別ごとに扱いを変える:

- **(a) ゲート報告** — 承認・裁定が必要な停止点（計画承認、マージ/push
  承認、仕様の曖昧さの裁定等）。即時・単独で出す。他の報告と束ねない
- **(b) バンドル報告** — フェーズ／Issue完了時。進行記録を連結した1通
  にまとめて出す
- **(c) 例外報告** — 失敗・停止・裁定を要する発見。即時に出す

進行中の中間記録（Red/Green確認・実測値・小さな判断等）はチャット出力
ではなく `docs/reports/<phase>-log.md` への追記コミットとして残す
（連番節: R1, R2…。pushまで含めて記録完了とする）。「コミット3本ごと」
のような定期チャット報告義務は課さない。バンドル報告の冒頭には
「本フェーズのログ: `docs/reports/<file>`（R1〜Rn）」と明記し、ゲート
判断に必要な要約は本文に含める。

## 評価データの人間レビュー中の編集範囲（2026-08-25導入）

評価データのゴールド本体（`query`/`expected_archetype_id`/`expected_at_code`/
`notes`等のレビュー記載フィールド）は、人間レビュー進行中は人間の専有領域。
エージェントは読み込み系（実行・集計・レポート追記）およびspec側（期待値の
実測追従）のみ変更可とし、ゴールド本体への変更は明示指示がある場合に限る
（WP4の`spec/fixtures/pathcards_eval_seed.yml`並行編集運用の明文化）。

## 主要ドキュメント

- `docs/upstream-candidates.md` — gem / startup への上流候補の記録。**起票前の観察ログ**
  として運用する: 気づいた時点では自由に書いてよいが、再現手順または実測根拠
  （file:line・実行結果）が揃うまでは Issue を起票しない。揃った時点で openehr-ruby /
  openehr-rails 側に Issue として昇格させ、昇格済みの項目には台帳側にその Issue への
  リンクを残す（例: `2026-08-22` の #6a〜#6b・#5・#1 昇格時のリンク記載が実例）
- `docs/ideas-2027.md` — スコープ外アイデアの退避先
- `docs/design/` — 設計文書（各WPの成果物）

## 進行中のワークストリーム

- **セマンティックパスカード基盤**: `claude-code-prompt_semantic-pathcards.md` — パスカード関連の作業は、必ずこのプロンプトを読んでから着手する（自動読み込みはしない。セッション冒頭で明示的に参照すること）
- マイルストーン: **2026-11-05 デモビルド凍結 ／ 2026-11-12 デモ本番**（医療情報学連合大会チュートリアル）／ **2026-12 世界公開**（OSS一式・動画・被覆レポート）
- 11/5凍結の受入条件: `bundle exec rspec spec/demo/` green（デモクエリ全件の期待件数一致。`docs/demo/aql-queries.md`・`docs/design/demo-queries-plan.md` 5節）。**デモクエリ4件全てを実際のフォーム保存経路（POST）経由のspecで検証済み**
- `README.md`の「Current focus」節は各フェーズのゲート承認時に更新する

## ビルド・テストコマンド

- テスト実行: `bundle exec rspec`（一括実行可。2026-08-23、`patient_blood_pressure.opt`
  fixture復元〔#3〕以降は全suite一括でgreen。binstubは無い）
