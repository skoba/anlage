# Harden OPT/archetype XML parsing with explicit, safe Nokogiri ParseOptions

要約: OPTParser/XMLArchetypeParserはNokogiriのParseOptionsを明示していない。現行のnokogiri既定値ではNONETはON・NOENTはOFFで古典的XXEは防がれているが、明示的な安全デフォルト＋回帰テストとしてgem側で保証すべき。

**起票先: [skoba/openehr-ruby#33](https://github.com/skoba/openehr-ruby/issues/33)**

## Suggested labels

`enhancement`, `security`, `hardening`

## Summary

- `OPTParser#parse` and `XMLArchetypeParser#parse` call `Nokogiri::XML::Document.parse(...)` with no `ParseOptions` argument, relying entirely on whatever the linked libxml2/Nokogiri version's default happens to be.
- With the currently-resolved `nokogiri` 1.19.4, that default (`ParseOptions::DEFAULT_XML`) already forbids network access (`NONET`) and does not substitute entities (`NOENT` is off) — so classic XXE (external entity expansion / SSRF via entity) is **not** currently exploitable through these call sites, as far as this default goes.
- This issue is a hardening request, not a report of an currently-exploitable XXE: making the safe options explicit removes the dependency on "whichever Nokogiri/libxml2 happens to be linked" and adds a regression test so a future Nokogiri release (or a downstream app pinning an older Nokogiri) can't silently change this by shipping a different default.

## Environment

- `openehr` 2.3.0 (rubygems.org)
- `nokogiri` 1.19.4 (x86_64-linux-gnu)
- Ruby 4.0.6

## Current behavior, precisely (file:line + verified default)

Call sites, both with **no** `ParseOptions` argument:

```ruby
# lib/openehr/parser/opt_parser.rb:43
@opt = Nokogiri::XML::Document.parse(File.open(@filename))
```

```ruby
# lib/openehr/parser/xml_archetype_parser.rb:33
parsed = Nokogiri::XML::Document.parse(File.open(@filename, 'rb:bom|utf-8'))
```

`OpenehrRails::Opt::Parser#parse` (`openehr-rails`, `lib/openehr_rails/opt/parser.rb:20`) inherits this behavior — it subclasses `OpenEHR::Parser::OPTParser` and does not override parsing, so a fix at the openehr-ruby level automatically benefits it.

With no explicit options, `Nokogiri::XML::Document.parse` defaults to `XML::ParseOptions::DEFAULT_XML` (nokogiri 1.19.4, `lib/nokogiri/xml/document.rb:56-58`), defined as:

```ruby
# nokogiri 1.19.4, lib/nokogiri/xml/parse_options.rb:151
DEFAULT_XML  = RECOVER | NONET | BIG_LINES
```

- `NONET` (`parse_options.rb:115`, doc comment lines 111-114: "Forbid network access. On by default ... It is UNSAFE to unset this option") — **is** included in `DEFAULT_XML`, so external-resource fetches over the network are already blocked by default.
- `NOENT` (`parse_options.rb:80`, doc comment lines 75-79: "Substitute entities. Off by default. ... It is UNSAFE to set this option") — is **not** part of `DEFAULT_XML`, so entity substitution is off by default, which is the safe state.
- `RECOVER` (`parse_options.rb:73`) is also on by default, meaning malformed XML is parsed leniently rather than rejected — worth a decision either way, see "Open question" below.

So, precisely: **the two call sites are not currently vulnerable to classic XXE under nokogiri 1.19.4's defaults**, but that safety is incidental (inherited from the Nokogiri gem's own default), not asserted by this gem. Both call sites also leak the `File.open` file handle (opened without a block, never explicitly closed).

## Proposed fix

1. Pass explicit `ParseOptions` at both call sites instead of relying on the ambient default — e.g. `Nokogiri::XML::Document.parse(source, nil, nil, Nokogiri::XML::ParseOptions::NONET)` (or a similarly explicit construction) so the safe behavior is guaranteed by this gem's own code, independent of whatever Nokogiri version resolves at bundle time. Do **not** set `NOENT`.
2. Use `File.open(...) { |f| Nokogiri::XML::Document.parse(f, ...) }` (block form) at both sites to close the file handle deterministically, since this is being touched anyway.
3. **Open question worth deciding explicitly** rather than inheriting by accident: should untrusted uploads still be parsed with `RECOVER` (lenient, silently-repairing) mode? For trusted local archetype/OPT files `RECOVER` is convenient; for XML arriving from an HTTP upload, failing loudly on malformed XML may be preferable to silently "fixing" it. This issue only asks for `NONET`/`NOENT` to be pinned explicitly; whether to also drop `RECOVER` for untrusted-input call sites is a separate decision the maintainers may want to make consciously either way.

## Suggested test

Add a regression spec asserting that parsing a small XML fixture containing an external entity declaration (`<!ENTITY xxe SYSTEM "...">`) referenced from an element value does **not** get expanded — i.e. the parsed value contains the literal entity reference text or an empty/failed substitution, not the referenced resource's content. This fixture is a synthetic attack payload with no clinical content, so it falls outside this project's real-artifact-only fixture policy (it belongs alongside other parser-mechanics fixtures, not `spec/fixtures/opt/` style CKM-derived archetypes) — it should be labeled clearly as a security fixture in its filename/directory.

## Workaround

Anlage does not rely on gem-level `ParseOptions` for this. Its `Opt::SafeParser` (`app/lib/opt/safe_parser.rb`, whole file) takes a different, complementary defense: it rejects any uploaded OPT containing a `<!DOCTYPE` declaration via a regex pre-check (`DOCTYPE_PATTERN = /<!DOCTYPE/i`, line 12) **before** the source ever reaches `OpenehrRails::Opt.parse` (line 19), on the reasoning that XXE entity expansion is impossible without a DTD to declare the entity in (comment, lines 2-7). It is called from `app/models/template.rb:23`.

Note this is *not* the `Nokogiri::XML::ParseOptions` wrapper originally sketched in this project's own planning document (`docs/plans/opt-dropzone.md`, Slice 2 / §2.7) — the DOCTYPE pre-check was implemented instead, and is arguably simpler and libxml2-version-independent. It doesn't restore `NONET` protection if a future Nokogiri release changed that default, though, so the upstream fix in this issue still has standalone value as defense in depth.
