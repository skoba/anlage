# FieldExtractor resolves at-code labels against the host archetype's terminology, not the owning embedded archetype's

要約: FieldExtractorは埋め込みCLUSTERアーキタイプ内のat-codeも常に宿主エントリのterminologyで解決するため、コード衝突時に誤ったラベル（または未解決のat-codeそのもの）を返す。

> **RESOLVED UPSTREAM（2026-08-22 確認）** — このドラフトを起票する前に
> `openehr-rails` のローカルチェックアウト（`/home/skoba/src/openehr-rails`）
> で既に修正済みであることが判明した。GitHub `skoba/openehr-rails` の
> Issue #25 として存在し、以下のコミットでクローズ済み:
>
> ```
> f9291d429642bb795050e51393086721ea5b5962
> Fix: FieldExtractor resolved terminology labels using the wrong archetype scope
> Fixes #25
> ```
>
> 修正内容: `collect_elements` が直近の `C_ARCHETYPE_ROOT` 境界で
> archetype_id を更新しながら walk するようになった（`rm_type_name`
> は制約先のRM型名――例 `"CLUSTER"`――を保持するだけで、リテラル
> `"C_ARCHETYPE_ROOT"` にはならないため判定には使えない、との注記
> がコミットメッセージにあり）。`field[:archetype_id]` およびそれを
> 使うFHIRプロファインコーディングも同じ理由で誤っていたため、
> あわせて修正されている。回帰テストとして
> `spec/openehr_rails/opt/field_extractor_embedded_archetype_spec.rb`
> と実archetype由来のfixture `spec/templates/lab_result_report_reduced.opt`
> が追加された。バージョンは 0.4.0 → 0.4.1。
>
> **本ファイルは起票せず、調査時点の再現手順・根拠・修正案の記録として
> 保存する**（このリポジトリで先に同じ根本原因を独立に特定していたことの
> 裏付けとして残す）。以下は起票用に準備していた原文のまま。

## Suggested labels

`bug`, `field-extractor`

## Summary

- `FieldExtractor` walks an entry's constraint tree depth-first to collect `ELEMENT` nodes, but never tracks `C_ARCHETYPE_ROOT` boundaries during that walk.
- Label resolution always looks up the at-code in the **entry's (host) archetype's** `component_terminologies` entry, even for elements that live inside a nested embedded archetype (e.g. a `CLUSTER`) with its own, separate terminology.
- When an embedded archetype's at-code happens to collide with a code used by the host archetype (a common occurrence, since at-codes are only unique within their own archetype), the wrong label is returned — or, if the host has no term for that code, the raw at-code string is returned instead of any human-readable label.

## Environment

- `openehr-rails` 0.4.0 (local path in the reporting app; not gem-published at time of writing)
- `openehr` 2.3.0 (rubygems.org)
- Ruby 4.0.6

## Reproduction

Run via `bin/rails runner` (needs `ActiveRecord` loaded — `openehr_rails` requires it) against a real OPT containing an embedded CLUSTER archetype whose at-codes collide with the host's:

```ruby
require 'openehr'
require 'openehr_rails'

template = OpenehrRails::Opt.parse('spec/fixtures/opt/LabResultReport.opt')
extractor = OpenehrRails::Opt::FieldExtractor.new(template)

fields = extractor.fields
target = fields.select { |f| %w[at0001 at0024].include?(f[:node_id]) }
target.each { |f| puts f.slice(:name, :label, :node_id, :archetype_id, :path, :entry_rm_type).inspect }
```

### Actual output (from the reproduction above)

```
{name: "laboratory_test_result_at0024", label: "at0024", node_id: "at0024", archetype_id: "openEHR-EHR-OBSERVATION.laboratory_test_result.v1", path: "/content[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]/data[at0001]/events[at0002]/data[at0003]/items[at0000]/items[at0024]/value", entry_rm_type: "OBSERVATION"}
{name: "laboratory_test_result_event_series", label: "Event Series", node_id: "at0001", archetype_id: "openEHR-EHR-OBSERVATION.laboratory_test_result.v1", path: "/content[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]/data[at0001]/events[at0002]/data[at0003]/items[at0000]/items[at0024]/value", entry_rm_type: "OBSERVATION"}
```

(Note the `path` for both fields passes through `items[at0000]` — `at0000` is the node_id of the embedded `CLUSTER.laboratory_test_analyte.v1` archetype root itself, confirming both elements are inside that embedded archetype, not directly in the host `OBSERVATION`.)

## Expected

- `at0001` (inside `CLUSTER.laboratory_test_analyte.v1`) → label **"分析結果"** (its own archetype's term for at0001; fixture: `LabResultReport.opt:621-623`).
- `at0024` (also inside that CLUSTER) → label **"分析名"** (fixture: `LabResultReport.opt:686-688`).

## Actual

- `at0001` → label **"Event Series"** — this is the *host* `OBSERVATION.laboratory_test_result.v1` archetype's own term for its `at0001` (the HISTORY node; fixture: `LabResultReport.opt:1038-1041`), returned only because the codes happen to collide.
- `at0024` → label **"at0024"** (the raw code) — the host archetype has no `at0024` term at all (its terms run at0001–at0005, then jump to at0017, at0035, at0037…), so lookup returns `nil` and the code-fallback kicks in.

## Root cause

`build_field` (`lib/openehr_rails/opt/field_extractor.rb:146-166`) always resolves the label against `entry[:archetype_id]`:

```ruby
def build_field(element, path, entry, sibling_count)
  constraint = value_constraint(element)
  rm_type = constraint&.rm_type_name || 'DV_TEXT'
  label = term_text(entry[:archetype_id], element.node_id)

  field = {
    name: field_name(entry[:concept], label, element.node_id, sibling_count),
    label: label || element.node_id,
    ...
  }
  field.merge!(coded_text_constraints(constraint, entry[:archetype_id])) if rm_type == 'DV_CODED_TEXT'
  field.merge!(symbol_constraints(constraint, entry[:archetype_id])) if %w[DV_ORDINAL DV_SCALE].include?(rm_type)
  field
end
```
(`term_text(entry[:archetype_id], ...)` at line 149; code-fallback at line 153; the same wrong-scope `archetype_id` is also passed into `coded_text_constraints` at line 163/194 and `symbol_constraints` at line 164/210.)

`entry[:archetype_id]` is set exactly once, from the entry's own root, in `build_entry` (line 105: `archetype_id = root.archetype_id.value`) and never changes as the walk descends into nested archetypes.

`term_text` (lines 258-267) consults exactly one per-archetype terminology, keyed by whatever `archetype_id` it's given:

```ruby
def term_text(archetype_id, code)
  terminology = @template.component_terminologies[archetype_id]
  return nil unless terminology

  terminology.term_definitions.each_value do |terms|
    term = terms.find { |t| t.code == code }
    return term.items['text'] if term
  end
  nil
end
```

The walk that collects elements, `collect_elements` (lines 122-144), never checks for an archetype boundary:

```ruby
def collect_elements(node, path)
  return [] unless node.respond_to?(:attributes) && node.attributes

  node.attributes.flat_map do |attribute|
    next [] unless DESCENDABLE_ATTRIBUTES.include?(attribute.rm_attribute_name)
    next [] unless attribute.respond_to?(:children) && attribute.children

    child_path = "#{path}/#{attribute.rm_attribute_name}"
    attribute.children.flat_map do |child|
      next [] unless child.respond_to?(:rm_type_name)

      node_path = child_path
      node_path += "[#{child.node_id}]" if child.respond_to?(:node_id) && child.node_id

      if child.rm_type_name == 'ELEMENT'
        [[child, node_path]]
      else
        collect_elements(child, node_path)
      end
    end
  end
end
```

A nested `C_ARCHETYPE_ROOT` (the CLUSTER) is simply "not an `ELEMENT`", so the walk recurses into it as an ordinary container (line 140) — it never tests `child.respond_to?(:archetype_id) && child.archetype_id` to notice it just crossed into a differently-scoped archetype. `entry_root?`/`entry_roots` (lines 99-102, 77-97) do check `archetype_id`, but only at the top level, for `ENTRY_TYPES = %w[OBSERVATION EVALUATION INSTRUCTION ACTION ADMIN_ENTRY]` (line 23) — nested `C_ARCHETYPE_ROOT`s under an entry (CLUSTERs, in particular) are invisible to that check.

## Why the fix is straightforward: the gem already tracks per-archetype terminologies correctly

- The `openehr` gem's `CArchetypeRoot` constraint node already carries its own `archetype_id`, set for *every* `C_ARCHETYPE_ROOT` encountered — including nested ones — not just the outermost: `lib/openehr/parser/xml_constraint_parsing.rb:23-28` (`c_archetype_root` reads `./archetype_id/value` and builds `CArchetypeRoot.new(..., archetype_id: archetype_id, ...)` for each one it visits).
- `component_terminologies` is already stored correctly keyed **per archetype_id**, not just for the template root: `lib/openehr/parser/opt_parser.rb:119-123` (`@component_terminologies[archetype_id.value] = archetype_terminology(nodes)`), called once per `C_ARCHETYPE_ROOT`.

So the information needed to fix this is already present in the parsed tree — `collect_elements` just needs to notice when it crosses a `C_ARCHETYPE_ROOT` boundary and carry the *current* archetype's id down the rest of that subtree's walk, instead of `build_field` always reaching back to `entry[:archetype_id]`.

## Proposed fix

In `collect_elements`, detect `child.respond_to?(:archetype_id) && child.archetype_id` when `child.rm_type_name == 'C_ARCHETYPE_ROOT'` and thread the current archetype scope (id) alongside each collected `[element, path]` pair, defaulting to `entry[:archetype_id]` until such a boundary is crossed. `build_field` (and the `coded_text_constraints`/`symbol_constraints` callers) should then resolve `term_text` against that per-element scope instead of the entry-wide `entry[:archetype_id]`.

## Suggested test

A `FieldExtractor` spec using an OPT fixture with an embedded CLUSTER (or similar nested archetype) whose at-codes intentionally collide with the host archetype's — `LabResultReport.opt`, as used in the reproduction above, already exercises this shape (`CLUSTER.laboratory_test_analyte.v1`'s at0001/at0024 vs. the host `OBSERVATION.laboratory_test_result.v1`'s at0001) and could be adapted as a fixture, subject to this project's normal licensing/fixture policies for real archetype content.

## Workaround

Anlage's semantic-pathcard extractor (in development) does not use `FieldExtractor` for its own walk — it traverses the OPT tree itself and is being designed from the outset to resolve terminology per the *owning* archetype (this bug is one of the concrete design inputs for that decision). No Anlage-side patch to `FieldExtractor` itself currently exists.
