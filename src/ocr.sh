#!/usr/bin/env bash
#
# Add a text layer to scanned PDFs so convert.py can extract them:
# pdftotext reads the text layer, which an image-only scan does not have.
#
# The result mirrors the source tree under _ocr/ with an .ocr.pdf suffix, so
# "2021/cespiti-2021.pdf" -> "_ocr/2021/cespiti-2021.ocr.pdf". Originals are
# never modified.
#
# The tree to process is $CONVSYNC_ROOT (default /data, the volume of the image).
#
# Requires: ocrmypdf, tesseract-ocr + language packs, ghostscript, unpaper,
# poppler-utils (all in the image)
# Usage: ocr.sh [--force]

set -euo pipefail

ROOT="${CONVSYNC_ROOT:-/data}"
[ -d "$ROOT" ] || {
	echo "Not a directory: $ROOT (mount the documents there)" >&2
	exit 2
}
ROOT="$(cd "$ROOT" && pwd)"
OUT="$ROOT/_ocr"
LANGS="${OCR_LANGS:-ita+eng}"

# Below this many characters a PDF is treated as an image-only scan. A born
# digital PDF always yields far more; a scan yields nothing or stray glyphs.
MIN_CHARS=100

BIN="$(command -v ocrmypdf || true)"
[ -n "$BIN" ] || {
	echo "ocrmypdf not found in PATH" >&2
	exit 1
}

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

cd "$ROOT"

ocred=0
skipped=0
native=0
removed=0
failed=0

# Drop OCR output whose source document no longer exists.
if [ -d "$OUT" ]; then
	while IFS= read -r -d '' dst; do
		rel="${dst#"$OUT/"}"
		[ -f "$ROOT/${rel%.ocr.pdf}.pdf" ] && continue
		rm -f "$dst"
		echo "REMOVED: _ocr/$rel"
		removed=$((removed + 1))
	done < <(find "$OUT" -type f -name '*.ocr.pdf' -print0)
	find "$OUT" -type d -empty -delete
fi

while IFS= read -r -d '' f; do
	rel="${f#./}"
	dst="$OUT/${rel%.pdf}.ocr.pdf"

	if [ "$FORCE" -eq 0 ] && [ -f "$dst" ] && [ "$dst" -nt "$f" ]; then
		skipped=$((skipped + 1))
		continue
	fi

	# Leave born digital PDFs alone: convert.py already extracts them, and
	# rasterizing them would only degrade the text.
	chars=$(pdftotext -q "$f" - 2>/dev/null | tr -d '[:space:]' | wc -c)
	if [ "$chars" -ge "$MIN_CHARS" ]; then
		native=$((native + 1))
		continue
	fi

	mkdir -p "$(dirname "$dst")"

	# --force-ocr: scanners wrap the image in a tagged PDF, which ocrmypdf
	# refuses to touch otherwise. There is no text layer to lose here.
	# --output-type pdfa: PDF/A-2b, the archival format for tax documents.
	if ! "$BIN" \
		-l "$LANGS" \
		--output-type pdfa \
		--force-ocr \
		--rotate-pages \
		--deskew \
		--clean \
		--optimize 1 \
		--quiet \
		"$f" "$dst"; then
		echo "FAILED: $rel" >&2
		rm -f "$dst"
		failed=$((failed + 1))
		continue
	fi

	echo "OCR: $rel -> _ocr/${rel%.pdf}.ocr.pdf"
	ocred=$((ocred + 1))
done < <(find . \
	\( -path ./_md -o -path ./_ocr -o -path './.*' \) -prune -o \
	-type f -iname '*.pdf' -print0)

echo "ocr: $ocred | skipped: $skipped | native: $native | removed: $removed | failed: $failed"
[ "$failed" -eq 0 ]
