# pizza-baker

`pizza-baker` converts EPUB files into PizzaReader `.pizzabook` documents.

The generated file is a gzip-compressed JSON document compatible with
PizzaReader's `PizzaBookCodec`:

```json
{
  "format": "pizza_reader_document",
  "version": 1,
  "content_hash": "sha256:...",
  "book": {
    "id": "...",
    "title": "...",
    "author": "...",
    "language": "...",
    "chapters": []
  }
}
```

## Server

```bash
uv run pizza-baker serve --host 0.0.0.0 --port 8090
```

Then open `http://127.0.0.1:8090/`. The mobile-first UI uploads an EPUB,
starts a background job, polls `/api/jobs/{id}`, shows a percentage, and exposes
the `.pizzabook` download when ready.

Codex is used by default through `codex exec --json` with schema-constrained
outputs, `--sandbox read-only`, `gpt-5.5`, and `model_reasoning_effort=low`.

Important: Codex never writes or rewrites book prose. It only returns ranges over
spine items and sentence indexes. `pizza-baker` builds the final `.pizzabook` by
copying text from the original EPUB ranges.

## CLI Usage

```bash
uv run pizza-baker bake book.epub
```

Write a specific output path:

```bash
uv run pizza-baker bake book.epub -o book.pizzabook
```

Inspect the generated document without gzip:

```bash
uv run pizza-baker bake book.epub --plain-json -o book.pizzabook.json
```

## Current Scope

- EPUB input only.
- Reads OPF metadata, spine order, NAV/NCX table-of-contents labels, and
  visible headings.
- Emits one PizzaReader chapter per readable spine item.
- Uses Codex to create chapter and concept range plans.
- Keeps source spine diagnostics and concept ranges in `book.metadata`.

The package is intentionally separate from PizzaReader. PizzaReader can keep a
fast local importer, while this utility can grow more aggressive EPUB cleanup
and AI-assisted chapter planning without changing the app flow.
