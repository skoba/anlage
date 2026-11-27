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
