# 依存更新ログ（`skoba/anlage#65`）

bundler-audit の勧告を解消し、CI の `scan_ruby` を green に戻す。裁定 R-20261118-1（依存更新の認可はこの裁定）。連番節 R1〜。

---

## R1: 勧告の表、更新、検証（2026-11-18）

### 1. 勧告（実測）

入力: CI run `44275440831`（`ab61c7b`）の `scan_ruby` ジョブ（`bin/bundler-audit`）のログ。
ログは同じ勧告を複数回出すので（gem 名, GHSA）で重複を除いた。**15 gem・60 件**。

| gem | 現行版 | 勧告が求める修正版 | 更新後 | 件数 | GHSA | 対応する dependabot PR |
|---|---|---|---|---|---|---|
| actionmailbox | 8.1.3.1 | '~> 8.0.5, >= 8.0.5.2', '>= 8.1.4.1' | 8.1.4.1 | 1 | GHSA-5957-c7qm-m469 | #61 |
| actionpack | 8.1.3.1 | '>= 8.1.4.1'；'~> 8.0.5, >= 8.0.5.2', '>= 8.1.4.1' | 8.1.4.1 | 7 | GHSA-2586-8ghr-69fj、GHSA-2gff-2mmg-m73p、GHSA-gmj8-hvj3-49mw、GHSA-r9jg-fmfx-2gv6、GHSA-rwvh-fw6r-pwvp、GHSA-wm3x-v3qw-4jh3、GHSA-x6mj-8jx9-qhqv | #61 |
| actionview | 8.1.3.1 | '~> 8.0.5, >= 8.0.5.2', '>= 8.1.4.1' | 8.1.4.1 | 4 | GHSA-2p2f-4rq4-gjwc、GHSA-68p9-83h6-5wpj、GHSA-rq8q-p985-fjq7、GHSA-v6rj-xm57-3p59 | #61 |
| activestorage | 8.1.3.1 | '~> 8.0.5, >= 8.0.5.2', '>= 8.1.4.1' | 8.1.4.1 | 7 | GHSA-3f4q-8x5m-76v8、GHSA-3w93-6hmw-whh4、GHSA-4v2w-w6g6-f8f8、GHSA-f3w6-w445-fwh9、GHSA-hfr4-8rjc-97m2、GHSA-p2pm-g2h6-7j5j、GHSA-v924-7rp8-4mxh | #61 |
| activesupport | 8.1.3.1 | '>= 8.1.4.1'；'~> 8.0.5, >= 8.0.5.2', '>= 8.1.4.1' | 8.1.4.1 | 2 | GHSA-2w9f-fxwj-w2qf、GHSA-8474-xrp6-wh69 | #61 |
| addressable | 2.9.0 | '>= 2.9.1' | 2.9.2 | 7 | GHSA-4w5q-wg7v-w6gp、GHSA-539f-xcgw-2gjg、GHSA-8gmh-2hhj-2hv9、GHSA-9crm-g4mf-wc5j、GHSA-9f42-57jx-vpp3、GHSA-j82w-28jv-3pmj、GHSA-qq38-m9mg-xjj5 | 無し |
| crass | 1.0.7 | '>= 1.0.8' | 1.0.8 | 1 | GHSA-pq4g-8rxf-4g29 | #62・#63 に同乗 |
| loofah | 2.25.2 | '>= 2.25.3' | 2.25.3 | 6 | GHSA-345x-3rq2-jfrm、GHSA-h6v6-rg66-fqj4、GHSA-jcff-cj73-4w4f、GHSA-m3x9-938q-5767、GHSA-mf2j-8f84-cc9q、GHSA-p9wj-w8xq-vjx6 | #62・#63 に同乗 |
| msgpack | 1.8.4 | '>= 1.8.7' | 1.8.7 | 1 | GHSA-73v3-wf97-vpgj | #59（bootsnap の更新に同乗） |
| net-ssh | 7.3.3 | '~> 7.3, >= 7.3.4', '>= 8.0.0.beta3'；'~> 7.3, >= 7.3.5', '>= 8.0.0.rc2' | 7.3.10 | 7 | GHSA-3x7f-q7wf-fp73、GHSA-ggxh-cfwq-5xqc、GHSA-pfqh-p9vh-wx4p、GHSA-qpg5-fx6p-8cq3、GHSA-r75w-7fhp-84w8、GHSA-rpq3-v334-f5pm、GHSA-vxj5-fg65-x765 | 無し |
| nokogiri | 1.19.4 | '>= 1.19.5' | 1.19.7 | 3 | GHSA-3w22-6jfg-527w、GHSA-4p39-36wj-23h4、GHSA-v995-44v6-5fqm | #62・#63 に同乗 |
| puma | 8.0.2 | '~> 7.2.2', '>= 8.0.3' | 8.1.2 | 7 | GHSA-86xc-wrr9-xmmq、GHSA-jm4r-w4xx-qxw7、GHSA-m5xw-3hrw-qcmf、GHSA-r885-m39c-939g、GHSA-rf6g-xhmp-gm7v、GHSA-x646-wp7c-h9mg、GHSA-xw3h-pgr9-3vg7 | 無し |
| rack | 3.2.7 | '~> 2.2.25', '~> 3.1.23', '>= 3.2.8'；'~> 3.1.23', '>= 3.2.8' | 3.2.8 | 4 | GHSA-2j8w-xcrc-x985、GHSA-5v64-555j-wjxm、GHSA-p8x9-v4hv-2w4g、GHSA-wvg4-6p58-3gh3 | #62・#63 に同乗 |
| rails-html-sanitizer | 1.7.1 | '>= 1.7.2' | 1.7.2 | 2 | GHSA-cpgf-5mjf-73p7、GHSA-h7wh-q2qr-458c | #62・#63 に同乗 |
| sqlite3 | 2.9.6 | '>= 2.10.2' | 2.10.2 | 1 | GHSA-4fqr-96q8-xrfx | #58 |

- rails 本体の 5 gem（actionmailbox・actionpack・actionview・activestorage・activesupport、計 21 件）は
  rails 8.1.4.1 への更新 1 回で解消する。
- 「同乗」は、dependabot の PR が別の gem を主題にしつつ lock 上でその gem も上げていることを指す
  （各 PR の `gh pr diff` で確認）。addressable・net-ssh・puma は、どの dependabot PR にも入っていない。

### 2. 更新

ブランチ `chore/65-security-updates`（`ab61c7b` から分岐）。作業場所は `~/worktrees/anlage-security-updates`（裁定 D）。
gem ごとに `bundle update --conservative <gem>` を 1 回、1 コミット。変更は全て `Gemfile.lock` のみで、
**`Gemfile` は変えていない**。メジャー版が上がった gem は無い。

- `84923ab` Chore(deps): nokogiri 1.19.4 → 修正版（bundler-audit 勧告 3 件）（Refs #65）
- `45a692c` Chore(deps): loofah 2.25.2 → 修正版（勧告 6 件）（Refs #65）
- `c58a244` Chore(deps): rails-html-sanitizer 1.7.1 → 修正版（勧告 2 件）（Refs #65）
- `ac9c2b5` Chore(deps): crass 1.0.7 → 修正版（勧告 1 件）（Refs #65）
- `95260cc` Chore(deps): rack 3.2.7 → 修正版（勧告 4 件）（Refs #65）
- `a24cca0` Chore(deps): rails 8.1.3.1 → 8.1.4.1（actionpack・actionview・activestorage・activesupport・actionmailbox の勧告 21 件）（Refs #65）
- `dc1800d` Chore(deps): addressable 2.9.0 → 修正版（勧告 7 件）（Refs #65）
- `fe9debf` Chore(deps): msgpack 1.8.4 → 修正版（勧告 1 件）（Refs #65）
- `6042f11` Chore(deps): net-ssh 7.3.3 → 修正版（勧告 7 件）（Refs #65）
- `3c9aa20` Chore(deps): puma 8.0.2 → 修正版（勧告 7 件）（Refs #65）
- `14fc244` Chore(deps): sqlite3 2.9.6 → 修正版（勧告 1 件）（Refs #65）
- `d420b3d` Chore(deps): bootsnap を更新（勧告なし、dependabot PR 相当）（Refs #65）
- `05d4cf3` Chore(deps): selenium-webdriver を更新（勧告なし、dependabot PR 相当）（Refs #65）
- `10475de` Chore(deps): solid_queue を更新（勧告なし、dependabot PR 相当）（Refs #65）
- `0cab655` Chore(deps): rspec-rails を更新（勧告なし、dependabot PR 相当）（Refs #65）

- 順序: rails の更新は nokogiri・loofah・rails-html-sanitizer を巻き込む（最初の試行で実測）ので、
  それらを先に単独で上げ、rails を後にした。最初の試行の仮コミット 8 本は push 前に `git reset --hard main` で
  捨てて組み直した（自分の未 push ブランチ内）。
- 勧告なしの 4 gem（dependabot #59・#60・#62・#63 相当）も入れた。1 gem 入れるたびに全 suite を回し、
  4 回とも `236 examples, 0 failures, 3 pending`。外した gem は無い。
- dependabot との差:
  - **#61（rails）は `Gemfile` の制約を `"~> 8.1.3", ">= 8.1.3.1"` → `"~> 8.1.4"` に書き換える**。
    現行の制約のまま 8.1.4.1 に上がるので、制約の書き換えは入れていない（裁定 B の 3）。
  - #60 の selenium-webdriver は 4.52.0 を指すが、本ブランチは最新の 4.53.0。
  - dependabot の各 PR は推移依存（bigdecimal・minitest・irb・rubyzip ほか）も上げる。本ブランチは
    `--conservative` なので、指定した gem だけを上げている。

### 3. 検証（手元、クリーンな worktree）

- `bin/bundler-audit`: 勧告 11 gem 分の更新後に **No vulnerabilities found**。
- `bundle exec rspec`: 勧告分の更新後、および勧告なしの各 gem の追加後に 236 examples, 0 failures, 3 pending
  （js の system spec を含む。worktree をホーム配下に置いたので snap 版 Chromium の `attach_file` も通る）。
- 合否は PR の CI（4 ジョブ）で決める。結果は R2。
