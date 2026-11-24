### Changed

- テンプレートの用語（ルートごとの名前と、項目の改名）を、openehr 2.5.0 の `CArchetypeRoot#term_definitions` から
  取るようにした（`Opt::RootTerms`）。OPT の XML を Nokogiri で読み直す迂回 `Opt::TemplateTerms` は撤去した（`skoba/anlage#104`）

利用者に見える変更: なし（パスカード、帳票のラベル、SECTION の名前は同じ値。golden は変えていない）。
