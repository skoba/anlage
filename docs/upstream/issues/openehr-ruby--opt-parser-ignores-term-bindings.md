# OPTParser drops `term_bindings` (external terminology bindings) from parsed archetype ontology

要約: OPTParserはterm_definitionsしか読まず、外部ターミノロジー参照であるterm_bindings（SNOMED CT等）を破棄する。AMモデル側には既に受け皿がある。

**起票先: [skoba/openehr-ruby#31](https://github.com/skoba/openehr-ruby/issues/31)**

## Suggested labels

`enhancement`, `parser`

## Summary

- `OPTParser`'s terminology handling reads only `term_definitions` from each archetype's ontology XML; it never looks at `term_bindings` (or `constraint_definitions`/`constraint_bindings`).
- Real Archetype Designer output binds local at-codes to external terminologies (e.g. SNOMED CT) via `<term_bindings terminology="...">`, and to external value sets via the `C_CODE_REFERENCE`/`referenceSetUri` mechanism (see the companion crash issue) — both are silently unavailable to anything using `OPTParser`.
- The sibling `XMLArchetypeParser` (used for raw `.adl`/archetype XML, as opposed to compiled OPTs) already threads `term_bindings` through to the AM model, so the receiving data structure exists — `OPTParser` just doesn't populate it.

## Environment

- `openehr` 2.3.0 (rubygems.org)
- Ruby 4.0.6

## Evidence: real OPTs carrying both binding forms

**`term_bindings` (SNOMED CT)** — from a real Archetype Designer-generated OPT (`CardiologyEncounter.opt`, lines 1029-1036 of the reporter's fixture, included as a minimal excerpt for shape only — content firewall note: only two SNOMED CT codes are shown, no broader terminology content):

```xml
<term_bindings terminology="SNOMED-CT">
    <items code="at0004">
        <value>
            <terminology_id>
                <value>SNOMED-CT</value>
            </terminology_id>
            <code_string>[SNOMED-CT(2003)::271649006]</code_string>
        </value>
    </items>
    <!-- followed by an at0005 item bound to [SNOMED-CT(2003)::271650006] -->
</term_bindings>
```

**`referenceSetUri` (ICD-11, via `C_CODE_REFERENCE`)** — from a real OPT (`ProblemList.opt`, lines 323-334 of the reporter's fixture; ICD-11 root URI only, no coded content):

```xml
<children xsi:type="C_CODE_REFERENCE">
    <rm_type_name>CODE_PHRASE</rm_type_name>
    <occurrences>...</occurrences>
    <node_id></node_id>
    <referenceSetUri>terminology:http://id.who.int/icd/release/11/mms</referenceSetUri>
</children>
```

Both forms occur in real, CKM-derived clinical archetypes, not synthetic test data.

## Expected

Parsing an OPT preserves both `term_bindings` (at-code → external terminology code mappings) and, where present, `referenceSetUri` value-set bindings, so downstream code can resolve at-codes to external terminology concepts without re-parsing the OPT XML independently.

## Actual

`OPTParser`'s terminology handling reads only `term_definitions`:

```ruby
# lib/openehr/parser/opt_parser.rb:149-168
def archetype_terminology(nodes)
  td = term_definitions(nodes)
  concept_code = td[language.code_string][0]
  OpenEHR::AM::Archetype::Terminology::
    ArchetypeTerminology.new(
          concept_code: concept_code,
          original_language: language,
          term_definitions: td)
end

def term_definitions(nodes)
  term_definitions = nodes.xpath 'term_definitions'
  term_items = term_definitions.map do |term|
    code = term.attributes['code'].value
    text = term.at('items[@id="text"]').text
    description = term.at('items[@id="description"]').text
    OpenEHR::AM::Archetype::Terminology::ArchetypeTerm.new(code: code, items: {'text' => text, 'description' => description})
  end
  { language.code_string => term_items }
end
```

`nodes.xpath 'term_definitions'` (line 160) is the *only* XPath consulted for terminology data — there is no query for `term_bindings`, `constraint_definitions`, or `constraint_bindings` anywhere in `opt_parser.rb` or its mixins (confirmed by grep, zero matches), and `referenceSetUri` does not appear anywhere in `lib/`. `ArchetypeTerminology.new` (lines 152-156) is called with only `concept_code`, `original_language`, `term_definitions` — bindings are never even attempted. Additionally, only `id="text"`/`id="description"` items are read (lines 163-164, unguarded `.text` calls that would themselves raise if either is absent) and only the primary language is kept (line 167 — translations are dropped).

## Why the fix is straightforward: the AM model already supports bindings

`XMLArchetypeParser` (used for standalone archetype/ADL-derived XML) already passes bindings through to the ontology model:

```ruby
# lib/openehr/parser/xml_archetype_parser.rb:186-188
# (constructs ArchetypeOntology.new with, among others:)
constraint_definitions: ...,
term_bindings: ...,
constraint_bindings: ...,
```

And `ArchetypeOntology` already has the accessor to receive it:

```ruby
# lib/openehr/am/archetype/ontology.rb:8
attr_accessor :term_bindings
```

So this is a parser-completeness gap in `OPTParser` specifically, not a missing model capability.

## Proposed fix

Add XPath handling for `term_bindings` in `OPTParser#archetype_terminology`/`term_definitions` (or a sibling method), following the same shape `XMLArchetypeParser` already uses to populate `ArchetypeOntology#term_bindings`, and pass the result into `ArchetypeTerminology.new` (extending it with a `term_bindings:` keyword if `ArchetypeTerminology` doesn't already accept one — please confirm against the actual class before implementing). Handling `referenceSetUri` is closely related but lives in the constraint tree rather than the ontology section — see the companion `C_CODE_REFERENCE` crash issue; the two may be worth coordinating since both concern preserving external-terminology bindings that Archetype Designer emits.

Design detail (which terminologies/structures a WP2-scale extractor actually needs from this) will be added to this issue as a follow-up comment once that implementation work is done downstream — this issue is scoped to what upstream should preserve while parsing, not to a full consuming design.

## Suggested test

A parser spec asserting that parsing an OPT fixture containing a `<term_bindings terminology="...">` block populates `ArchetypeTerminology#term_bindings` (or equivalent) with the code mapping. A minimal fixture can reuse the shape shown above; per this project's real-artifact-only policy, prefer deriving it from an actual CKM/Archetype Designer export and keep the SNOMED CT content to the smallest number of codes needed to exercise the parser (ICD-11 URI-only bindings, as in the `referenceSetUri` example, carry no licensing concern and are safe to include more liberally).

## Workaround

Anlage's semantic-pathcard extractor (in development) re-parses the OPT's stored source XML itself (`templates.source_xml`) rather than relying on `OPTParser`'s ontology output, specifically to recover both `term_bindings` and `referenceSetUri` forms. This is a deliberate, human-approved design decision (2026-08-22) tracked in this repository's own planning documents, not a landed workaround file — implementation is scheduled as a WP2 TDD item.

## Priority note (2026-08-26 update, not posted to the live issue)

A second, independent workaround has since landed: `openehr-rails`
`OpenehrRails::Opt::Parser#populate_term_bindings!`
(`lib/openehr_rails/opt/parser.rb:43-60`, shipped in `openehr-rails`
0.5.0, `skoba/openehr-rails#30`) does the same raw-XML re-parse
Anlage's `Opt::PathcardExtractor` does, but inside the gem's own parser
subclass, and enriches the upstream `ArchetypeOntology#term_bindings`
slot directly. It is explicitly nil-guarded and documented as a
two-method deletion once this issue (`#31`) lands upstream (removal-
condition comment in the source).

Net effect: there are now **two independent bypass implementations**
of the same upstream gap (Anlage's `PathcardExtractor` and
`openehr-rails`' `Parser`), both re-parsing the same OPT XML shape by
hand. Verified byte-identical output between the two
(`docs/reports/fsh-log.md` R4, 2026-08-26): same `code_string` format
(versioned `[SNOMED-CT(2003)::...]`), same `reference_set_uri`
strings. This does not lower the value of fixing `#31` upstream — if
anything it raises it, since a single upstream fix would let both
downstream bypasses be deleted rather than just one. It does mean
neither downstream repo is currently blocked waiting on `#31`, so
there is no urgency pressure from either consumer; this is offered as
context for whoever next triages `#31`'s priority, not a request to
re-prioritize it now.
