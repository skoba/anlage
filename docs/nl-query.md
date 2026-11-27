# Asking in plain language (natural language to AQL)

Japanese version (supplementary): [`nl-query.ja.md`](nl-query.ja.md). If the two differ, this English version is authoritative.

In the query builder, you can type a question as a Japanese sentence. An LLM picks the items to show and the conditions, and
the query builder builds the AQL. **It is off by default**; when off, the query builder works as before, by picking items by
hand. The design is in [`docs/design/s4-nl-aql-plan.md`](design/s4-nl-aql-plan.md) (Japanese).

## Current state (2026-11-27)

- The screen, the query flow, the Claude API adapter (`anthropic`) and the OpenAI adapter (`openai`) are in place
- **Both adapters have only been checked with specs that do not call out. The real APIs have not been called even once**
  (that happens when a key is provided). How correctly each model picks items has not been measured yet
- An adapter for a locally run model (`local`, for an Ollama server on the same machine) is in place. It was tried with one small
  model on a CPU-only machine: about 30 seconds per question, and not every answer was usable

## Turning it on

The operator sets environment variables and restarts. It cannot be switched from the screen.

| Environment variable | Meaning | Default |
|---|---|---|
| `ANLAGE_LLM` | Name of the adapter to use (`anthropic`, `openai`, `local`, `recorded`). This is the "on" setting | none (off) |
| `ANLAGE_LLM_MODEL` | Model ID (for `anthropic`, `openai` and `local`; see the provider's model list, or the name of the model you pulled into Ollama). There is no default | none |
| `ANTHROPIC_API_KEY` | Claude API key (for `anthropic`) | none |
| `OPENAI_API_KEY` | OpenAI API key (for `openai`) | none |
| `ANLAGE_LLM_BASE_URL` | Endpoint (for `openai`). Change it to point at a server that offers the same Chat Completions interface | `https://api.openai.com/v1` |
| `ANLAGE_LLM_DAILY_CALL_LIMIT` | Calls allowed per day. Once reached, the LLM is not called and you pick by hand | 100 |
| `ANLAGE_LLM_RECORDINGS` | Directory of recorded responses (for `recorded`; development and tests) | none |

- It turns on only when `ANLAGE_LLM` **and** everything that adapter needs (model ID, key) are all set. A key alone does not turn it on
- **Which company receives the text is decided by `ANLAGE_LLM`.** With `ANLAGE_LLM=anthropic` the text goes to Anthropic and the
  OpenAI key is not read; with `ANLAGE_LLM=openai` it goes to OpenAI (or to `ANLAGE_LLM_BASE_URL`) and the Anthropic key is not read
- If something is missing, it stays off and the query builder shows the reason
- With `openai`, only an endpoint on the same machine (127.0.0.1, localhost) is treated as "not sent outside"; there the key is
  optional and the warning is not shown. Any other endpoint counts as outside and must be https
- With `local`, the text goes to an Ollama server on the same machine (`ANLAGE_LLM_BASE_URL`, default `http://127.0.0.1:11434`).
  Nothing is sent outside, no key is needed, and the warning is not shown. Only an endpoint on the same machine is accepted
- One question waits at most 30 seconds (300 seconds with `local`). The output limit is 2,000 tokens (400 with `local`)
- Keys are passed as environment variables. They are not written to the repository or to configuration files, and their values
  do not appear on the screen or in logs

## Cost and the daily limit

- With an adapter that calls an external API, every call costs money
- Anlage's screens have no login of their own. **Anyone who can reach an instance with this turned on can call the LLM.** The
  daily limit is the safeguard
- Today's call count and token counts are shown in the "文で問う" section of the query builder. The counts are kept per day in
  `storage/llm_usage.json` (dates and numbers only; neither the question nor the response is stored)

## What is sent, and what is not

| Sent | Not sent |
|---|---|
| The question the user typed | Record contents (query results, patient IDs, names) |
| The list of candidate items (item name, section name, type, names of value-set values, unit, template name) | Paths, archetype IDs, at-codes, descriptions, bindings to external terminologies |
| A fixed instruction text | Template (OPT) files, licensed terminology content |

- **Do not write patient information in the question.** The question is sent as typed
- The LLM returns only item numbers, operators and values. Anlage looks up paths and codes from its own index. The query
  builder builds the AQL, and only AQL that passes the checker (linter) is run
- The explanation of what was queried is assembled by Anlage from the wording of the chosen items. The LLM does not write it

## How to use it

1. In the query builder, type a question under "文で問う" and press "選択を作る"
2. The selection made by the LLM appears under "表示する項目" and "条件". Read the explanation and check the selection; you can change it
3. Press "実行"

When a selection could not be made (unreadable response, daily limit, connection failure), the reason is shown and you can
continue by picking items by hand below.

The user interface is in Japanese only.
