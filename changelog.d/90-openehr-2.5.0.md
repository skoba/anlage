### Changed

- openehr を 2.4.3 から 2.5.0 に上げた（openehr-rails は 0.8.0 のまま）（`skoba/anlage#90`）
- デモクエリ 2 を本来形に置き換えた: 診断確度を、表示ラベルではなくコード値
  （`value/defining_code/code_string`）で絞る
- デモクエリ 4 を本来形に置き換えた: ELEMENT の値ではなく、OBSERVATION のイベント時刻
  （`events[at0002]/time/value`）の半開区間で絞る
- name 述語（`items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']`）で引ける。
  直接コミットした jp_referral の構造骨格で確かめた

利用者に見える変更: あり（AQL で書ける path が増える。アプリの画面と保存される記録は変わらない）。
暫定形のデモクエリはタグ `v0.1.0-jcmi46` に残る。
