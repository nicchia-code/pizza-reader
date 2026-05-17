from __future__ import annotations

import argparse
from typing import Sequence

from .baker import BakeOptions, bake_epub, write_bake_result
from .codex import CodexOptions, DEFAULT_MODEL, DEFAULT_REASONING_EFFORT


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pizza-baker")
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve = subparsers.add_parser("serve", help="Run the FastAPI server")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8090)
    serve.add_argument("--reload", action="store_true")

    bake = subparsers.add_parser("bake", help="Bake an EPUB into .pizzabook")
    bake.add_argument("epub")
    bake.add_argument("--output", "-o")
    bake.add_argument("--no-codex", action="store_true")
    bake.add_argument("--plain-json", action="store_true")
    bake.add_argument("--codex-bin", default="codex")
    bake.add_argument("--model", default=DEFAULT_MODEL)
    bake.add_argument("--reasoning-effort", default=DEFAULT_REASONING_EFFORT)
    bake.add_argument("--concept-min-words", type=int, default=300)
    bake.add_argument("--max-preview-chars", type=int, default=1600)

    args = parser.parse_args(argv)
    if args.command == "serve":
        import uvicorn

        uvicorn.run(
            "pizza_baker.api:app",
            host=args.host,
            port=args.port,
            reload=args.reload,
        )
        return 0

    def report(percent: int, message: str) -> None:
        print(f"{percent:3d}% {message}", flush=True)

    result = bake_epub(
        args.epub,
        options=BakeOptions(
            use_codex=not args.no_codex,
            plain_json=args.plain_json,
            codex=CodexOptions(
                codex_bin=args.codex_bin,
                model=args.model,
                reasoning_effort=args.reasoning_effort,
                max_preview_chars=args.max_preview_chars,
                concept_min_words=args.concept_min_words,
            ),
            progress=report,
        ),
    )
    output = write_bake_result(result, args.output)
    print(output)
    return 0
