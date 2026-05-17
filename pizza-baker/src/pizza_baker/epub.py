from __future__ import annotations

import html
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from html.parser import HTMLParser
from io import BytesIO
from pathlib import PurePosixPath
from zipfile import ZipFile

from .model import clean_metadata_text, normalize_imported_text


HTML_MEDIA_TYPES = {
    "application/xhtml+xml",
    "application/xml",
    "text/html",
}


@dataclass(frozen=True)
class SpineItem:
    index: int
    href: str
    member: str
    title_hint: str
    text: str
    body_html: str

    @property
    def word_count(self) -> int:
        return len(re.findall(r"\S+", self.text))


@dataclass(frozen=True)
class ExtractedEpub:
    source_name: str
    title: str | None
    authors: list[str]
    language: str | None
    items: list[SpineItem]


class EpubError(ValueError):
    pass


class _TextExtractor(HTMLParser):
    block_tags = {
        "article",
        "blockquote",
        "div",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "li",
        "p",
        "pre",
        "section",
        "td",
        "th",
        "tr",
    }

    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag.lower() in self.block_tags:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self.block_tags:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if data:
            self.parts.append(data)

    def text(self) -> str:
        return normalize_imported_text(html.unescape("".join(self.parts)))


class _HeadingExtractor(HTMLParser):
    heading_tags = {"h1", "h2", "h3"}

    def __init__(self) -> None:
        super().__init__()
        self.current_tag: str | None = None
        self.current_parts: list[str] = []
        self.headings: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag.lower() in self.heading_tags:
            self.current_tag = tag.lower()
            self.current_parts = []

    def handle_endtag(self, tag: str) -> None:
        if self.current_tag and tag.lower() == self.current_tag:
            heading = clean_metadata_text("".join(self.current_parts))
            if heading:
                self.headings.append(heading)
            self.current_tag = None
            self.current_parts = []

    def handle_data(self, data: str) -> None:
        if self.current_tag and data:
            self.current_parts.append(data)


def extract_epub_bytes(data: bytes, *, source_name: str) -> ExtractedEpub:
    with ZipFile(BytesIO(data), "r") as zf:
        return _extract_epub(zf, source_name=source_name)


def extract_epub_file(path: str) -> ExtractedEpub:
    with ZipFile(path, "r") as zf:
        return _extract_epub(zf, source_name=path)


def _extract_epub(zf: ZipFile, *, source_name: str) -> ExtractedEpub:
    try:
        container = _read_member(zf, "META-INF/container.xml")
    except KeyError as exc:
        raise EpubError("EPUB is missing META-INF/container.xml.") from exc

    opf_path = _find_rootfile(container)
    opf_root = _parse_xml(_read_member(zf, opf_path))
    title = _parse_book_title(opf_root)
    authors = _parse_book_authors(opf_root)
    language = _first_element_text(opf_root, "language")
    manifest = _parse_manifest(opf_root)
    toc_id, spine_ids = _parse_spine(opf_root)

    toc_titles = _parse_nav(zf, manifest, opf_path)
    if not toc_titles:
        toc_titles = _parse_ncx(zf, manifest, opf_path, toc_id)

    items: list[SpineItem] = []
    for item_id in spine_ids:
        manifest_item = manifest.get(item_id)
        if not manifest_item:
            continue
        if not _is_readable_document(manifest_item["media_type"], manifest_item["href"]):
            continue
        member = _resolve_member(opf_path, manifest_item["href"])
        if member not in zf.namelist():
            continue
        raw = _read_member(zf, member)
        body_html = _extract_body(raw)
        text = _html_to_text(raw)
        if not text:
            continue
        title_hint = toc_titles.get(member) or _guess_title(raw, manifest_item["href"])
        items.append(
            SpineItem(
                index=len(items) + 1,
                href=manifest_item["href"],
                member=member,
                title_hint=title_hint,
                text=text,
                body_html=body_html,
            )
        )

    if not items:
        raise EpubError("EPUB does not contain readable spine items.")
    return ExtractedEpub(
        source_name=source_name,
        title=title,
        authors=authors,
        language=language,
        items=items,
    )


def _read_member(zf: ZipFile, member: str) -> bytes:
    with zf.open(member, "r") as f:
        return f.read()


def _parse_xml(data: bytes) -> ET.Element:
    return ET.fromstring(data)


def _find_rootfile(container_xml: bytes) -> str:
    root = _parse_xml(container_xml)
    rootfile = root.find(".//{*}rootfile")
    if rootfile is None:
        raise EpubError("No <rootfile> found in META-INF/container.xml.")
    full_path = rootfile.attrib.get("full-path")
    if not full_path:
        raise EpubError("The <rootfile> element has no full-path attribute.")
    return full_path


def _parse_manifest(opf_root: ET.Element) -> dict[str, dict[str, str]]:
    manifest: dict[str, dict[str, str]] = {}
    for item in opf_root.findall(".//{*}manifest/{*}item"):
        item_id = item.attrib.get("id")
        href = item.attrib.get("href")
        if not item_id or not href:
            continue
        manifest[item_id] = {
            "href": href,
            "media_type": item.attrib.get("media-type", ""),
            "properties": item.attrib.get("properties", ""),
        }
    return manifest


def _parse_spine(opf_root: ET.Element) -> tuple[str | None, list[str]]:
    spine = opf_root.find(".//{*}spine")
    if spine is None:
        raise EpubError("No <spine> found in OPF package.")
    toc_id = spine.attrib.get("toc")
    item_ids = [item.attrib.get("idref") for item in spine.findall("{*}itemref")]
    return toc_id, [item_id for item_id in item_ids if item_id]


def _parse_book_title(opf_root: ET.Element) -> str | None:
    return _first_element_text(opf_root, "title")


def _parse_book_authors(opf_root: ET.Element) -> list[str]:
    creators: list[tuple[str, str]] = []
    seen: set[str] = set()
    for creator in opf_root.findall(".//{*}metadata/{*}creator"):
        author = clean_metadata_text("".join(creator.itertext()))
        if not author:
            continue
        normalized = author.casefold()
        if normalized in seen:
            continue
        role = next(
            (
                value.strip().casefold()
                for name, value in creator.attrib.items()
                if name == "role" or name.endswith("}role")
            ),
            "",
        )
        creators.append((author, role))
        seen.add(normalized)
    author_creators = [name for name, role in creators if role == "aut"]
    return author_creators or [name for name, _role in creators]


def _first_element_text(node: ET.Element | None, local_name: str) -> str | None:
    if node is None:
        return None
    for element in node.iter():
        if element.tag.rsplit("}", 1)[-1] == local_name:
            return clean_metadata_text("".join(element.itertext()))
    return None


def _resolve_member(opf_path: str, href: str) -> str:
    relative = href.split("#", 1)[0].strip()
    base_dir = PurePosixPath(opf_path).parent
    return str(base_dir / PurePosixPath(relative)).lstrip("/")


def _is_readable_document(media_type: str, href: str) -> bool:
    lower_type = media_type.lower()
    lower_href = href.lower()
    return (
        lower_type in HTML_MEDIA_TYPES
        or "html" in lower_type
        or lower_href.endswith((".html", ".htm", ".xhtml"))
    )


def _detect_encoding(raw: bytes) -> str:
    head = raw[:512].decode("utf-8", errors="ignore")
    match = re.search(r'encoding=["\']([^"\']+)["\']', head, flags=re.IGNORECASE)
    return match.group(1) if match else "utf-8"


def _extract_body(raw_html: bytes) -> str:
    source = raw_html.decode(_detect_encoding(raw_html), errors="replace")
    match = re.search(r"<body[^>]*>(.*)</body>", source, flags=re.IGNORECASE | re.DOTALL)
    return match.group(1) if match else source


def _html_to_text(raw_html: bytes) -> str:
    parser = _TextExtractor()
    parser.feed(_extract_body(raw_html))
    return parser.text()


def _guess_title(raw_html: bytes, fallback_href: str) -> str:
    parser = _HeadingExtractor()
    parser.feed(_extract_body(raw_html))
    if parser.headings:
        return parser.headings[0]
    stem = PurePosixPath(fallback_href).stem.replace("_", " ").replace("-", " ").strip()
    return stem or "Chapter"


def _parse_nav(
    zf: ZipFile,
    manifest: dict[str, dict[str, str]],
    opf_path: str,
) -> dict[str, str]:
    nav_item_id = next(
        (
            item_id
            for item_id, item in manifest.items()
            if "nav" in item.get("properties", "").split()
        ),
        None,
    )
    if not nav_item_id:
        return {}
    nav_member = _resolve_member(opf_path, manifest[nav_item_id]["href"])
    if nav_member not in zf.namelist():
        return {}

    try:
        root = _parse_xml(_read_member(zf, nav_member))
    except ET.ParseError:
        return {}

    toc: dict[str, str] = {}
    for nav in root.findall(".//{*}nav"):
        nav_type = nav.attrib.get("{http://www.idpf.org/2007/ops}type", "")
        if nav_type and nav_type != "toc":
            continue
        for anchor in nav.findall(".//{*}a"):
            href = (anchor.attrib.get("href") or "").strip()
            if not href or href.startswith("#"):
                continue
            title = clean_metadata_text("".join(anchor.itertext()))
            if title:
                toc.setdefault(_resolve_member(opf_path, href), title)
    return toc


def _parse_ncx(
    zf: ZipFile,
    manifest: dict[str, dict[str, str]],
    opf_path: str,
    toc_id: str | None,
) -> dict[str, str]:
    if not toc_id or toc_id not in manifest:
        return {}
    ncx_member = _resolve_member(opf_path, manifest[toc_id]["href"])
    if ncx_member not in zf.namelist():
        return {}

    try:
        root = _parse_xml(_read_member(zf, ncx_member))
    except ET.ParseError:
        return {}

    toc: dict[str, str] = {}
    for nav_point in root.findall(".//{*}navPoint"):
        content = nav_point.find("{*}content")
        label = nav_point.find(".//{*}text")
        if content is None:
            continue
        href = (content.attrib.get("src") or "").strip()
        if not href or href.startswith("#"):
            continue
        title = clean_metadata_text("".join(label.itertext())) if label is not None else None
        if title:
            toc.setdefault(_resolve_member(opf_path, href), title)
    return toc
