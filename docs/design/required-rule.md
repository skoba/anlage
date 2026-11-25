# 必須の規則: 入れ物を書くなら必須（R-20261125-1）

状態: 実装済み（`wip/i-referral-exit`、draft PR #123）。裁定 R-20261125-1（案 B）。
openehr-rails の #65（条件つきの必須）が同じ規則にそろえられるように、ここに規則だけを書く。上流への起票とコメントは人間が行う。

## 規則

1. **入れ物**は、ENTRY と、埋め込みの CLUSTER（テンプレートのルートを除いた C_ARCHETYPE_ROOT）。
   SECTION とアーキタイプ内の CLUSTER は入れ物に数えない（判定では素通りする）
2. 下限 ≥1 の要素（ELEMENT の occurrences）は、**その要素を含む入れ物が書かれるとき**に必須
3. 入れ物が書かれるのは、次のどちらか:
   1. その配下（内側の入れ物も含む）に、値が 1 つでも入力されている
   2. 入れ物自身の下限が 1 以上で、その親の入れ物が書かれる。いちばん外の入れ物の親は根の COMPOSITION で、常に書かれる
4. 判定は、要素にいちばん近い入れ物から外へたどる
5. 入れ物の下限が分からない（OPT に occurrences が無い）ときは、書かれるものとして扱う。任意と見なして黙って通さない
6. 帳票全体で値が 1 つも無ければ保存させない。メッセージは項目ではなく帳票に付ける
7. 「値」に数えるのは、項目そのものの値とコード入力（`__code`）。単位（`__units`）と時刻の欄（`__time`）だけでは数えない

理由: openEHR の occurrences は、親が存在するときの個数の制約。0..1 の入れ物は、入れ物ごと書かないことが許される。

## 実装の場所

| 何 | どこ |
|---|---|
| 入れ物の下限を OPT から取る | `app/lib/opt/element_roots.rb`（ルートの 4 つめの要素、`occurrences.lower`） |
| field の入れ物の並び（`containers`: `{key, min}` を外側から） | `app/models/template.rb` の `containers`。`key` は OPT 上の path と出現順で、インスタンスを区別する |
| 規則の判定・帳票全体の空 | `app/lib/opt/form_validator.rb`（`required_now?`・`EMPTY_FORM_MESSAGE`） |
| 帳票の印 | `Opt::FormValidator.required_mark`、`app/views/templates/_field.html.erb`、`app/views/forms/show.html.erb`。文言は `docs/demo/ui-vocabulary.md` |

`required`（web_template の field）の意味は「要素を含む入れ物を書くなら必須」に変わる（値は従来どおり、gem の required または要素の下限 ≥1）。
`containers` の無い field（この変更より前の登録）は、従来どおり `required` なら必須。`rake templates:rebuild_web_template` で `containers` が付く。

## 下限の実測（6 つの fixture）

ENTRY と埋め込み CLUSTER の下限はすべて 0（`docs/reports/m2-exit-log.md` R4）。規則 3-2（下限 ≥1 の入れ物）に当たる実物は、まだ無い。
単体の spec（`spec/lib/opt/required_rule_spec.rb`）は、規則を合成の field で確かめる（OPT・at-code を捏造しない、フィールド名だけの記述）。

## テンプレートの側で決めること

紹介状で「症状経過及び検査結果」や「治療経過」を必ず書かせたいなら、テンプレートで入れ物の下限を 1 にする（人間。v0.3）。コードの規則では決めない。
