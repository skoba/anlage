- Add: Postman のコレクションに「患者 ID から EHR を引く」（`GET /openehr/v1/ehr?subject_id=&subject_namespace=anlage`。openehr-rails 0.13.0 から）を足した（Refs #272、Refs R-20261127-30）。利用者に見える変更: あり（API を試す人向け）。
  応答の EHR ID が環境の `ehr_id` に入るので、患者の画面から EHR ID を写さなくてよい。環境の雛形に `subject_id`（既定 DEMO-01）を足した
