from __future__ import annotations

import unittest

from pizza_baker.epub import extract_epub_bytes

from .testing import minimal_epub


class EpubTest(unittest.TestCase):
    def test_extracts_spine_items_in_order(self) -> None:
        extracted = extract_epub_bytes(minimal_epub(), source_name="sample.epub")

        self.assertEqual(extracted.title, "Sample Pizza")
        self.assertEqual(extracted.authors, ["Ada Baker"])
        self.assertEqual([item.title_hint for item in extracted.items], ["Start", "End"])
        self.assertEqual(extracted.items[0].text, "Start\n\nFirst chapter text.")


if __name__ == "__main__":
    unittest.main()
