from __future__ import annotations

import json
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .epub import SpineItem


DEFAULT_MODEL = "gpt-5.5"
DEFAULT_REASONING_EFFORT = "low"


@dataclass(frozen=True)
class CodexOptions:
    codex_bin: str = "codex"
    model: str | None = DEFAULT_MODEL
    reasoning_effort: str | None = DEFAULT_REASONING_EFFORT
    max_preview_chars: int = 1600
    concept_min_words: int = 300


class CodexError(RuntimeError):
    pass


def run_codex_json(
    prompt: str,
    *,
    options: CodexOptions,
    schema: dict[str, Any],
    schema_filename: str,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="pizza-baker-") as tmpdir:
        schema_path = Path(tmpdir) / schema_filename
        schema_path.write_text(json.dumps(schema, indent=2), encoding="utf-8")

        cmd = [options.codex_bin, "exec"]
        if options.model:
            cmd.extend(["--model", options.model])
        if options.reasoning_effort:
            cmd.extend(
                [
                    "--config",
                    f"model_reasoning_effort={json.dumps(options.reasoning_effort)}",
                ]
            )
        cmd.extend(
            [
                "--json",
                "--skip-git-repo-check",
                "--sandbox",
                "read-only",
                "--output-schema",
                str(schema_path),
                "-",
            ]
        )

        result = subprocess.run(
            cmd,
            input=prompt,
            text=True,
            capture_output=True,
            check=False,
        )

    messages: list[str] = []
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") != "item.completed":
            continue
        item = event.get("item", {})
        if item.get("type") == "agent_message" and isinstance(item.get("text"), str):
            messages.append(item["text"])

    if not messages:
        stderr = result.stderr.strip() or "codex exec returned no agent_message item"
        raise CodexError(stderr)

    try:
        payload = json.loads(messages[-1])
    except json.JSONDecodeError as exc:
        raise CodexError(f"Invalid JSON returned by codex exec: {exc}") from exc
    if not isinstance(payload, dict):
        raise CodexError("Codex JSON payload must be an object.")
    return payload


def build_chapter_prompt(
    *,
    source_name: str,
    source_title: str | None,
    source_authors: list[str],
    items: list[SpineItem],
    max_preview_chars: int,
) -> str:
    payload = {
        "book_file": Path(source_name).name,
        "source_title": source_title,
        "source_authors": source_authors,
        "spine_items": [
            {
                "spine_index": item.index,
                "href": item.href,
                "member": item.member,
                "title_hint": item.title_hint,
                "char_count": len(item.text),
                "word_count": item.word_count,
                "preview": _truncate_preview(item.text, max_preview_chars),
            }
            for item in items
        ],
    }
    instructions = """
You are segmenting an EPUB into chapters for PizzaReader.
You must group the ordered spine items into contiguous chapter ranges.
Return JSON only, matching the provided schema exactly.

Rules:
- Every spine item must belong to exactly one chapter.
- Chapters must cover the full spine from item 1 to the last item, with no gaps or overlaps.
- Do not split inside a single spine item.
- Keep the response minimal: one `book_title`, one `authors` array, one `spoiler_free_summary`, then for each range return `title`, `kind`, `start_spine_index`, `end_spine_index`.
- Prefer an explicit work title found in `source_title`, TOC labels, or visible headings/text over an inferred title.
- Only infer the overall work title from general knowledge if the source material does not reveal it.
- Keep `book_title` in the same language and script as the source material. Never translate it.
- `authors` must contain the most likely author names, one name per list item, in the source language/script.
- Prefer explicit authors from `source_authors` or visible source metadata/text.
- Do not include translators, editors, publishers, blogs, conversion credits, or source websites unless they are clearly the work authors.
- If the author cannot be determined confidently, return an empty `authors` array.
- `spoiler_free_summary` must be concise and spoiler-free, 2-4 sentences.
- Prefer explicit chapter titles from title_hint and visible headings in the preview only to decide boundaries.
- Chapter titles must be useful in a reader UI. If a source chapter label is only a number, combine it with a short descriptive label from the preview, for example `2 - Il ritrovamento di Wellington`. Do not return only the number.
- If opening pages are clearly front matter, keep them together as "Front Matter".
- If closing pages are clearly appendices, notes, or back matter, keep them together.
- If the book already looks like one chapter per spine item, keep that structure.
""".strip()
    return f"{instructions}\n\nINPUT_JSON:\n{json.dumps(payload, ensure_ascii=False, indent=2)}\n"


def build_concept_prompt(
    *,
    chapter_title: str,
    chapter_kind: str,
    sentences: list[dict[str, Any]],
    min_words: int,
) -> str:
    payload = {
        "chapter_title": chapter_title,
        "chapter_kind": chapter_kind,
        "minimum_words_per_concept": min_words,
        "total_words": sum(int(sentence["word_count"]) for sentence in sentences),
        "sentences": sentences,
    }
    instructions = """
You are segmenting one book chapter into conceptual reading chunks.
Return JSON only, matching the provided schema exactly.

Rules:
- Group the ordered sentences into contiguous concept ranges.
- Return ranges only. Do not rewrite, paraphrase, summarize, or quote the book text in your response.
- Concepts may leave gaps. Omit sentences that are not reader-facing prose: standalone chapter title pages, repeated running headers, table-of-contents lines, decorative labels, copyright/publisher boilerplate, or navigation-only text.
- Omitted sentences must not appear inside any concept range.
- Concept ranges must be ordered and non-overlapping.
- Do not split inside a sentence.
- A concept must contain at least `minimum_words_per_concept` words whenever the chapter has enough reader-facing prose to make that possible.
- It is fine and often better for a concept to be longer than the minimum. Do not create short chunks just to keep them even.
- If the entire chapter has fewer than `minimum_words_per_concept` words but is real reader-facing prose, return exactly one concept covering that prose.
- If the chapter contains no reader-facing prose, return an empty `concepts` array.
- Prefer natural semantic boundaries.
- `title` should be a short label in the source language describing the concept, not a summary sentence.
""".strip()
    return f"{instructions}\n\nINPUT_JSON:\n{json.dumps(payload, ensure_ascii=False, indent=2)}\n"


def chapter_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["book_title", "authors", "spoiler_free_summary", "chapters"],
        "properties": {
            "book_title": {"type": "string"},
            "authors": {"type": "array", "items": {"type": "string"}},
            "spoiler_free_summary": {"type": "string"},
            "chapters": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["title", "kind", "start_spine_index", "end_spine_index"],
                    "properties": {
                        "title": {"type": "string"},
                        "kind": {
                            "type": "string",
                            "enum": [
                                "front_matter",
                                "chapter",
                                "part",
                                "section",
                                "appendix",
                                "back_matter",
                            ],
                        },
                        "start_spine_index": {"type": "integer", "minimum": 1},
                        "end_spine_index": {"type": "integer", "minimum": 1},
                    },
                },
            },
        },
    }


def concept_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["concepts"],
        "properties": {
            "concepts": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["index", "title", "start_sentence_index", "end_sentence_index", "word_count"],
                    "properties": {
                        "index": {"type": "integer", "minimum": 1},
                        "title": {"type": "string"},
                        "start_sentence_index": {"type": "integer", "minimum": 1},
                        "end_sentence_index": {"type": "integer", "minimum": 1},
                        "word_count": {"type": "integer", "minimum": 0},
                    },
                },
            }
        },
    }


def _truncate_preview(text: str, max_chars: int) -> str:
    compact = " ".join(text.split())
    if len(compact) <= max_chars:
        return compact
    head = max_chars * 3 // 4
    tail = max(0, max_chars - head - 9)
    return f"{compact[:head]} [...] {compact[-tail:]}"
