# RMJSONSerializer output cannot be round-tripped through CompositionFactory.create_from_json (DV_DATE_TIME timezone)

要約: RMJSONSerializerが吐くJSONをCompositionFactory.create_from_jsonで読み戻すと、DV_DATE_TIMEのtimezone派生ivarに対応するFactoryクラスが無くNameErrorになる。

**起票先: [skoba/openehr-ruby#32](https://github.com/skoba/openehr-ruby/issues/32)**

## Suggested labels

`bug`, `serializer`

## Summary

- `RMJSONSerializer` is a generic reflection walker that dumps every non-nil instance variable of an RM object (except `@parent`).
- `DvDateTime#value=` derives and stores several ivars from the ISO8601 string, including `@timezone` — which, for `DvDateTime` (unlike `DvTime`), is a `Timezone` *object*, not a string.
- Feeding that serialized JSON back into `CompositionFactory.create_from_json` fails with `NameError: uninitialized constant OpenEHR::RM::Factory::TimezoneFactory`, because no such factory class exists.
- The gem's own test suite works around this today by hand-curating fixture JSON with only `_type`/`value` keys rather than round-tripping a real serialized object — see Reproduction below.

## Environment

- `openehr` 2.3.0 (rubygems.org)
- `nokogiri` 1.19.4 (x86_64-linux-gnu)
- Ruby 4.0.6

## Reproduction

Run from a checkout of this gem (or any app bundling it) with `bundle exec ruby`:

```ruby
require 'openehr'

# Step 1: build a real Composition via the gem's own recommended
# integration path, using the gem's own test fixture
# (spec/fixtures/health_summary_composition.json).
fixture = File.read('spec/fixtures/health_summary_composition.json')
composition = OpenEHR::RM::CompositionFactory.create_from_json(fixture)

# Step 2: serialize that live object with the gem's own serializer.
json2 = OpenEHR::Serializer::RMJSONSerializer.new(composition).serialize

# Step 3: feed it straight back into the same integration path.
OpenEHR::RM::CompositionFactory.create_from_json(json2)
```

### Actual output (from the reproduction above)

Step 1 succeeds and shows the derived ivars `DvDateTime#value=` populates:

```
Step 1 OK: built OpenEHR::RM::Composition::Composition with context.start_time=#<OpenEHR::RM::DataTypes::Quantity::DateTime::DvDateTime:0x00007bd6618e76d8 @value="2020-09-22T16:18:51.481222+02:00", @year=2020, @month=9, @day=22, @minute=18, @second=51, @hour=16, @fractional_second=0.481222, @timezone=#<OpenEHR::AssumedLibraryTypes::Timezone:0x00007bd6618e5950 @value="+02:00", @hour=2, @minute=0>, @magnitude_status="=", @accuracy=nil, @normal_range=nil, @normal_status=nil, @other_reference_ranges=nil>
  start_time ivars: [:@accuracy, :@day, :@fractional_second, :@hour, :@magnitude_status, :@minute, :@month, :@normal_range, :@normal_status, :@other_reference_ranges, :@second, :@timezone, :@value, :@year]
```

Step 2 succeeds and shows the re-serialized `start_time` now carries all derived fields, including the nested `timezone` object:

```
Step 2 OK: serialized 8581 bytes
  re-serialized start_time hash: {"_type" => "DV_DATE_TIME", "value" => "2020-09-22T16:18:51.481222+02:00", "year" => 2020, "month" => 9, "day" => 22, "minute" => 18, "second" => 51, "hour" => 16, "fractional_second" => 0.481222, "timezone" => {"_type" => "TIMEZONE", "value" => "+02:00", "hour" => 2, "minute" => 0}, "magnitude_status" => "="}
```

Step 3 raises (full exception):

```
(eval at lib/openehr/rm/factory.rb:34):1:in 'OpenEHR::RM::Factory.create': uninitialized constant OpenEHR::RM::Factory::TimezoneFactory (NameError)
Did you mean?  OpenEHR::RM::ActionFactory
	from lib/openehr/rm/factory.rb:34:in 'Module#class_eval'
	from lib/openehr/rm/factory.rb:34:in 'OpenEHR::RM::Factory.create'
	from lib/openehr/rm/factory.rb:82:in 'OpenEHR::RM::Factory.convert_hash'
	from lib/openehr/rm/factory.rb:60:in 'OpenEHR::RM::Factory.convert_value'
	from lib/openehr/rm/factory.rb:41:in 'block in OpenEHR::RM::Factory.params'
	from lib/openehr/rm/factory.rb:38:in 'Hash#each'
	from lib/openehr/rm/factory.rb:38:in 'Enumerable#each_with_object'
	from lib/openehr/rm/factory.rb:38:in 'OpenEHR::RM::Factory.params'
	from lib/openehr/rm/factory.rb:34:in 'OpenEHR::RM::Factory.create'
	from lib/openehr/rm/factory.rb:82:in 'OpenEHR::RM::Factory.convert_hash'
	... (repeats up the containing EVENT_CONTEXT/COMPOSITION hash walk) ...
	from lib/openehr/rm/factory.rb:606:in 'OpenEHR::RM::CompositionFactory.create_from_json'
```

Note: `spec/fixtures/health_summary_composition.json`'s own `start_time` entries only ever contain `{"_type": "DV_DATE_TIME", "value": "..."}` — i.e. the gem's own test corpus already avoids feeding a *real* `RMJSONSerializer` output back through `create_from_json`. This issue reproduces what happens the moment that shortcut is not taken.

## Expected

A `Composition` built via `create_from_json`, serialized via `RMJSONSerializer`, and passed back into `create_from_json` should reconstruct an equivalent object graph — or at minimum should not raise.

## Root cause

`RMJSONSerializer#object_value` (`lib/openehr/serializer/rm_json_serializer.rb:38-50`) dumps every instance variable except `@parent`:

```ruby
EXCLUDED_IVARS = [:@parent].freeze
...
def object_value(value, seen)
  return nil if seen.include?(value)

  seen << value
  hash = {'_type' => OpenEHR::RM.type_name_of(value)}
  (value.instance_variables - EXCLUDED_IVARS).each do |ivar|
    field = value.instance_variable_get(ivar)
    next if field.nil?

    hash[ivar.to_s.delete_prefix('@')] = to_value(field, seen)
  end
  hash
end
```
(`EXCLUDED_IVARS` at line 13)

`DvDateTime#value=` (`lib/openehr/rm/data_types/quantity/date_time.rb:213-224`) derives and stores several ivars from the ISO8601 string on every assignment:

```ruby
def value=(value)
  super(value)
  iso8601date_time = OpenEHR::AssumedLibraryTypes::ISO8601DateTime.new(value)
  self.year = iso8601date_time.year
  self.month = iso8601date_time.month
  self.day = iso8601date_time.day
  self.minute = iso8601date_time.minute
  self.second = iso8601date_time.second
  self.hour = iso8601date_time.hour
  self.fractional_second = iso8601date_time.fractional_second
  self.timezone = iso8601date_time.timezone
end
```

`timezone=` (from `ISO8601TimeModule`, `lib/openehr/assumed_library_types.rb:367-373`) wraps the value in a `Timezone` object (`@timezone = Timezone.new(timezone)`), and `Timezone` (`assumed_library_types.rb:119-162`) itself has ivars `@value, @hour, @minute`. So the serializer emits `timezone` as a nested `{"_type":"TIMEZONE",...}` hash, not a scalar.

On the read side, `OpenEHR::RM::Factory.create_from_json` → `Factory.params` → `Factory.convert_value` → `Factory.convert_hash` (`lib/openehr/rm/factory.rb:75-83`) resolves any hash with a `_type` key via `Factory.create(type, **param)` (`factory.rb:28-35`):

```ruby
def create(type, **param)
  if type.include? '_'
    type = type.downcase.camelize
  else
    type = type.capitalize
  end
  class_eval("#{type}Factory").create(params(param))
end
```

For `_type: "TIMEZONE"`, this resolves to `class_eval("TimezoneFactory")`, and **no `TimezoneFactory` class exists** (confirmed: zero matches for `TimezoneFactory`/`Iso8601` anywhere in `lib/`) — hence the `NameError`.

**Precision note on scope:** unknown *scalar* derived keys (`year`, `month`, `day`, `hour`, `minute`, `second`, `fractional_second`) do **not** cause a crash — they pass through `convert_value` unchanged (`factory.rb:58-66`) and are then silently ignored by `DvTemporal#initialize` (`date_time.rb:16-23`), which only reads `:value, :magnitude_status, :accuracy, :normal_range, :normal_status, :other_reference_ranges`. The crash is specific to **hash-valued** derived fields whose `_type` has no matching `*Factory` (`timezone` → `NameError`) or that have no `_type` at all (`ArgumentError`, `factory.rb:77-81`, via `NON_POLYMORPHIC_TYPE_FOR_KEY` at `factory.rb:17-21` not covering `timezone`). `DvTime`'s `timezone` is a plain `String` (`date_time.rb:136`, `assumed_library_types.rb:375-377`), so it does not trigger this — only `DvDateTime` (and any other class whose ivar happens to hold a `Timezone` object) does.

## Proposed fix

Two options, not mutually exclusive:

1. **(Preferred)** In `RMJSONSerializer`, exclude derived ivars that are fully recomputable from `value` when the class defines a matching setter chain (or, more narrowly, special-case `DvDateTime`/`DvTime`/`DvDate` to serialize only `_type` and `value` plus explicitly-set fields like `magnitude_status`/`accuracy`/`normal_range`). Rationale:
   - (i) This matches openEHR canonical JSON, where `DV_DATE_TIME` is represented by `_type` and `value` alone — the derived fields are not part of the canonical wire format.
   - (ii) Adding a `TimezoneFactory` only patches this one symptom; the same class of bug (a derived object-valued ivar with no matching `*Factory`) can recur for any future RM class that caches a derived object.
2. **(Alternative / complementary)** Make `Factory.create`/`convert_hash` tolerant of a `_type` with no matching `*Factory` constant — e.g. skip that key instead of raising — so that JSON persisted by other tools (or by this serializer, until (1) lands) can still be read back. This helps existing persisted data recover even if (1) is not adopted.

Either way, please add a round-trip regression test: build (or load) a `Composition` containing at least one `DvDateTime` with a non-UTC offset, run it through `RMJSONSerializer#serialize` → `CompositionFactory.create_from_json`, and assert it succeeds and `start_time.value` is preserved. No such test currently exists in the gem's suite (confirmed by grep for `RMJSONSerializer` combined with `create_from_json` in `spec/`) — this is likely why the break went unnoticed.

## Suggested test

A spec building on the existing `spec/lib/openehr/aql/json_roundtrip_spec.rb` pattern (reuses `spec/fixtures/health_summary_composition.json`, a fixture already in the gem's suite): build → serialize → re-parse → assert equivalence of `start_time.value` (and ideally a deep structural comparison). No new fixture content is needed since the existing fixture already contains DV_DATE_TIME with a UTC-offset value.

## Workaround

Anlage's `Opt::CompositionReader` (`app/lib/opt/composition_reader.rb:1-24`) avoids `CompositionFactory.create_from_json` entirely and instead walks parsed JSON `Hash`es directly using the known canonical keys (`_type`/`archetype_node_id`/`data`/`events`/`items`/`value`). Its own header comment states the reason explicitly:

> Walks the parsed JSON Hash directly rather than going through `OpenEHR::RM::CompositionFactory.create_from_json`: that factory dispatches per `"_type"` to a `"<Type>Factory"` class, but `OpenEHR::Serializer::RMJSONSerializer` (a generic reflection walker) also serializes derived ivars `DvDateTime` keeps internally (e.g. `"timezone"`), and the gem has no `TimezoneFactory` to parse that back — `NameError`. Since this app only ever needs to read compositions it produced itself (a known shape), a direct Hash walk sidesteps that gem-level round-trip gap entirely (see `docs/upstream-candidates.md` #5).

This workaround only works because Anlage controls both write and read side (it never round-trips a composition it didn't produce itself). It could be simplified back to using `CompositionFactory.create_from_json` once this issue is fixed upstream.
