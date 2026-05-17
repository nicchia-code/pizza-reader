from __future__ import annotations

import gzip
import json
import unittest

from pizza_baker.baker import (
    BakeOptions,
    _chapter_title_with_concept_context,
    bake_epub_bytes,
)

from .testing import minimal_epub


class BakerTest(unittest.TestCase):
    def test_bakes_without_codex_using_source_text(self) -> None:
        result = bake_epub_bytes(
            minimal_epub(),
            source_name="sample.epub",
            options=BakeOptions(use_codex=False),
        )

        document = json.loads(gzip.decompress(result.document_bytes).decode("utf-8"))
        book = document["book"]

        self.assertEqual(book["title"], "Sample Pizza")
        self.assertEqual(book["author"], "Ada Baker")
        self.assertEqual(len(book["chapters"]), 2)
        self.assertIn("First chapter text.", book["chapters"][0]["text"])
        self.assertEqual(book["metadata"]["source_kind"], "pizzabook")

    def test_numeric_chapter_title_uses_concept_context(self) -> None:
        self.assertEqual(
            _chapter_title_with_concept_context(
                "2",
                [{"title": "Il ritrovamento di Wellington"}],
            ),
            "2 - Il ritrovamento di Wellington",
        )
        self.assertEqual(
            _chapter_title_with_concept_context(
                "Capitolo iniziale",
                [{"title": "Altro"}],
            ),
            "Capitolo iniziale",
        )
        self.assertEqual(
            _chapter_title_with_concept_context("3", [{"title": "Parte 1"}]),
            "3",
        )


if __name__ == "__main__":
    unittest.main()
