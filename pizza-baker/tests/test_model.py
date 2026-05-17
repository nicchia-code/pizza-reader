from __future__ import annotations

import gzip
import json
import unittest

from pizza_baker.model import PizzaBook, PizzaChapter, encode_reader_document


class ModelTest(unittest.TestCase):
    def test_encodes_reader_document_as_gzip_json(self) -> None:
        book = PizzaBook(
            id="pizzabook-test",
            title="Test",
            chapters=[PizzaChapter(id="chapter-1", title="One", text="Hello pizza.")],
        )

        payload = gzip.decompress(encode_reader_document(book))
        document = json.loads(payload.decode("utf-8"))

        self.assertEqual(document["format"], "pizza_reader_document")
        self.assertEqual(document["version"], 1)
        self.assertTrue(document["content_hash"].startswith("sha256:"))
        self.assertEqual(document["book"]["title"], "Test")


if __name__ == "__main__":
    unittest.main()
