#!/usr/bin/env python3
"""
Convert files that LLM tooling cannot read as they are (PDF, XLSX) into Markdown
under _md/.

markitdown is not used here: its core dependency `magika` pulls in `onnxruntime`,
whose prebuilt wheels are compiled with AVX2 and abort with SIGILL on CPUs without
it. pdftotext (poppler) and openpyxl need no such runtime.

The tree to convert is $CONVSYNC_ROOT (default /data, the volume of the image).

Usage: convert.py [--force]
"""

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(os.environ.get("CONVSYNC_ROOT", "/data")).resolve()
OUT = ROOT / "_md"
OCR = ROOT / "_ocr"
EXCLUDED_DIRS = {"_md", "_ocr"}

# Provenance stamp written on the first line of every generated file. The digest
# covers the body only, so a hand edit can be told apart from a stale rebuild.
MARKER = "<!-- generated from {source} sha256:{digest} -->"
MARKER_RE = re.compile(r"^<!-- generated from .* sha256:([0-9a-f]{64}) -->\n")


def digest_of(body: str) -> str:
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def read_generated(dst: Path) -> tuple[str | None, str]:
    """Return the recorded digest (None if unstamped) and the body on disk."""
    text = dst.read_text(encoding="utf-8")
    match = MARKER_RE.match(text)
    if match is None:
        return None, text.strip("\n")
    return match.group(1), text[match.end() :].strip("\n")


def ocr_variant(src: Path) -> Path | None:
    """The copy of a scanned PDF that ocr.sh enriched with a text layer."""
    if src.suffix.lower() != ".pdf":
        return None
    candidate = OCR / src.relative_to(ROOT).with_suffix(".ocr.pdf")
    return candidate if candidate.is_file() else None


def pdf_to_markdown(src: Path) -> str:
    # An image-only scan carries no text layer: read the OCR copy instead, so
    # the result lands at the same path as any other document.
    src = ocr_variant(src) or src
    # pdftotext -layout keeps labels and values on the same visual line;
    # pdfminer groups text boxes by column and breaks form-like PDFs.
    result = subprocess.run(
        ["pdftotext", "-layout", "-enc", "UTF-8", "-nopgbrk", str(src), "-"],
        capture_output=True,
        text=True,
        check=True,
    )
    text = result.stdout.strip()
    # Fenced block: the alignment is significant, don't let Markdown collapse it.
    return f"```\n{text}\n```" if text else ""


def xlsx_to_markdown(src: Path) -> str:
    # data_only=True returns the values cached by Excel/LibreOffice, not formulas.
    workbook = load_workbook(src, data_only=True, read_only=True)
    chunks = []

    for sheet in workbook.worksheets:
        rows = [
            ["" if cell is None else str(cell).strip().replace("|", "\\|") for cell in row]
            for row in sheet.iter_rows(values_only=True)
        ]
        rows = [row for row in rows if any(row)]
        if not rows:
            continue

        width = max(len(row) for row in rows)
        rows = [row + [""] * (width - len(row)) for row in rows]

        chunks.append(f"## {sheet.title}")
        chunks.append("")
        chunks.append("| " + " | ".join(rows[0]) + " |")
        chunks.append("|" + "---|" * width)
        chunks.extend("| " + " | ".join(row) + " |" for row in rows[1:])
        chunks.append("")

    workbook.close()
    return "\n".join(chunks).strip()


CONVERTERS = {".pdf": pdf_to_markdown, ".xlsx": xlsx_to_markdown}


def remove_orphans() -> int:
    """Delete generated files whose source document no longer exists."""
    removed = 0
    if not OUT.is_dir():
        return removed

    for dst in sorted(OUT.rglob("*.md")) + sorted(OUT.rglob("*.md.new")):
        # "_md/2021/degiro/x.pdf.md" -> "2021/degiro/x.pdf"
        rel = dst.relative_to(OUT)
        if rel.suffix == ".new":
            rel = rel.with_suffix("")
        src = ROOT / rel.with_suffix("")
        if src.exists():
            continue
        dst.unlink()
        print(f"REMOVED: {dst.relative_to(ROOT)}")
        removed += 1

    # Drop directories left empty, deepest first.
    for path in sorted(OUT.rglob("*"), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()

    return removed


def main() -> int:
    force = "--force" in sys.argv[1:]
    if not ROOT.is_dir():
        print(f"Not a directory: {ROOT} (mount the documents there)", file=sys.stderr)
        return 2
    removed = remove_orphans()
    converted = skipped = conflicts = failed = 0

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [
            d for d in dirnames if d not in EXCLUDED_DIRS and not d.startswith(".")
        ]

        for filename in sorted(filenames):
            src = Path(dirpath) / filename
            convert = CONVERTERS.get(src.suffix.lower())
            if convert is None:
                continue

            rel = src.relative_to(ROOT)
            # Keep the original extension in the name: "File inventario.pdf" and
            # "File inventario.xlsx" coexist in the same folder.
            dst = OUT / f"{rel}.md"

            # A re-run of ocr.sh changes the OCR copy, not the original.
            mtime = src.stat().st_mtime
            ocr = ocr_variant(src)
            if ocr is not None:
                mtime = max(mtime, ocr.stat().st_mtime)

            if not force and dst.exists() and dst.stat().st_mtime >= mtime:
                skipped += 1
                continue

            try:
                text = convert(src)
            except Exception as exc:
                print(f"FAILED: {rel} ({exc})", file=sys.stderr)
                failed += 1
                continue

            # An image-only scan yields nothing until ocr.sh has run.
            if not text:
                print(f"EMPTY (scanned PDF, run convsync ocr?): {rel}", file=sys.stderr)

            conflict = dst.with_name(dst.name + ".new")
            stamp = MARKER.format(
                source=f"{rel} (ocr)" if ocr is not None else rel,
                digest=digest_of(text),
            )

            if dst.exists():
                stored, body = read_generated(dst)
                # An unstamped file predates this check and is assumed generated.
                if stored is not None and stored != digest_of(body) and body != text:
                    conflict.write_text(f"{stamp}\n\n{text}\n", encoding="utf-8")
                    print(f"CONFLICT (edited by hand): {rel}", file=sys.stderr)
                    conflicts += 1
                    continue

            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(f"{stamp}\n\n{text}\n", encoding="utf-8")
            # The hand edit and the converter agree again, or never diverged.
            if conflict.exists():
                conflict.unlink()
            converted += 1

    print(
        f"converted: {converted} | skipped: {skipped} | removed: {removed} | "
        f"conflicts: {conflicts} | failed: {failed}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
