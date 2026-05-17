from __future__ import annotations

import gzip
import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import PurePath
from typing import Any


PIZZA_READER_FORMAT = "pizza_reader_document"
PIZZA_READER_VERSION = 1
HASH_PREFIX = "sha256:"


@dataclass(frozen=True)
class PizzaChapter:
    id: str
    title: str
    text: str

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "text": self.text,
        }


@dataclass(frozen=True)
class PizzaBook:
    id: str
    title: str
    chapters: list[PizzaChapter]
    author: str | None = None
    language: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_json(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "id": self.id,
            "title": self.title,
        }
        if self.author is not None:
            payload["author"] = self.author
        if self.language is not None:
            payload["language"] = self.language
        payload["chapters"] = [chapter.to_json() for chapter in self.chapters]
        if self.metadata:
            payload["metadata"] = self.metadata
        return payload


def validate_book(book: PizzaBook) -> None:
    if not book.id.strip():
        raise ValueError("Pizza book id is required.")
    if not book.title.strip():
        raise ValueError("Pizza book title is required.")
    if not book.chapters:
        raise ValueError("Pizza book must contain at least one chapter.")

    seen: set[str] = set()
    for chapter in book.chapters:
        if not chapter.id.strip():
            raise ValueError("Pizza chapter id is required.")
        if not chapter.title.strip():
            raise ValueError(f'Pizza chapter "{chapter.id}" title is required.')
        if not chapter.text.strip():
            raise ValueError(f'Pizza chapter "{chapter.id}" text is empty.')
        if chapter.id in seen:
            raise ValueError(f'Duplicate Pizza chapter id "{chapter.id}".')
        seen.add(chapter.id)
    assert_json_value(book.metadata)


def assert_json_value(value: Any) -> None:
    if value is None or isinstance(value, (bool, int, str)):
        return
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise ValueError("JSON numbers must be finite.")
        return
    if isinstance(value, list):
        for item in value:
            assert_json_value(item)
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("JSON object keys must be strings.")
            assert_json_value(item)
        return
    raise ValueError(f"Unsupported JSON value type {type(value).__name__}.")


def canonical_json(value: Any) -> str:
    if value is None or isinstance(value, (bool, int, str)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise ValueError("JSON numbers must be finite.")
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, list):
        return "[" + ",".join(canonical_json(item) for item in value) + "]"
    if isinstance(value, dict):
        entries: list[tuple[str, Any]] = []
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("JSON object keys must be strings.")
            entries.append((key, item))
        entries.sort(key=lambda entry: entry[0])
        return "{" + ",".join(
            f"{json.dumps(key, ensure_ascii=False, separators=(',', ':'))}:"
            f"{canonical_json(item)}"
            for key, item in entries
        ) + "}"
    raise ValueError(f"Unsupported JSON value type {type(value).__name__}.")


def canonical_content(book: PizzaBook) -> str:
    validate_book(book)
    return canonical_json(book.to_json())


def content_hash(book: PizzaBook) -> str:
    digest = hashlib.sha256(canonical_content(book).encode("utf-8")).hexdigest()
    return f"{HASH_PREFIX}{digest}"


def reader_document(book: PizzaBook) -> dict[str, Any]:
    validate_book(book)
    return {
        "format": PIZZA_READER_FORMAT,
        "version": PIZZA_READER_VERSION,
        "content_hash": content_hash(book),
        "book": book.to_json(),
    }


def encode_reader_document(book: PizzaBook, *, gzip_output: bool = True) -> bytes:
    source = canonical_json(reader_document(book)).encode("utf-8")
    return gzip.compress(source) if gzip_output else source


def normalize_imported_text(text: str) -> str:
    lines = [
        re.sub(r"[ \t]+", " ", line).strip()
        for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    ]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def clean_metadata_text(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = normalize_imported_text(value)
    return cleaned or None


def base_name(path: str) -> str:
    return PurePath(path).name


def base_name_without_extension(path: str) -> str:
    name = base_name(path)
    stem = name.rsplit(".", 1)[0] if "." in name and not name.startswith(".") else name
    title = re.sub(r"\s+", " ", re.sub(r"[_-]+", " ", stem)).strip()
    return title or "Untitled"


def clean_title(title: str | None, source_name: str) -> str:
    return clean_metadata_text(title) or base_name_without_extension(source_name)


def stable_book_id(source_kind: str, title: str, text: str) -> str:
    digest = hashlib.sha256(f"{source_kind}\n{title}\n{text}".encode("utf-8"))
    return f"{source_kind}-{digest.hexdigest()[:16]}"


def chapter_id(index: int) -> str:
    return f"chapter-{index}"


def sanitize_title(value: str, fallback: str) -> str:
    cleaned = clean_metadata_text(value)
    return cleaned or fallback
