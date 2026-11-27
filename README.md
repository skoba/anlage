# Anlage

> **参照実装です。認証がありません。実在の患者のデータを入れないでください。外から届く場所で動かさないでください。**
> **This is a reference implementation without authentication. Do not enter real patient data, and do not expose it to an untrusted network.**
> All values in the sample data are synthetic and all patients are fictitious.

English | [日本語](README.ja.md)

Anlage (German: the primordium from which an organ develops) is a reference implementation of an
[openEHR](https://specifications.openehr.org/)-based EHR, written in Ruby on Rails.

## What it aims for

Anlage aims to be the primordium of any EHR. On top of the clinical models (openEHR archetypes and templates), it holds
logic, screens and flows, and user layers **as definitions, placed at runtime**. No code is generated and the server is not
restarted: an EHR changes shape the moment a definition is placed.

What runs today is the first of those layers: drop in an Operational Template, and a form, validation, persistence, AQL and
FHIR profiles come alive. Next come a patient screen that reads like a chart (a default screen that needs no definition, which a
definition can override) and logic that is registered together with a template.

It is built in four layers: [`openehr-ruby`](https://github.com/skoba/openehr-ruby) (RM/AM in pure Ruby) →
[`openehr-rails`](https://github.com/skoba/openehr-rails) (Rails integration, RM persistence, AQL) →
`openehr-rails-startup` (application generator) → **Anlage** (this repository).

## What works today

Each item is backed by specs in `spec/` (CI runs them on every push).

- **Template → form, validation, persistence.** Drop an OPT on the templates screen; the form is built from it at runtime,
  values are validated against its constraints and saved as an openEHR COMPOSITION
  ([`app/lib/opt/`](app/lib/opt/)). Templates with SECTION, INSTRUCTION and repeated roots save too (the referral letter
  `jp_referral`). Template detail, version history and diffs between versions.
- **Patients (EHR) and records.** Create a patient (an EHR), select it, and records are saved into its EHR. Records can be
  amended (openEHR versions), logically deleted, and read back in the form's layout.
- **AQL.** An AQL console (from openehr-rails) over the RM graph, and a **query builder**: find an item by words, add it to the
  columns or conditions, and an AQL query is assembled, linted against the registered templates, and run. It can also query
  across archetype versions where a reviewed mapping exists.
- **Path cards (semantic index).** Every node of a registered template becomes a searchable card; search by Japanese clinical
  words, with a reviewed alias table.
- **FHIR.** StructureDefinition profiles generated from each registered template (`/fhir/r5/StructureDefinition/:id`), and the
  openehr-rails CapabilityStatement. Reading records as FHIR resources is not available yet (known limitation 19).
- **openEHR REST.** EHR, COMPOSITION and AQL endpoints from openehr-rails (`/openehr/v1`), with a Postman collection in
  [`docs/demo/postman/`](docs/demo/postman/).

What it cannot do, and what to watch out for: [`docs/known-limitations.md`](docs/known-limitations.md) (in Japanese).
Above all, **there is no authentication or authorisation**.

Search and query evaluation results (questions, scores, known weaknesses, how to reproduce):
[`docs/evaluation-summary.md`](docs/evaluation-summary.md) (in Japanese). In short, as measured on main `4b25af4`
(2026-11-26): card search v1 Top-1 17/17, v2 10/13; AQL questions 12/12 for both the reference queries and the query
builder. The question sets are small; read the counts, not the percentages.

## Running it

### Development (Ruby 4.0.10)

```sh
bundle install
bin/rails db:prepare
bin/rails server          # http://localhost:3000
bundle exec rspec         # tests (system specs need Chrome)
```

### Docker

The image uses the production settings (`RAILS_ENV=production`). It starts without `config/master.key` if you pass
`SECRET_KEY_BASE`. Data (SQLite) lives in `/rails/storage`; mount a volume there. Start it with Basic authentication:

```sh
docker build -t anlage .
docker run -d --name anlage -p 8080:80 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e ANLAGE_BASIC_AUTH_USERNAME=demo -e ANLAGE_BASIC_AUTH_PASSWORD='<a long password>' \
  -v anlage-storage:/rails/storage anlage
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/up        # 200 (no auth on /up)
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/patients  # 401
```

Load the sample data (5 fixture templates; 9 fictitious patients, 84 records). This **deletes all data and reloads it**, so it
must be enabled explicitly:

```sh
docker exec -e ANLAGE_ALLOW_DEMO_RESET=1 anlage bin/rails demo:reset
```

Open http://localhost:8080/ (user `demo` and your password). Sample OPTs are in [`spec/fixtures/opt/`](spec/fixtures/opt/)
(sources in [`docs/demo/opt-catalog.md`](docs/demo/opt-catalog.md)).

**Basic authentication** is applied to every screen and API only when **both** environment variables are set (setting just one
fails at boot). It is sent in clear text, so use it behind TLS. It is a minimal safeguard and does not make it acceptable to
enter real patient data. Without it, the openehr-rails engine (AQL console, FHIR, openEHR REST) returns 403 in production, but
**Anlage's own screens stay open to anyone** (known limitation 6b).

**Asking in plain language (LLM) is off by default.** The query builder can turn a Japanese question into a selection of items
and conditions with an LLM; Anlage then builds and checks the AQL itself. It calls an external API only when **all** of these are
set (a key alone does not turn it on), and every call costs money:

```sh
  -e ANLAGE_LLM=anthropic -e ANLAGE_LLM_MODEL='<model ID>' -e ANTHROPIC_API_KEY='<your key>' \
  -e ANLAGE_LLM_DAILY_CALL_LIMIT=100   # optional; calls per day (default 100)
```

The question text and the names of the candidate items are sent to the API; record contents are not. Anlage's screens have no
login of their own, so anyone who can reach an instance with this turned on can spend your API budget, up to the daily limit.
Details: [`docs/nl-query.md`](docs/nl-query.md) (Japanese).

The user interface is in Japanese only (known limitation 5).

## Status

- Released: [v0.2.0](https://github.com/skoba/anlage/releases/tag/v0.2.0) (2026-11-27). Changes: [`CHANGELOG.md`](CHANGELOG.md)
- Dependencies: openehr 2.6.1, openehr-rails 0.12.0, Ruby 4.0.10
- Good first issues: [label `good first issue`](https://github.com/skoba/anlage/labels/good%20first%20issue)
- Progress logs and design documents (in Japanese): [`docs/reports/`](docs/reports/), [`docs/design/`](docs/design/)

## License and community

Apache License 2.0 ([`LICENSE`](LICENSE)).

NPO openEHR Japan holds regular online meetings ([connpass](https://openehr-japan.connpass.com/)).
External issues and contributions are not yet formally accepted; this will be announced.
