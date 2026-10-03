#!/usr/bin/env bash
#
# End-to-end check of the image, run by ci.yml and usable locally:
#
#   docker run --rm --entrypoint /opt/convsync/tests/smoke.sh convsync:local
#
# Every fixture is generated here with tools the image already ships, so the
# repository carries no binary test files.

set -euo pipefail

export CONVSYNC_ROOT
CONVSYNC_ROOT="$(mktemp -d)"
trap 'rm -rf "$CONVSYNC_ROOT"' EXIT
cd "$CONVSYNC_ROOT"

fail() {
	echo "SMOKE FAILED: $*" >&2
	exit 1
}

# No ML runtime may sneak in through a dependency: it is what would bring back
# the AVX2 requirement.
for pkg in numpy onnxruntime torch magika; do
	if python3 -m pip show -q "$pkg" >/dev/null 2>&1; then
		fail "$pkg is installed"
	fi
done

# Born digital PDF: a text layer written by Ghostscript. Long enough to clear
# MIN_CHARS in ocr.sh, otherwise it would be taken for a scan.
mkdir -p 2026
cat >page.ps <<'PS'
/Helvetica findfont 24 scalefont setfont
72 700 moveto (Fattura numero 4417 del 2026) show
72 660 moveto (Cliente Mario Rossi, Via Roma 12) show
72 620 moveto (Servizio di hosting annuale) show
72 580 moveto (Totale imponibile 1250 euro) show
72 540 moveto (Pagamento a trenta giorni data fattura) show
showpage
PS
gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -o 2026/native.pdf page.ps

# Image-only scan: the same page rasterized, so it has no text layer at all.
gs -q -dBATCH -dNOPAUSE -sDEVICE=pnggray -r300 -o page.png 2026/native.pdf
img2pdf --output 2026/scan.pdf page.png
rm -f page.ps page.png

# Flattened form: a scanned body under a text layer that holds only the
# filled-in fields, long enough to clear MIN_CHARS. Only the full-page raster
# check in ocr.sh tells it apart from a born digital PDF.
cat >form.ps <<'PS'
/Helvetica findfont 24 scalefont setfont
72 700 moveto (Convenzione numero 8823 del 2026) show
72 660 moveto (Licenza d'uso del software gestionale) show
showpage
PS
gs -q -dBATCH -dNOPAUSE -sDEVICE=pnggray -r300 -o form.png form.ps
img2pdf --output form-body.pdf form.png
python3 - <<'PY'
import pikepdf
from pikepdf import Dictionary, Name

with pikepdf.open("form-body.pdf") as pdf:
    page = pdf.pages[0]
    page.add_resource(
        Dictionary(Type=Name.Font, Subtype=Name.Type1, BaseFont=Name.Helvetica),
        Name.Font,
        Name.F1,
    )
    page.contents_add(
        pikepdf.Stream(
            pdf,
            b"BT /F1 12 Tf 72 400 Td"
            b" (Ragione sociale Esempio Srl, Via Verdi 7, 00100 Roma) Tj"
            b" 0 -20 Td (Codice fiscale 01234567890, PEC esempio@pec.example) Tj"
            b" 0 -20 Td (Legale rappresentante Mario Bianchi, data 30/09/2026) Tj ET",
        )
    )
    pdf.save("2026/form.pdf")
PY
rm -f form.ps form.png form-body.pdf
# Without this the fixture would pass as a plain scan and prove nothing.
[ "$(pdftotext -q 2026/form.pdf - | tr -d '[:space:]' | wc -c)" -ge 100 ] ||
	fail "form fixture does not clear MIN_CHARS"

# Poster: low-contrast text on a light band, below a black block. A single
# page-wide Otsu threshold lands between the black and the white and turns
# both the band and its text white; only a local threshold recovers it.
cat >poster.ps <<'PS'
0 setgray 0 400 612 392 rectfill
0.8 setgray 0 200 612 120 rectfill
0.55 setgray
/Helvetica-Bold findfont 28 scalefont setfont
72 270 moveto (Spettacolo numero 5190) show
72 230 moveto (Ingresso ad offerta libera) show
showpage
PS
gs -q -dBATCH -dNOPAUSE -sDEVICE=pnggray -r300 -o poster.png poster.ps
img2pdf --output 2026/poster.pdf poster.png
rm -f poster.ps poster.png

# Spreadsheet.
python3 - <<'PY'
from openpyxl import Workbook

workbook = Workbook()
sheet = workbook.active
sheet.title = "Cespiti"
sheet.append(["Bene", "Valore"])
sheet.append(["Notebook", 1200])
workbook.save("2026/cespiti.xlsx")
PY

convsync

grep -q "Fattura numero 4417" _md/2026/native.pdf.md || fail "native PDF not extracted"
[ -f _ocr/2026/scan.ocr.pdf ] || fail "scan not OCRed"
[ ! -f _ocr/2026/native.ocr.pdf ] || fail "born digital PDF was OCRed"
# OCR output is not byte exact: match a token tesseract cannot get wrong at 300 dpi.
grep -q "4417" _md/2026/scan.pdf.md || fail "OCR text missing from the scan"
grep -q "(ocr)" _md/2026/scan.pdf.md || fail "OCR provenance missing from the stamp"
grep -q "| Notebook | 1200 |" _md/2026/cespiti.xlsx.md || fail "XLSX table missing"
[ -f _ocr/2026/form.ocr.pdf ] || fail "flattened form not OCRed"
# 8823 is only in the raster: the fields alone would not produce it.
grep -q "8823" _md/2026/form.pdf.md || fail "OCR text missing from the flattened form"
grep -q "5190" _md/2026/poster.pdf.md || fail "OCR text missing from the low-contrast poster"

# Second run: nothing to do.
convsync | grep -q "converted: 0 | skipped: 5" || fail "rebuild was not incremental"

# A hand edit survives the next forced rebuild as a .new conflict file.
echo "hand edit" >>_md/2026/native.pdf.md
convsync convert --force 2>/dev/null || true
[ -f _md/2026/native.pdf.md.new ] || fail "hand edit not detected"
grep -q "hand edit" _md/2026/native.pdf.md || fail "hand edit overwritten"

# Orphans go away with their source.
rm 2026/scan.pdf
convsync >/dev/null
[ ! -e _md/2026/scan.pdf.md ] || fail "orphan Markdown left behind"
[ ! -e _ocr/2026/scan.ocr.pdf ] || fail "orphan OCR copy left behind"

echo "smoke: ok"
