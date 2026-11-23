# 作業ツリー分離の計画（ゲート報告用の案）

裁定 ID: R-20261117-4（2 節）。状態: **案**。承認までは何も実装しない。
対象は openehr-ruby・openehr-rails・anlage の 3 リポジトリ。本書が答える設計課題は
openehr-ruby `docs/backlog.md`「Session isolation」（`a041bf9` 時点）にある。

## 1. 課題（実測）

- cwd の取り違えが 3 件記録されている（openehr-ruby `CLAUDE.md`
  「Repository-context-dependent commands…」の incident log）。コマンドごとの
  `cd`／`-C`／`-R` は緩和策で、3 件とも防げなかった
- 同じマシンで 3 セッションが同時に動き、同じ項目を二重に書いた（backlog の傍証、2026-08-27）
- 並行負荷で anlage の system spec が偽陰性になった（`skoba/anlage#18`）
- 現状: worktree を使っているのは anlage だけ（`/home/skoba/src/anlage-worktrees/`）。
  openehr-ruby・openehr-rails は `git worktree list` が本体 1 行のみ。
  `~/.claude/projects/` にはリポジトリごとのディレクトリが 3 つあり、
  セッション自体はすでにリポジトリ別に起動されている

## 2. 案

| 論点 | 案 |
|---|---|
| セッションの単位 | 1 セッション = 1 リポジトリ。起動ディレクトリがそのリポジトリで、宛先が別リポジトリの依頼は着手せずに止まる（裁定の宛先欄で判定する） |
| 書き込みの場所 | 実装は必ず `/home/skoba/src/<repo>-worktrees/<slug>`。1 ブランチ = 1 worktree。本体の作業ツリーは既定ブランチのまま動かさず、docs のみの直接 push と fetch にだけ使う |
| 越境（読み取り） | 絶対パスと `git -C` で、相手リポジトリの**本体ツリー**を読む（`log`／`show`／`grep`／ファイルの閲覧）。報告に対象リポジトリと SHA を書く。相手のツリーでの `checkout`・`pull`・`bundle`・`rspec` は読み取りに含めない |
| 横断する作業 | 1 本の裁定を宛先ごとに分け、受け渡しは push 済みの SHA と Issue で行う。セッションの文脈を共有の前提にしない |
| Codex の納品先 | 当該 Issue の worktree。本体ツリーには納品させない。起動の直前に `pwd` を出力して worktree であることを確かめる。`codex exec resume --last` は使わない（incident 3 の原因） |
| 同時セッションの排他 | (a) ブランチ: git は同じブランチを 2 つの worktree に checkout させないので、worktree の作成が排他になる。(b) 既定ブランチ: 直接 push が non-fast-forward で拒否されたら fetch して rebase する。force はしない。(c) 作業: 着手時に worktree `<slug>` が既にあり、自分が作ったものでなければ、止まって例外報告。(d) 合否は CI で決める（並行負荷による手元の偽陰性を合否に使わない） |

## 3. 採らない案

- **1 セッションに 3 リポジトリを `--add-dir` する**: cwd の取り違えの原因そのもの
- **Agent ツールの `isolation: "worktree"` を土台にする**: 同じリポジトリの中の一時 worktree を
  作るもので、リポジトリをまたぐ取り違えには効かない。作成場所を
  `<repo>-worktrees/` に指定できるかは**未実測**。補助としての利用は妨げない
- **リポジトリごとのコンテナ**: 排他は強いが、snap 版 Chromium と rbenv の再構成が要る。
  得られる効果に対して重い

## 4. 実装するとしたら（承認後。各リポジトリ宛ての裁定が要る）

1. openehr-ruby・openehr-rails の `CLAUDE.md` に、anlage の「作業ツリー規律」と同旨の節を足す（越境なので各リポジトリのセッションが行う）
2. anlage の `CLAUDE.md`「作業ツリー規律」に、上の表の「越境（読み取り）」「Codex の納品先」「同時セッションの排他 (c)」を足す
3. openehr-ruby `docs/backlog.md` の当該項目に、本書への参照を足す

## 5. 裁定を求める点

1. 相手リポジトリのツリーでの実行（`bundle exec rspec` など）を、読み取り越境から外してよいか。
   外すと、gem 側の挙動の確認は gem 側のセッションに頼むことになる
2. Codex の再開方法。`resume --last` を禁じたあと、セッションを明示して再開する手段が
   あるかは**未確認**（Codex の現行の CLI を確かめていない）
3. `/home/skoba/src/openehr.code-workspace` は 5 フォルダを 1 つのウィンドウで開く構成に
   なっている。リポジトリごとにウィンドウを分ける運用に改めるか（人間側の作業）
4. 排他 (c) の「自分が作ったものか」の判定。セッションをまたぐと記憶が無いので、
   「既にあれば常に止まる」に倒すか、ログ（`docs/reports/`）の記載で判定するか
