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

## R3 段 3: クエリビルダーの画面に「文で問う」を足す（2026-11-27。`skoba/anlage#231`）

gem を足していない。外を呼んでいない。

### 自己承認した判断

| # | 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|---|
| U1 | 文で問う口（**URL を 1 つ足した**） | `POST /queries/ask`。選択ができたら、選択を URL のパラメータに直して `GET /queries/new` に移る（303） | `GET /queries/new?nl=…` の中で LLM を呼ぶ | GET で呼ぶと、読み込み直しや先読みのたびに LLM を呼ぶ（費用）。選択ができたあとの状態は、これまでどおり URL に持つ（共有できる。読み込み直しても LLM を呼ばない。request spec で固定） |
| U2 | 選択を作れなかったときの返し方 | 同じ画面を 422 で返す | 200 で返す／flash を付けて移る | 200 では、Turbo がフォームの POST の結果を画面に出さない（下の実測）。flash は、状態をサーバーに持つことになる |
| U3 | 選択を作れなかったときに出す候補 | `NlQuery::Candidates` の候補（初期データでは、索引の 18 枚すべて） | 問いの文で検索した結果だけ | R2 の実測（問いの文の全体では、検索に当たらない問いがある） |
| U4 | 説明を、いつ出すか | 文で問うから移ってきた選択（URL に `nl` がある）のあいだ出す。利用者が条件を直すと、説明も、いまの選択に合わせて変わる | 最初の選択の説明を固定して出す | 説明は「何をどう引いたか」。実行する AQL と食い違わないのが正しい。文言は「この選択は、文で問う（LLM）から始めました」（直したあとも偽にならない言い方） |
| U5 | 文字列の「いずれか」（MATCHES）の入れ方 | 一致の条件を「または」でつないだ形にする | 画面に、文字列の「いずれか」の入力を足す | 画面に入力が無い。組まれる AQL は、`MATCHES {a, b}` ではなく `(= a OR = b)` になる。実測: a003 の形（2型糖尿病、高血圧症。テンプレートつき）で、どちらも 7 行で、行は同じ |
| U6 | オンにする方法の案内 | `docs/nl-query.md` を足し、画面から名前で指す | README に節を足す | README は、書く側が英語を主にした構成に直している最中（PR #216）。README への記載は、外を呼ぶアダプタが入る段 4 で行う（計画書 10.4 節） |

### Red（実行して失敗を確かめた）

```
$ bundle exec rspec spec/lib/nl_query/query_params_spec.rb
NameError:
  uninitialized constant NlQuery::QueryParams

$ bundle exec rspec spec/requests/queries_nl_spec.rb
  1) … オフであることと、オンにする方法への案内が出る …
       expected: ["文で問う"]
            got: []
  4) … 文で問う口に直接送っても、LLM は呼ばれず、理由が出る
       expected the response to have status code :ok (200) but it was :not_found (404)
  6) … 問いを入れると、表示する項目と条件が入った状態（URL）に移る。実行はまだ
       expected the response to have status code :see_other (303) but it was :not_found (404)
```

実装のあとで、穴を 2 つ見つけ、テストを足して Red を取ってから直した。

1. 選択を作れなかったあと、手で選んだ選択にも「LLM から始めました」の説明が付く（問いを、隠しの入力で持ち回っていた）
2. 画面から来た、片方が空の日時の範囲で、説明が「 以降、2026-01-01 より前」になる

```
  2) … 選択を作れなかったあと、手で選んだ選択には、「文で問うから始めました」の説明を付けない
       expected: nil
            got: #<Nokogiri::XML::Element name="input" … name="nl" value="診断確度が「疑い」の傷病名">
  3) NlQuery::Explanation 画面から来た、片方が空の日時の範囲 …
       expected "…条件: 「発症日時」が  以降、2026-01-01 より前。…" to include "条件: 「発症日時」が 2026-01-01 より前。"
23 examples, 3 failures
```

### 実ブラウザの spec で分かったこと

request spec は 200 で通っていたが、実ブラウザでは、選択を作れなかったときの画面が出なかった。

```
$ bundle exec rspec spec/system/demo_nl_query_spec.rb
  1) … 選択を作れなかったときは、理由が出て、候補のカードから手で選んで続けられる
       expected to find css "#nl_reason" but there were no matches
3 examples, 1 failure
```

Turbo は、フォームの POST への 200 の HTML を画面に出さない（`app/javascript/application.js:2` が `@hotwired/turbo-rails` を読む）。
request spec を 422 に直して Red を取り（`expected the response to have status code 422 but it was 200`）、実装を合わせた。

### Green

```
$ bundle exec rspec spec/system/demo_nl_query_spec.rb spec/requests/queries_nl_spec.rb
18 examples, 0 failures
$ bundle exec rspec spec/requests/queries_nl_spec.rb spec/lib/nl_query/explanation_spec.rb spec/requests/queries_spec.rb
48 examples, 0 failures
```

### 追記: 候補の上限を 40 枚から 100 枚に直した（R2 の C2 の訂正）

R2 で、上限を「初期データの 18 枚と、紹介状を入れた 44 枚のあいだ」の 40 に置いた。これは誤りだった。
紹介状のテンプレート（jp_referral。26 枚）を登録した索引は、ふつうにある（手元の開発用の DB が、その状態だった）。
40 だと、その索引では「検索で当たったカードと、同じテンプレートのカード」に絞る側に入り、R2 の実測のとおり、候補が足りなくなる。

- Red: fixture の 6 つの OPT を入れた索引（44 枚）で、「空腹時血糖の値」の候補が 0 枚（`expected: 44 got: 0`）
- 直し: 上限を 100 に。Green（`candidates_spec` 7 examples, 0 failures）
- 実測: 44 枚をすべて送ったときの入力は 2,616 文字（18 枚の 4〜5 倍。まだ小さい）
- 100 の根拠も弱い（見込み）。100 枚を超える索引での候補の取り方は、ここでは決めていない（検索の段 C・E は保留）
