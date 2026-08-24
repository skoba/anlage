# CI修復（lint常時red解消+テストジョブ追加）進行ログ

R1〜。

---

## R1: Step 0（起票）・Step 1（explore実測）

### Step 0: problem Issue起票

`skoba/anlage#16`「CI lintジョブが全runでfailure」を起票（`skoba/anlage#15`と相互参照）。

### Step 1: explore実測結果

**1. 直近runの実ログで失敗点を確定（`gh run view`実測）**:
`gh run list`で直近5件すべて`failure`を確認（`32642297597`等）。`gh run view 32642297597`の
ジョブ内訳: `scan_ruby` ✓・`scan_js` ✓・`lint` ✗。lintジョブのステップ内訳: `Set up job`✓→
`Checkout code`✓→`Set up Ruby`✓→`Prepare RuboCop cache`✓→**`Lint code for consistent
style`✗**→`Post Prepare RuboCop cache`（スキップ）→`Post Checkout code`✓→`Complete job`✓。

**当初仮説「bin/rubocop不在」は誤りと判明**: `ls -la bin/rubocop`で実在確認（実行可能、
266 bytes、標準的なRailsバインスタブ内容——`bundler/setup`＋`.rubocop.yml`への明示パス指定
のみ、破損無し）。GitHub Actions runのannotationsも「Lint code for consistent style」
ステップが実際に**実行されて**rubocop本来のオフェンスを検出していることを示している
（`Layout/SpaceInsideArrayLiteralBrackets`・`Style/StringLiterals`の実オフェンスが
annotation一覧に列挙されている——ステップが起動すらしていない場合はこの形のannotationは
出ない）。

**真の原因**: コードベース全体に対する`bin/rubocop -f github`実行で、**75 files inspected,
14 offenses detected, 8 offenses autocorrectable**（実行結果全文で確認）。内訳:
`db/migrate/20260813120002_create_openehr_rm_storage.rb`（`Layout/SpaceInsideArrayLiteralBrackets`
×8）・`db/migrate/20260813120003_create_openehr_rm_versioning.rb`（同×2）・
`config/routes.rb`（`Style/StringLiterals`×1）・`config/initializers/openehr.rb`（同×1）。
ローカルでのrubocop実行が変更ファイル単位（diffレビュー時等）に限られており、これらの
既存ファイルに対する全体実行が一度も行われていなかったため、CIが初めて全体を検出した
とみられる（推測。ただし全体実行結果自体は実測）。

**注目すべき構造的要因**: `Layout/SpaceInsideArrayLiteralBrackets`（12/14件、大多数）の
発生源は`db/migrate/`配下のマイグレーションファイル。本セッション中の複数の過去作業
（例: `#10`実装時のmigration実行）で、`db/schema.rb`の配列表記が`bin/rails db:migrate`
実行のたびに`[ "x" ]`→`["x"]`という無害な書式差分を生じることを繰り返し観測してきた
（過去のコミットログ参照）。これは、このRails環境（gemバージョン等）が生成する既定の
配列書式が`[ "x" ]`（スペース入り）であり、rubocop-rails-omakaseの既定
（`Layout/SpaceInsideArrayLiteralBrackets`有効＝スペース無し必須）と食い違っている
ことを示唆する。`.rubocop.yml`自体に「`[a, [b, c]]`ではなく`[ a, [ b, c ] ]`を使うなら
このcopを無効化」という趣旨のコメント例が既に用意されている（`.rubocop.yml`冒頭）。
この食い違いは今回の14件に限らず、今後もマイグレーション・スキーマ再生成のたびに
再発しうる構造的な要因である（対応方針はStep 2で判断）。

**2. scan_ruby / scan_js の成否**: 両方とも`✓`（green）。lint以外のredは無い。

**3. 全体オフェンス実数**: 上記のとおり14件（8件autocorrectable）。「異常な件数」ではなく、
todoベースライン化・直接修正いずれも実施コストは小さい規模。

### Step 2への引き継ぎ

14件という小規模な件数だが、裁定の明示的指示（「コード修正で黙らせない」）に従い
`.rubocop_todo.yml`でベースライン化する。ただし12/14件を占める
`Layout/SpaceInsideArrayLiteralBrackets`は上記の構造的要因（Rails生成コードの既定書式との
食い違い）を持つため、todoベースラインとは別に、この食い違い自体をbacklogへ記録する。

---

## R2: Step 2（修正）・Step 3（検証、コミット`92932b6`）

- `.rubocop_todo.yml`を`bin/rubocop --auto-gen-config`で生成し14件をベースライン化。
  `.rubocop.yml`に`inherit_from`追加。実行後`bin/rubocop -f github`のexit codeが0に
  なることをローカルで確認
- `.github/workflows/ci.yml`: `test`ジョブ新設（`bin/rails db:test:prepare` +
  `bundle exec rspec`全suite）。`actions/checkout@v6→v7`・`actions/cache@v4→v5`
  （`openehr-ruby`/`openehr-rails`との版数整合、Node.js 20非推奨警告の解消）
- ローカル検証: `RAILS_ENV=test bin/rails db:test:prepare`正常終了、
  `RAILS_ENV=test bundle exec rspec` 97 examples, 0 failures
- push後、`gh run watch`で実際のCI runを監視: **run `32687777074`、全4ジョブ
  （`test`・`scan_js`・`lint`・`scan_ruby`）green**（`gh run view`で
  `conclusion: success`・`headSha`がコミット`92932b6`と一致することを確認）
- `test`ジョブ（system spec含む全suite）は標準設定のまま一発でgreen化した。
  開発機sandboxで観測されていた`Errno::EPERM`はこの開発機固有の制約であり、
  GitHub Actions runnerには再現しなかった（「2回まで試行」のフォールバックは
  不要だった）
- `docs/backlog.md`に「CI status (verified, 2026-08-24)」節を追加（`openehr-ruby`/
  `openehr-rails`と同型）。`.rubocop_todo.yml`の段階的解消方針と、
  `Layout/SpaceInsideArrayLiteralBrackets`の構造的要因（Rails生成コードの既定書式との
  食い違い、対応方針は未判断）を記録
- `CLAUDE.md`に報告規約1行追加（push報告にはCI run結果を含める、redは例外報告）

## 完了の意味

凍結受入条件「デモクエリ spec green」が、push ごとに機械検証される状態になった
（受入条件の実効化）。
