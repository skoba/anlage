# S4（自然言語から AQL）の進行記録

計画書: `docs/design/s4-nl-aql-plan.md`。裁定 ID: R-20261127-14。実測と見込みを分けて書く。

## R1 段 1: 文の組み立て、選択の検査、説明の文（2026-11-27。`skoba/anlage#224`）

基準点: anlage main `c786e55`。gem を足していない。外を呼んでいない。

### 自己承認した判断

| # | 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|---|
| P1 | カードの文の「型」に何を書くか | 条件の種類の言葉（数値／値集合／日時／文字列。`QueryBuilder::Builder.kind`） | RM の型の名前（DV_QUANTITY など） | LLM が選ぶのは演算子で、演算子は条件の種類で決まる（`Builder::OPERATORS`）。外部値集合の DV_CODED_TEXT（code_list が空）は、ビルダーでは文字列として扱う。RM の型を渡すと、ここがずれる |
| P2 | 用語マスター由来の文言を、どう落とすか | 値集合の表示名は、コードが at-code のものだけを送る | カードに「用語マスター由来」の印を足す | 印を足すのはパスカードのスキーマの変更（ゲート）。実測: fixture の 6 つの OPT から抽出したカードで、`code_list` に at-code でないコードは 0 件 |
| P3 | P2 の spec の入力 | 実物の「診断確度」のカードの値集合に、実物の収縮期のカードの binding のコード（SNOMED CT）を 1 行足した形 | 外の用語のコードを持つ OPT を作る | そういう実物の OPT が fixture に無い（上の実測）。アーキタイプの ID、at-code、パスは作っていない。足した 1 行のコードは実物の binding、表示名は「外の用語の表示名」という目印の文字 |
| P4 | 応答の中の値集合の値 | 表示名だけを受ける。コード（at0074）を書いてきたら、はねる | コードも受ける | LLM 分業原理。コードはカードから引く。LLM にはコードを渡していないので、書いてきたコードは推測 |
| P5 | 説明の文に、値集合のコードを書くか | 書く（「疑い（at0074）」） | 表示名だけ | 計画書 7 節の見出しのとおり。説明は画面に出すだけで、外には送らない |

### Red（実行して失敗を確かめた）

```
$ bundle exec rspec spec/lib/nl_query/prompt_spec.rb
NameError:
  uninitialized constant NlQuery
0 examples, 0 failures, 1 error occurred outside of examples

$ bundle exec rspec spec/lib/nl_query/selection_parser_spec.rb
0 examples, 0 failures, 1 error occurred outside of examples   （uninitialized constant NlQuery::SelectionParser）

$ bundle exec rspec spec/lib/nl_query/explanation_spec.rb
NameError:
  uninitialized constant NlQuery::Explanation
0 examples, 0 failures, 1 error occurred outside of examples
```

`Prompt` は、実装のあとの 1 回めで 1 例が落ちた。spec に書いた容器の名前がセッションの推測（「検体検査結果／検体検査分析対象」）で、
実物は「検体検査結果／検査分析結果」だった。spec を実測に合わせた。

```
expected: [..., "6 | 分析名 | 検体検査結果／検体検査分析対象 | 文字列 |  |  | LabResultReport"]
     got: [..., "6 | 分析名 | 検体検査結果／検査分析結果 | 文字列 |  |  | LabResultReport"]
11 examples, 1 failure
```

### Green

```
$ bundle exec rspec spec/lib/nl_query
37 examples, 0 failures
$ bundle exec rubocop app/lib/nl_query spec/lib/nl_query spec/support/nl_query_cards.rb
7 files inspected, no offenses detected
```

### 実測で分かったこと（段 2 に持ち越す）

問いの文をそのままパスカード検索（`Opt::PathcardSearch`）にかけたときの候補（CardiologyEncounter・ProblemList・LabResultReport を入れた索引で）:

| 問い | 候補 | 足りないカード |
|---|---|---|
| 診断確度が「疑い」の傷病名 | 診断確度、プロブレム・診断名、日時の 4 枚 | 無い |
| 収縮期血圧が 140 mmHg 以上の記録 | 収縮期、拡張期 | 無い |
| 発症が 2025 年の病名を、出所の文書名と発症日時つきで | 発症日時、ほかの日時 2 枚 | **プロブレム・診断名**（別名表の「病名」は、語の全体が一致したときだけ引ける） |

文の全体で検索すると、表示する項目のカードが候補に入らない問いがある。段 2 で、候補の取り方を決める。

### カードの文の大きさ（実測）

3 つのテンプレートのカード 11 枚をすべて候補にして、入力は 580 文字、指示文は 1,362 文字。トークンの数は測っていない（段 4 の前に測る）。

## R2 段 2: 汎用のアダプタの口、記録した応答、オンとオフ、回数、問い合わせの流れ（2026-11-27。`skoba/anlage#228`）

gem を足していない。外を呼んでいない。

### 実測: 問いの文の全体で検索すると、候補が足りない

初期データ（`rake demo:reset`。5 テンプレート・18 枚）で、aql の 12 問の文を `Opt::PathcardSearch.call` にかけ、
問いの `cards`（問いが指すカード）が候補に入るかを見た。

| 問い | 検索で当たった枚数 | 入らなかったカード | 同じテンプレートに広げたとき |
|---|---|---|---|
| a001・a002・a005・a009・a010・a011・a012・a014 | 6〜9 | 無い | 無い |
| a003「2型糖尿病または高血圧症の記録を、出所の文書名つきで」 | 2 | at0002（プロブレム・診断名） | 入らない |
| a004「空腹時血糖の値」 | 0 | at0024、at0001（分析名、分析結果） | 入らない |
| a006「病名に「糖尿病」を含む記録を、出所の文書名つきで」 | 0 | at0002 | 入らない |
| a013「発症が 2025 年の病名を、出所の文書名と発症日時つきで」 | 3 | at0002 | 入る |

12 問のうち 4 問で、必要なカードが候補に入らない。理由: 問いの文には値（「糖尿病」「空腹時血糖」）が多く、項目の名前が少ない。
別名表は、語の全体が一致したときだけ引ける（「病名」だけなら引けるが、文の中の「病名」は引けない）。

### 自己承認した判断

| # | 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|---|
| C1 | 候補のカードの取り方（**計画書 1 節の 1 から変えた**） | 索引が 40 枚までなら、索引のカードをすべて候補にする（検索で当たったカードを前に）。40 枚より多いときは、当たったカードと、同じテンプレートのカードに絞る | 検索で当たったカードだけを候補にする（計画書のとおり） | 上の実測。当たったカードだけでは、4/12 問で、正しい選択が作れない。18 枚をすべて送っても入力は小さい（R1 の実測: 11 枚で 580 文字） |
| C2 | 40 枚の上限 | 40 | — | 根拠は弱い（見込み）。初期データの 18 枚、紹介状を入れた 44 枚（jp_referral が 26 枚）のあいだに置いた。索引が大きいときの候補の取り方は、検索の段 C・E（保留）の主題で、ここでは決めない |
| C3 | 「LLM なし」の持ち方 | アダプタの 1 つではなく、オフの状態（`Llm::Settings#on?` が偽） | `Adapters::None` | 計画書 3.1 節（R-20261127-14 で直した形） |
| C4 | 回数に数えるもの | アダプタを呼んだ回数。成功も失敗も 1 回。記録した応答も数える | 外を呼ぶアダプタだけ数える | 作りを 1 つにする。記録した応答で、上限の動きを確かめられる |
| C5 | 回数のファイルが壊れているとき | 上限に達した扱い（呼ばない） | 0 回として呼ぶ | 費用の歯止めなので、数えられないときは、呼ばない側に倒す |
| C6 | アダプタが `Llm::Error` でない例外で落ちたとき | 例外のクラスの名前だけを理由に出す | 例外の文を出す | 例外の文に、鍵やヘッダが入りうる（R-20261127-14: 鍵の値を、画面とログに出さない） |
| C7 | spec の応答 | セッションが手で書いた JSON を、記録の形で置く（`source: hand_written`、`model: hand-written`） | — | まだモデルを呼んでいない。**モデルの応答ではない**。実際の応答の記録は、段 4 で、人間が鍵を渡したときに取る |

C1 の影響: 測定の「接地あり」の腕で渡すカードは、初期データでは、索引の 18 枚すべてになる。「検索で絞った候補」ではない。
測定の報告の限界に書く（索引が大きいときに同じ成績になるとは言えない）。

### Red（実行して失敗を確かめた）

```
$ bundle exec rspec spec/lib/llm
NameError:
  uninitialized constant Llm
0 examples, 0 failures, 3 errors occurred outside of examples

$ bundle exec rspec spec/lib/nl_query/candidates_spec.rb spec/lib/nl_query/runner_spec.rb
NameError:
  uninitialized constant NlQuery::Candidates
NameError:
  uninitialized constant NlQuery::Runner
0 examples, 0 failures, 2 errors occurred outside of examples
```

実装のあとの 1 回めで、`runner_spec` の 2 例が落ちた。spec の書き方の誤り（ハッシュを、括弧なしでメソッドに渡して、キーワード引数になった）。

```
ArgumentError:
  wrong number of arguments (given 0, expected 1)
# ./spec/lib/nl_query/runner_spec.rb:29:in 'RSpec::ExampleGroups::NlQueryRunner#record'
78 examples, 2 failures
```

### Green

```
$ bundle exec rspec spec/lib/llm
22 examples, 0 failures
$ bundle exec rspec spec/lib/nl_query/runner_spec.rb
13 examples, 0 failures
$ bundle exec rubocop app/lib/llm.rb app/lib/llm app/lib/nl_query spec/lib/llm spec/lib/nl_query
17 files inspected, no offenses detected
```

a002 の問いは、記録した応答（手で書いた選択）から、参照 AQL と同じ形の AQL になり、実行すると期待行の 7 行が返る（`runner_spec`）。
