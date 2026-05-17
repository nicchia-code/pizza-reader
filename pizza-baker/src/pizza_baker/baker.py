from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .codex import (
    CodexError,
    CodexOptions,
    build_chapter_prompt,
    build_concept_prompt,
    chapter_schema,
    concept_schema,
    run_codex_json,
)
from .epub import ExtractedEpub, SpineItem, extract_epub_bytes, extract_epub_file
from .model import (
    PizzaBook,
    PizzaChapter,
    base_name,
    chapter_id,
    clean_title,
    encode_reader_document,
    normalize_imported_text,
    stable_book_id,
)


@dataclass(frozen=True)
class BakeOptions:
    use_codex: bool = True
    codex: CodexOptions = CodexOptions()
    plain_json: bool = False
    progress: Callable[[int, str], None] | None = None


@dataclass(frozen=True)
class BakeResult:
    book: PizzaBook
    document_bytes: bytes
    filename: str
    metadata: dict[str, Any]


@dataclass(frozen=True)
class SentenceUnit:
    index: int
    text: str
    word_count: int


def bake_epub(path: str, *, options: BakeOptions | None = None) -> BakeResult:
    _report(options, 5, "Lettura EPUB")
    extracted = extract_epub_file(path)
    _report(options, 15, "EPUB estratto")
    return _bake_extracted(extracted, options=options or BakeOptions())


def bake_epub_bytes(
    data: bytes,
    *,
    source_name: str,
    options: BakeOptions | None = None,
) -> BakeResult:
    _report(options, 5, "Lettura EPUB")
    extracted = extract_epub_bytes(data, source_name=source_name)
    _report(options, 15, "EPUB estratto")
    return _bake_extracted(extracted, options=options or BakeOptions())


def _bake_extracted(extracted: ExtractedEpub, *, options: BakeOptions) -> BakeResult:
    _report(options, 20, "Pianificazione capitoli")
    raw_plan, chapter_plan_used_fallback = _chapter_plan(extracted, options)
    plan = _normalize_chapter_plan(raw_plan, extracted.items)
    if plan is None:
        plan = _fallback_chapter_plan(extracted.items)
        chapter_plan_used_fallback = True
    _report(options, 30, "Capitoli pianificati")

    book_title = _derive_book_title(raw_plan, extracted)
    authors = _derive_authors(raw_plan, extracted)
    spoiler_free_summary = _clean_inline_text(str(raw_plan.get("spoiler_free_summary", "")))

    pizza_chapters, concept_metadata, concept_fallback_count = _build_chapters(
        extracted.items,
        plan,
        options,
    )
    if not pizza_chapters:
        pizza_chapters = _fallback_pizza_chapters(extracted.items)

    text_fingerprint = "\n\n".join(chapter.text for chapter in pizza_chapters)
    book = PizzaBook(
        id=stable_book_id("pizzabook", book_title, text_fingerprint),
        title=book_title,
        author=", ".join(authors) if authors else None,
        language=extracted.language,
        chapters=pizza_chapters,
        metadata={
            "source_file": base_name(extracted.source_name),
            "source_kind": "pizzabook",
            "source_format": "epub",
            "prepared_by": "pizza-baker",
            "pizza_baker": {
                "version": 1,
                "spoiler_free_summary": spoiler_free_summary,
                "chapter_plan_used_fallback": chapter_plan_used_fallback,
                "concept_fallback_count": concept_fallback_count,
                "spine_item_count": len(extracted.items),
                "spine_items": [
                    {
                        "index": item.index,
                        "href": item.href,
                        "member": item.member,
                        "title_hint": item.title_hint,
                        "word_count": item.word_count,
                    }
                    for item in extracted.items
                ],
                "chapters": concept_metadata,
            },
        },
    )
    output_name = f"{_sanitize_filename(book.title)}.pizzabook"
    _report(options, 95, "Serializzazione .pizzabook")
    return BakeResult(
        book=book,
        document_bytes=encode_reader_document(book, gzip_output=not options.plain_json),
        filename=output_name,
        metadata={
            "title": book.title,
            "author": book.author,
            "chapter_count": len(book.chapters),
            "chapter_plan_used_fallback": chapter_plan_used_fallback,
            "concept_fallback_count": concept_fallback_count,
            "filename": output_name,
        },
    )


def _chapter_plan(
    extracted: ExtractedEpub,
    options: BakeOptions,
) -> tuple[dict[str, Any], bool]:
    if not options.use_codex:
        return _fallback_raw_plan(extracted), True

    prompt = build_chapter_prompt(
        source_name=extracted.source_name,
        source_title=extracted.title,
        source_authors=extracted.authors,
        items=extracted.items,
        max_preview_chars=options.codex.max_preview_chars,
    )
    try:
        return (
            run_codex_json(
                prompt,
                options=options.codex,
                schema=chapter_schema(),
                schema_filename="chapter-schema.json",
            ),
            False,
        )
    except (CodexError, FileNotFoundError):
        return _fallback_raw_plan(extracted), True


def _build_chapters(
    items: list[SpineItem],
    plan: list[dict[str, Any]],
    options: BakeOptions,
) -> tuple[list[PizzaChapter], list[dict[str, Any]], int]:
    chapters: list[PizzaChapter] = []
    metadata: list[dict[str, Any]] = []
    concept_fallback_count = 0
    global_concept_index = 1

    for planned_index, chapter in enumerate(plan, start=1):
        _report(
            options,
            30 + int((planned_index - 1) / max(1, len(plan)) * 55),
            f"Concetti {planned_index}/{len(plan)}",
        )
        selected = items[int(chapter["start_spine_index"]) - 1 : int(chapter["end_spine_index"])]
        title = _derive_chapter_title(chapter, selected, planned_index)
        kind = str(chapter.get("kind", "chapter")).strip() or "chapter"
        chapter_text = normalize_imported_text(
            "\n\n".join(item.text for item in selected if item.text.strip())
        )
        sentences = _split_sentences(chapter_text)
        concepts, used_fallback = _concept_plan(title, kind, sentences, options)
        if used_fallback:
            concept_fallback_count += 1

        concept_entries: list[dict[str, Any]] = []
        concept_texts: list[str] = []
        covered: set[int] = set()
        for local_index, concept in enumerate(concepts, start=1):
            start = int(concept["start_sentence_index"])
            end = int(concept["end_sentence_index"])
            body = _sentences_text(sentences, start, end)
            if not body:
                continue
            covered.update(range(start, end + 1))
            concept_texts.append(body)
            concept_entries.append(
                {
                    "index": local_index,
                    "global_index": global_concept_index,
                    "title": _clean_inline_text(str(concept.get("title", ""))) or f"Concept {local_index}",
                    "start_sentence_index": start,
                    "end_sentence_index": end,
                    "word_count": _word_count(body),
                }
            )
            global_concept_index += 1

        display_title = _chapter_title_with_concept_context(title, concept_entries)
        omitted = [sentence for sentence in sentences if sentence.index not in covered]
        readable_text = normalize_imported_text("\n\n".join(concept_texts))
        if readable_text:
            chapters.append(
                PizzaChapter(
                    id=chapter_id(len(chapters) + 1),
                    title=display_title,
                    text=readable_text,
                )
            )

        chapter_metadata: dict[str, Any] = {
            "index": planned_index,
            "title": display_title,
            "kind": kind,
            "start_spine_index": int(chapter["start_spine_index"]),
            "end_spine_index": int(chapter["end_spine_index"]),
            "word_count": _word_count(chapter_text),
            "omitted_sentence_count": len(omitted),
            "omitted_word_count": sum(sentence.word_count for sentence in omitted),
            "concept_count": len(concept_entries),
            "concepts": concept_entries,
        }
        if display_title != title:
            chapter_metadata["source_title"] = title
        metadata.append(chapter_metadata)

    _report(options, 88, "Concetti completati")
    return chapters, metadata, concept_fallback_count


def _concept_plan(
    chapter_title: str,
    chapter_kind: str,
    sentences: list[SentenceUnit],
    options: BakeOptions,
) -> tuple[list[dict[str, Any]], bool]:
    if not sentences:
        return [], False
    if not options.use_codex:
        return _fallback_concepts(sentences, options.codex.concept_min_words), True

    prompt = build_concept_prompt(
        chapter_title=chapter_title,
        chapter_kind=chapter_kind,
        sentences=[
            {
                "sentence_index": sentence.index,
                "word_count": sentence.word_count,
                "text": sentence.text,
            }
            for sentence in sentences
        ],
        min_words=options.codex.concept_min_words,
    )
    try:
        raw = run_codex_json(
            prompt,
            options=options.codex,
            schema=concept_schema(),
            schema_filename="concept-schema.json",
        )
    except (CodexError, FileNotFoundError):
        return _fallback_concepts(sentences, options.codex.concept_min_words), True

    concepts = _normalize_concept_plan(raw, sentences, options.codex.concept_min_words)
    if concepts is None:
        return _fallback_concepts(sentences, options.codex.concept_min_words), True
    return concepts, False


def _fallback_raw_plan(extracted: ExtractedEpub) -> dict[str, Any]:
    return {
        "book_title": clean_title(extracted.title, extracted.source_name),
        "authors": extracted.authors,
        "spoiler_free_summary": "",
        "chapters": _fallback_chapter_plan(extracted.items),
    }


def _fallback_chapter_plan(items: list[SpineItem]) -> list[dict[str, Any]]:
    return [
        {
            "title": item.title_hint or f"Chapter {item.index}",
            "kind": "chapter",
            "start_spine_index": item.index,
            "end_spine_index": item.index,
        }
        for item in items
    ]


def _normalize_chapter_plan(
    raw_plan: dict[str, Any],
    items: list[SpineItem],
) -> list[dict[str, Any]] | None:
    raw_chapters = raw_plan.get("chapters")
    if not isinstance(raw_chapters, list) or not raw_chapters:
        return None

    expected_start = 1
    normalized: list[dict[str, Any]] = []
    last_index = len(items)
    for raw in raw_chapters:
        if not isinstance(raw, dict):
            return None
        try:
            start = int(raw.get("start_spine_index"))
            end = int(raw.get("end_spine_index"))
        except (TypeError, ValueError):
            return None
        if start != expected_start or end < start or end > last_index:
            return None
        normalized.append(
            {
                "title": _clean_inline_text(str(raw.get("title", ""))),
                "kind": _clean_inline_text(str(raw.get("kind", "chapter"))) or "chapter",
                "start_spine_index": start,
                "end_spine_index": end,
            }
        )
        expected_start = end + 1
    if expected_start != last_index + 1:
        return None
    return normalized


def _normalize_concept_plan(
    raw_plan: dict[str, Any],
    sentences: list[SentenceUnit],
    min_words: int,
) -> list[dict[str, Any]] | None:
    raw_concepts = raw_plan.get("concepts")
    if not isinstance(raw_concepts, list):
        return None

    normalized: list[dict[str, Any]] = []
    previous_end = 0
    sentence_count = len(sentences)
    total_words = sum(sentence.word_count for sentence in sentences)
    for raw in raw_concepts:
        if not isinstance(raw, dict):
            return None
        try:
            start = int(raw.get("start_sentence_index"))
            end = int(raw.get("end_sentence_index"))
        except (TypeError, ValueError):
            return None
        if start < 1 or end < start or end > sentence_count or start <= previous_end:
            return None
        body = _sentences_text(sentences, start, end)
        words = _word_count(body)
        if total_words >= min_words and words < min_words:
            return None
        normalized.append(
            {
                "index": len(normalized) + 1,
                "title": _clean_inline_text(str(raw.get("title", ""))) or f"Concept {len(normalized) + 1}",
                "start_sentence_index": start,
                "end_sentence_index": end,
                "word_count": words,
            }
        )
        previous_end = end
    return normalized


def _fallback_concepts(sentences: list[SentenceUnit], min_words: int) -> list[dict[str, Any]]:
    if not sentences:
        return []
    total_words = sum(sentence.word_count for sentence in sentences)
    if total_words <= min_words:
        return [
            {
                "index": 1,
                "title": "Testo",
                "start_sentence_index": sentences[0].index,
                "end_sentence_index": sentences[-1].index,
                "word_count": total_words,
            }
        ]

    concepts: list[dict[str, Any]] = []
    start = sentences[0].index
    running = 0
    for sentence in sentences:
        running += sentence.word_count
        if running >= min_words:
            concepts.append(
                {
                    "index": len(concepts) + 1,
                    "title": f"Parte {len(concepts) + 1}",
                    "start_sentence_index": start,
                    "end_sentence_index": sentence.index,
                    "word_count": running,
                }
            )
            start = sentence.index + 1
            running = 0
    if start <= sentences[-1].index:
        if concepts and running < min_words:
            concepts[-1]["end_sentence_index"] = sentences[-1].index
            concepts[-1]["word_count"] = int(concepts[-1]["word_count"]) + running
        else:
            concepts.append(
                {
                    "index": len(concepts) + 1,
                    "title": f"Parte {len(concepts) + 1}",
                    "start_sentence_index": start,
                    "end_sentence_index": sentences[-1].index,
                    "word_count": running,
                }
            )
    return concepts


def _fallback_pizza_chapters(items: list[SpineItem]) -> list[PizzaChapter]:
    chapters: list[PizzaChapter] = []
    for item in items:
        text = normalize_imported_text(item.text)
        if not text:
            continue
        chapters.append(
            PizzaChapter(
                id=chapter_id(len(chapters) + 1),
                title=item.title_hint or f"Chapter {item.index}",
                text=text,
            )
        )
    return chapters


def _split_sentences(text: str) -> list[SentenceUnit]:
    compact = _clean_inline_text(text)
    if not compact:
        return []
    parts = [
        part.strip()
        for part in re.split(r"(?<=[.!?…])\s+", compact)
        if part.strip()
    ] or [compact]
    return [
        SentenceUnit(index=index, text=part, word_count=_word_count(part))
        for index, part in enumerate(parts, start=1)
    ]


def _sentences_text(sentences: list[SentenceUnit], start: int, end: int) -> str:
    return " ".join(sentence.text for sentence in sentences[start - 1 : end]).strip()


def _word_count(text: str) -> int:
    return len(re.findall(r"\S+", text))


def _clean_inline_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _derive_book_title(raw_plan: dict[str, Any], extracted: ExtractedEpub) -> str:
    raw_title = _clean_inline_text(str(raw_plan.get("book_title", "")))
    return clean_title(raw_title or extracted.title, extracted.source_name)


def _derive_authors(raw_plan: dict[str, Any], extracted: ExtractedEpub) -> list[str]:
    raw_authors = raw_plan.get("authors")
    if isinstance(raw_authors, list):
        authors = [
            author
            for value in raw_authors
            if isinstance(value, str)
            if (author := _clean_inline_text(value))
        ]
        if authors:
            return list(dict.fromkeys(authors))
    return extracted.authors


def _derive_chapter_title(
    chapter: dict[str, Any],
    selected: list[SpineItem],
    chapter_index: int,
) -> str:
    title = _clean_inline_text(str(chapter.get("title", "")))
    if title:
        return title
    first_hint = next((item.title_hint for item in selected if item.title_hint), "")
    return first_hint or f"Chapter {chapter_index}"


def _chapter_title_with_concept_context(
    title: str,
    concept_entries: list[dict[str, Any]],
) -> str:
    if not _is_bare_chapter_marker(title):
        return title
    concept_title = next(
        (
            clean
            for concept in concept_entries
            if (clean := _clean_inline_text(str(concept.get("title", ""))))
            if _is_meaningful_concept_title(clean)
        ),
        "",
    )
    if not concept_title:
        return title
    return f"{title} - {concept_title}"


def _is_bare_chapter_marker(title: str) -> bool:
    clean = _clean_inline_text(title).strip(".:-")
    return bool(re.fullmatch(r"\d+", clean))


def _is_meaningful_concept_title(title: str) -> bool:
    clean = _clean_inline_text(title)
    return not re.fullmatch(r"(?i)(testo|parte|concept)\s*\d*", clean)


def _sanitize_filename(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", value.strip())
    safe = re.sub(r"_+", "_", safe).strip("._-")
    return safe[:72] or "book"


def write_bake_result(result: BakeResult, output_path: str | None = None) -> str:
    path = Path(output_path) if output_path else Path(result.filename)
    path.write_bytes(result.document_bytes)
    return str(path)


def _report(options: BakeOptions | None, percent: int, message: str) -> None:
    callback = options.progress if options else None
    if callback is not None:
        callback(max(0, min(100, percent)), message)
