# UI 語彙表（正典、`skoba/anlage#47` 裁定 F、2026-10-12）

画面見出し・ボタン名・台本での呼び名の対応。**UI 文言を固定する spec はこの表に追随する**（CLAUDE.md、裁定 G）。
変更はこの表を先に直し、view と spec を同一コミットで追随させる。

| 対象 | 画面見出し | ボタン／ラベル | 台本での呼び名 | 置換元（2026-10-12 時点の現状） |
|---|---|---|---|---|
| テンプレート（OPT） | テンプレートの取り込み | ファイルを選択／URLから取り込む／登録／破棄 | テンプレート | Templates／試着室／Drop the .opt file to try it on／Drop an .opt file anywhere, or click to choose |
| 帳票（フォーム） | <テンプレート名> | 帳票に入力／保存 | 帳票 | Open form／送信 |
| カルテ記録（Composition） | カルテ記録一覧／カルテ記録: <テンプレート名> | 保存しました（flash）／保存日時／同じ帳票にもう 1 件入力・カルテ記録一覧・AQL 照会・FHIR プロファイル（次アクション）／canonical JSON（折りたたみ） | カルテ記録（「カルテ記録として保存」） | Compositions／composition／Registered:／登録しました |
| 共通ナビ（layout） | — | テンプレート／カルテ記録一覧／パスカード検索／AQL 照会 | — | （無し） |
| パスカード | パスカード検索 | 探したい項目／検索 | パスカード | Pathcard search／Query／Search／Template／Archetype／Node |
| AQL 照会 | （openehr-rails engine の console、文言は gem のまま） | AQL 照会（nav のリンク名） | AQL 照会 | AQL Query |
| FHIR プロファイル | — | FHIR プロファイル（カルテ記録画面のリンク） | FHIR プロファイル | — |
| FSH | — | — | FSH 出力（`rake fsh:export`） | — |
| 空状態 | — | テンプレートが未登録です。OPT ファイルを選択して取り込んでください | — | No templates registered yet. Drop an OPT file to get started. |
| 取り込み結果（Composition JSON） | 記入済みの帳票 | 閉じる | — | 記入済みフォーム |
| 取り込み結果（ADL） | アーキタイプ（テンプレートではありません） | 閉じる | — | ADLアーキタイプ／テンプレート化しますか |
| 閲覧専用 | — | 保存は未対応（#30） | 閲覧専用の帳票 | （同じ） |

備考: 「記録」単独は動詞と紛れるため「カルテ記録」とする。「帳票を開く」は開いて何をするかが見出しに出るよう「帳票に入力」とする（裁定 F）。
