- openehr を 2.6.0 に、openehr-rails を 0.10.0 に上げた。利用者に見える変更: あり。
  - FHIR プロファイルの id と URL（`/fhir/r5/StructureDefinition/<id>`）が、テンプレートで修飾された形になる
    （例: `openehr-problemlist-evaluation-problem-diagnosis-v1`）。
  - 同じアーキタイプを使う 2 つのテンプレートのプロファイルが、衝突しなくなる。
- 記録の COMPOSITION に、保存した時刻（`context/start_time`）を持たせた。利用者に見える変更: あり（AQL で引ける）。
  - AQL で紹介日などの記録日時で引ける。
  - 修正と削除の版は、元の記録の時刻を引き継ぐ。
- 出所の表示（template_id）の切り替えは見送った。利用者に見える変更: なし。
  - openehr-rails 0.10.0 の AQL では値が nil のため（上流候補 25 項）。
