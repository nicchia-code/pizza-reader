from __future__ import annotations

from io import BytesIO
from zipfile import ZIP_DEFLATED, ZipFile


def minimal_epub() -> bytes:
    buffer = BytesIO()
    with ZipFile(buffer, "w", ZIP_DEFLATED) as zf:
        zf.writestr(
            "META-INF/container.xml",
            """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
""",
        )
        zf.writestr(
            "OPS/package.opf",
            """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Sample Pizza</dc:title>
    <dc:creator>Ada Baker</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="chap-1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chap-2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chap-1"/>
    <itemref idref="chap-2"/>
  </spine>
</package>
""",
        )
        zf.writestr(
            "OPS/chapter1.xhtml",
            """<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>Start</h1><p>First chapter text.</p>
</body></html>""",
        )
        zf.writestr(
            "OPS/chapter2.xhtml",
            """<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>End</h1><p>Second chapter text.</p>
</body></html>""",
        )
    return buffer.getvalue()
