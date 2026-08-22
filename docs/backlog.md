# Backlog（低優先度・要別途承認の項目）

WP0-5やSliceの実装計画には載らないが、確認済みで記録しておくべき
低優先度項目。ここに載っている項目は**このファイルへの追記自体が
対応の完了**であり、実装対応は別途承認を得てから着手する。

## 1. `Opt::SafeParser` の DOCTYPE 検知が UTF-16 入力で素通りする

- 発見日: 2026-08-22（読み取り検査のみ、実装変更なし）
- 対象: `app/lib/opt/safe_parser.rb`
- 内容: `DOCTYPE_PATTERN = /<!DOCTYPE/i` によるDOCTYPE事前拒否
  （`docs/plans/opt-dropzone.md` §2.7 as-built 参照）は、アップロード
  バイト列を `.b`（ASCII-8BIT化）してから正規表現マッチする。これは
  UTF-8/ASCII/Shift_JIS等、`<!DOCTYPE` がASCII互換のバイト列として
  連続するエンコーディングでは確実に検知できるが、**UTF-16などASCII
  文字がヌルバイトを挟んで並ぶエンコーディングでは、バイト列が
  連続しないため正規表現に一致せず素通りする**。
- 実測（`bundle exec rails runner` で実際の `Opt::SafeParser.parse`
  にUTF-16LEエンコードのXXEペイロードを通した結果、tmpスクリプトの
  実行のみ・コミットなし）:
  - ASCII/UTF-8のXXEペイロード → `Opt::UnsafeTemplate` で正しく拒否
  - 同内容をUTF-16LEでエンコードしたペイロード →
    DOCTYPE検知をすり抜けて `OpenehrRails::Opt.parse`
    まで到達（今回のPoCペイロードは完全なOPT/archetype XMLではないため
    その先で`ArgumentError: invalid archetype id form`になったが、
    これはOPT構造として不正なための失敗であり、DOCTYPE検知の突破とは
    無関係。実際に有効なarchetype構造を持つUTF-16 OPTであれば、
    DOCTYPE宣言はチェックされずにNokogiriまで到達する）。
  - 補足: `templates_controller.rb:148/:170` の
    `force_encoding(Encoding::UTF_8)` はラベル貼り替えのみで実バイト列を
    変換しないため、この経路のどこにもエンコーディング正規化
    （宣言されたencodingを読んでUTF-8へ実変換する等）は存在しない。
- **緊急度: 低**。nokogiri 1.19.4 の `ParseOptions::DEFAULT_XML`
  （`RECOVER | NONET | BIG_LINES`）で **`NONET` が既定でON**・
  **`NOENT` が既定でOFF**（`docs/plans/opt-dropzone.md` §2.7参照）
  であるため、DOCTYPE検知をすり抜けたペイロードがNokogiriまで
  到達しても、外部ネットワーク参照やエンティティ実体展開自体は
  下段の既定動作でブロックされる。二層防御の一段目に穴があるが、
  二段目（gem側の既定）は生きている状態。
- **対応方針（本タスクでは実施しない）**: 修正案の候補は
  (a) DOCTYPE正規表現をかける前に宣言されたencodingを読んでUTF-8へ
  実変換する、(b) バイト列レベルで `<`/`!`/`D`/`O`/`C`/`T`/`Y`/`P`/`E`
  の各バイトの間にヌルバイトを許容する形へ正規表現を緩める、
  (c) Nokogiri側にも明示的な `NONET`/`NOENT` を渡し二段目を保証させる
  （`docs/upstream/issues/openehr-ruby--xxe-safe-default-parse-options.md`
  参照）などが考えられるが、**いずれも実装は別途承認を得てから**。

## 2. 診療情報提供書 OPT 入手時の受け入れスモーク

- ドロップゾーン通過・埋め込みCLUSTERラベル・FHIR facade出力を確認し
  `docs/evidence/` に証跡追加（デモ本番アーティファクトの新スタック
  初通過の記録）。
