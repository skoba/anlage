# OPTParser crashes with NoMethodError on `C_CODE_REFERENCE` children

要約: OPTParserは`C_CODE_REFERENCE`型の制約ノード（外部ターミノロジー参照）に対するハンドラを持たず、`send`ディスパッチで`NoMethodError`になる。

**起票先: [skoba/openehr-ruby#30](https://github.com/skoba/openehr-ruby/issues/30)**

## Suggested labels

`bug`, `parser`

## Summary

- `OPTParser` dispatches on `xsi:type` via `send type.downcase, ...` for every constraint node.
- There is no handler for `C_CODE_REFERENCE` — the type Archetype Designer emits when a `DV_CODED_TEXT.defining_code` constraint is bound to an external terminology value set (e.g. an ICD-11 reference set) instead of an internal code list.
- Any OPT containing such a node fails to parse at all, with a raw `NoMethodError`.

## Environment

- `openehr` 2.3.0 (rubygems.org) — the gem this bug is in; the reproduction below only requires `openehr`, not `openehr-rails`
- `nokogiri` 1.19.4 (x86_64-linux-gnu)
- Ruby 4.0.6

## Reproduction

```ruby
require 'openehr'

parser = OpenEHR::Parser::OPTParser.new('spec/fixtures/opt/ProblemList.opt')
parser.parse
```

Run from a checkout containing a `ProblemList.opt` whose `DV_CODED_TEXT` constraint carries an external reference-set binding — see the fragment below (line numbers from the reporter's local fixture, included for context only; the shape is what matters, not this specific file). This reproduces identically for any OPT containing this XML shape anywhere under a `C_COMPLEX_OBJECT`'s `<children>`, so a fresh minimal OPT built around just this fragment reproduces the crash the same way.

Content firewall note: the fragment below contains no coded/terminology content — only an ICD-11 root URI (not licensed content), occurrence bounds, and structural elements.

```xml
<children xsi:type="C_CODE_REFERENCE">
    <rm_type_name>CODE_PHRASE</rm_type_name>
    <occurrences>
        <lower_included>true</lower_included>
        <upper_included>true</upper_included>
        <lower_unbounded>false</lower_unbounded>
        <upper_unbounded>false</upper_unbounded>
        <lower>0</lower>
        <upper>1</upper>
    </occurrences>
    <node_id></node_id>
    <referenceSetUri>terminology:http://id.who.int/icd/release/11/mms</referenceSetUri>
</children>
```

### Actual output (full exception, from the reproduction above)

```
lib/openehr/parser/xml_constraint_parsing.rb:68:in 'block in OpenEHR::Parser::XMLConstraintParsing#children': undefined method 'c_code_reference' for an instance of OpenEHR::Parser::OPTParser (NoMethodError)

          send child.attributes['type'].text.downcase, child, child_node
          ^^^^
Did you mean?  c_code_phrase
	from .../nokogiri/xml/node_set.rb:237:in 'block in Nokogiri::XML::NodeSet#each'
	from .../nokogiri/xml/node_set.rb:236:in 'Integer#upto'
	from .../nokogiri/xml/node_set.rb:236:in 'Nokogiri::XML::NodeSet#each'
	from lib/openehr/parser/xml_constraint_parsing.rb:64:in 'Enumerable#map'
	from lib/openehr/parser/xml_constraint_parsing.rb:64:in 'OpenEHR::Parser::XMLConstraintParsing#children'
	from lib/openehr/parser/xml_constraint_parsing.rb:75:in 'OpenEHR::Parser::XMLConstraintParsing#c_single_attribute'
	from lib/openehr/parser/xml_constraint_parsing.rb:52:in 'block in OpenEHR::Parser::XMLConstraintParsing#attributes'
	... (repeats through c_complex_object / c_archetype_root / c_multiple_attribute
	     as the walk recurses into ancestor nodes) ...
	from lib/openehr/parser/xml_constraint_parsing.rb:28:in 'OpenEHR::Parser::XMLConstraintParsing#c_archetype_root'
	from lib/openehr/parser/opt_parser.rb:116:in 'OpenEHR::Parser::OPTParser#definition'
	from lib/openehr/parser/opt_parser.rb:47:in 'OpenEHR::Parser::OPTParser#parse'
```

## Expected

The OPT parses successfully, and the `C_CODE_REFERENCE` constraint is represented in the resulting constraint tree (at minimum, occurrences and the `referenceSetUri`/reference-set binding should be preserved so callers can tell "constrained to an external value set" apart from "unconstrained").

## Actual

`OPTParser#parse` raises `NoMethodError: undefined method 'c_code_reference'` and the entire OPT — including all sibling archetypes in the same template — fails to load.

## Root cause

`children` in `lib/openehr/parser/xml_constraint_parsing.rb:63-70` dispatches every constraint-tree child on its `xsi:type` by lowercasing the type name and calling it as a method:

```ruby
def children(children_xml, node)
  children_xml.map do |child|
    child_node = Node.new(node)
    child_node.path = node.path
    child_node.id = node.id
    send child.attributes['type'].text.downcase, child, child_node
  end
end
```
(dispatch at line 68)

The same pattern exists for attribute-level constraints in `attributes` (`xml_constraint_parsing.rb:41-54`, dispatch at line 52).

Handlers exist for `c_archetype_root` (:18), `c_complex_object` (:31), `c_single_attribute` (:72), `c_multiple_attribute` (:78), `archetype_slot` (:84), `archetype_internal_ref` (:174), `constraint_ref` (:181), `c_primitive_object` (:227), and the domain-type handlers in `lib/openehr/parser/xml_domain_type_parsing.rb` (`c_code_phrase` :13, `c_dv_quantity` :44, `c_dv_ordinal` :75, `c_dv_scale` :97, `c_dv_state` :123). **No `c_code_reference` handler exists anywhere in `lib/`.** There is also no `method_missing` anywhere in the parser's ancestry (`Parser::Base`, `lib/openehr/parser.rb:3-13`, defines none), so the `send` fails loudly with `NoMethodError` rather than degrading gracefully.

Note: `OPTParser#parse` calls `@opt.remove_namespaces!` (`opt_parser.rb:44`) before parsing, so `xsi:type` is read as the bare `type` attribute — this is why the dispatch code reads `child.attributes['type']` rather than a namespaced lookup.

## Investigation update (2026-08-22): the `ParseError` in the existing unknown-`xsi:type` spec is not a real, type-specific contract

Schema authority (openEHR/specifications-ITS-XML, `components/AM/Release-1.4/Template.xsd:115-123`):

    <xs:complexType name="C_CODE_REFERENCE">
      <xs:complexContent>
        <xs:extension base="C_CODE_PHRASE">
          <xs:sequence>
            <xs:element name="referenceSetUri" type="xs:anyURI"/>
          </xs:sequence>
        </xs:extension>
      </xs:complexContent>
    </xs:complexType>

`C_CODE_REFERENCE` is a straightforward extension of `C_CODE_PHRASE` adding one
`referenceSetUri` element - confirming a `CCodeReference < CCodePhrase` Ruby
model (mirroring this extension) is spec-faithful.

Separately, while scoping the "unknown `xsi:type` should not crash the parser"
defense that accompanies the `C_CODE_REFERENCE` fix, we traced why
`spec/lib/openehr/parser/xml_archetype_parser_spec.rb:145` ("raises a ParseError
for an unknown xsi:type in the definition tree") currently passes on `master`.

Both `OPTParser` and `XMLArchetypeParser` share one dispatch method,
`XMLConstraintParsing#children` (`lib/openehr/parser/xml_constraint_parsing.rb:68`),
which does `send child.attributes['type'].text.downcase, child, child_node` with
no guard. For an unknown type this raises a bare `NoMethodError`. We reproduced
both parsers against the same unknown-`xsi:type` input and captured the actual
exception classes:

- `XMLArchetypeParser#parse` (`lib/openehr/parser/xml_archetype_parser.rb:21-27`)
  wraps it: `rescue StandardError => e; raise ParseError, "...: #{e.class}: #{e.message}"`.
  This rescue clause does not inspect the exception type or message at all - it
  wraps *any* `StandardError` raised anywhere while building the archetype, not
  specifically unknown-`xsi:type` errors.
- `OPTParser#parse` (`lib/openehr/parser/opt_parser.rb:42-63`) has no rescue at
  all. The identical input raises a raw `NoMethodError` straight to the caller.

So the same bug, through the same shared dispatch code, currently produces two
different outcomes depending only on which of the two parser classes is used.
The existing spec's name overstates the implementation: there is no type-specific
"unknown xsi:type -> ParseError" contract, only an incidental side effect of one
parser's generic top-level rescue.

This supports (but doesn't by itself force) treating the fix as behavior
unification rather than a breaking contract change: both parsers will handle an
unrecognized constraint type the same way (a warning plus a same-shape fallback
node) instead of one silently succeeding-via-blanket-rescue and the other
crashing raw. Final call on wording/semver is the maintainer's.

## Proposed fix

1. Add a `c_code_reference` handler alongside `c_code_phrase` that preserves the reference-set binding (see the companion enhancement request for `term_bindings`/`referenceSetUri` handling — the two are closely related and may be worth landing together). At minimum it should return a constraint node carrying the `referenceSetUri` value and the occurrences, without dropping the node from the tree.
2. Independently of (1), harden `children`/`attributes` against *any* unknown `xsi:type` by falling back to a generic node (e.g. treat as `c_complex_object`) with a logged warning, rather than raising `NoMethodError`. As the investigation update above found, this is not purely forward-looking hardening — `OPTParser` and `XMLArchetypeParser` *already* disagree on this exact case today (raw `NoMethodError` vs. an incidentally-wrapped `ParseError`), so the fix is best framed as unifying two paths that already diverge on the same bug, not as changing a settled contract.

## Suggested test

Add a parser spec that feeds a minimal OPT/archetype fixture containing a `C_CODE_REFERENCE` child under a `C_COMPLEX_OBJECT`'s `children` (the DV_CODED_TEXT.defining_code case above is the real-world trigger) and asserts the parse succeeds and the reference-set URI is retrievable from the resulting node. This can be a small hand-written XML fixture derived from the real shape shown above — it is a parser-mechanics test, not a clinical-content test, so it is not subject to this project's real-artifact-only fixture policy.

## Workaround

None currently landed. Anlage's semantic-pathcard extractor (in development) is planned to re-parse the OPT's stored source XML itself rather than relying on `OPTParser`'s constraint tree for this case, so a template containing a `C_CODE_REFERENCE` node doesn't take down the whole OPT parse. Adding a `c_code_reference` handler to a local `Parser` subclass (mirroring the fix proposed above) is tracked as a WP2 TDD item in this repository's own planning documents, not yet implemented.
