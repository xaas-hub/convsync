[![Docker Pulls](https://img.shields.io/docker/pulls/frugan/convsync)](https://hub.docker.com/r/frugan/convsync)
[![Docker Image Size](https://img.shields.io/docker/image-size/frugan/convsync/latest)](https://hub.docker.com/r/frugan/convsync)
[![Build Status](https://github.com/xaas-hub/convsync/actions/workflows/ci.yml/badge.svg)](https://github.com/xaas-hub/convsync/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/xaas-hub/convsync)](https://github.com/xaas-hub/convsync/releases)
[![License](https://img.shields.io/github/license/xaas-hub/convsync)](https://github.com/xaas-hub/convsync/blob/main/LICENSE)

# ConvSync

Keeps a folder of **PDF and XLSX documents mirrored as Markdown**, so that LLM
agents and RAG tooling can read them. Scanned PDFs get a text layer through
**local OCR** first. Runs incrementally, cleans up after deleted documents and
never overwrites a Markdown file you edited by hand.

**No machine learning runtime inside** — no numpy, no onnxruntime, no torch —
so it runs on **x86-64 CPUs without AVX2**, where markitdown, docling and most
of the AI-oriented converters abort with `Illegal instruction` (SIGILL). It
also keeps the image small, the output deterministic, and the documents on your
machine.

```text
documents/                         documents/_md/
├── 2026/                          ├── 2026/
│   ├── invoice-4417.pdf     ──►   │   ├── invoice-4417.pdf.md
│   ├── scan-receipt.pdf     ──►   │   ├── scan-receipt.pdf.md   (via _ocr/)
│   └── assets.xlsx          ──►   │   └── assets.xlsx.md
```

---

## What is in the image

| | |
|---|---|
| `convsync` | entry point: `sync`, `ocr`, `convert` |
| [ocrmypdf](https://github.com/ocrmypdf/OCRmyPDF) + Tesseract | text layer for scanned PDFs, output as PDF/A-2b |
| `pdftotext -layout` (poppler) | PDF text extraction, keeping labels and values on the same line |
| [openpyxl](https://openpyxl.readthedocs.io) | XLSX sheets as Markdown tables |
| Ghostscript, unpaper | ocrmypdf runtime dependencies |

Tesseract selects its SIMD code path at runtime and falls back to SSE on CPUs
without AVX2. Every CI build fails if numpy, onnxruntime, torch or magika end
up installed.

## Available tags

| Tag | Content |
|---|---|
| `latest` | last build of the `main` branch |
| `main` | the same, to refer to the branch explicitly |
| `1`, `1.2`, `1.2.3` | semantic releases |

Platforms: `linux/amd64`, `linux/arm64`.

## Quick start

```bash
docker run --rm --network none \
  -v "$PWD/documents:/data" \
  frugan/convsync:1
```

The Markdown lands in `documents/_md/`, the OCR copies of scanned PDFs in
`documents/_ocr/`. Run it again whenever documents change: only what is new or
modified is processed.

`--network none` is not required, but nothing in the pipeline needs the
network: with it, the documents provably stay on the machine.

### File ownership

The container runs as root by default. With a Docker daemon configured for
`userns-remap`, container uid 0 maps to your host user and the generated files
are yours. Without it, pass your ids:

```bash
docker run --rm --network none --user "$(id -u):$(id -g)" \
  -v "$PWD/documents:/data" frugan/convsync:1
```

### Inside a Compose stack

The typical setup: the documents live in a gitignored folder of the project,
and the agents read the Markdown next to them.

```yaml
services:
  convsync:
    image: frugan/convsync:1
    profiles: ["tools"]        # never started by `docker compose up`
    network_mode: none
    volumes:
      - ./agents/sources:/data
```

```bash
docker compose run --rm convsync
```

## Commands

```bash
convsync [sync] [--force]   # OCR the scanned PDFs, then convert everything
convsync ocr [--force]      # only add the text layer to scanned PDFs
convsync convert [--force]  # only convert to Markdown
convsync bash               # anything else is executed as is
```

`--force` rebuilds everything instead of what changed. With `sync` it applies
to both steps, which means re-OCRing every scan: use `convert --force` when only
the Markdown has to be regenerated.

Every run ends with a summary, and the exit code is non-zero if any document
failed:

```text
ocr: 1 | skipped: 12 | native: 30 | removed: 0 | failed: 0
converted: 2 | skipped: 41 | removed: 1 | conflicts: 0 | failed: 0
```

## How it works

**OCR only where it is needed.** A PDF that yields fewer than 100 characters of
text is treated as an image-only scan and goes through ocrmypdf into
`_ocr/<path>.ocr.pdf`. Born digital PDFs are left alone: rasterizing them would
only degrade the text. Originals are never modified.

**Mirrored output.** `_md/` reproduces the source tree, keeping the original
extension in the name, so `report.pdf` and `report.xlsx` in the same folder do
not collide.

**Incremental.** A document is converted again only when it (or its OCR copy)
is newer than its Markdown.

**Orphans.** When a document is deleted, its Markdown and its OCR copy go with
it, and so do the folders left empty.

**Hand edits are safe.** Each generated file starts with a provenance stamp
carrying the SHA-256 of its body:

```text
<!-- generated from 2026/invoice-4417.pdf sha256:3f1a… -->
```

If the body no longer matches the stamp, someone edited it: the rebuild is
written next to it as `<name>.md.new` and reported as a `CONFLICT`, instead of
overwriting the edit. Merge by hand and delete the `.new` file; it also goes
away on its own as soon as the edit and the converter agree again.

**Output shape.** PDF text is wrapped in a fenced code block, because the
alignment produced by `pdftotext -layout` is meaningful on forms, invoices and
tax documents, and Markdown would collapse it. XLSX sheets become one table per
sheet, with the values cached by Excel or LibreOffice rather than the formulas.

## Configuration

| Variable | Default | |
|---|---|---|
| `CONVSYNC_ROOT` | `/data` | tree to process |
| `OCR_LANGS` | `ita+eng` | Tesseract languages, joined with `+` |

Language packs are chosen at build time: the published image carries English
and Italian. For other languages, build your own:

```bash
docker build --build-arg TESSERACT_LANGS="deu fra" -t convsync:custom .
docker run --rm -e OCR_LANGS=deu+fra+eng -v "$PWD/documents:/data" convsync:custom
```

## Comparison

Most converters are libraries that turn one file into Markdown, often with far
better layout reconstruction than this image. What they do not do is keep a
folder in sync, and the AI-based ones carry a runtime that rules out older
CPUs. The table reflects the state of each project at the time of writing:
check upstream before relying on it.

| Tool | Runs locally | OCR for scans | ML runtime | CPU without AVX2 | Folder sync | Formats |
|---|---|---|---|---|---|---|
| **ConvSync** | yes | yes, Tesseract, local | none | yes | **yes**: incremental, orphans, hand-edit guard | PDF, XLSX |
| [MarkItDown](https://github.com/microsoft/markitdown) | yes | via plugins or LLM | onnxruntime (`magika`, core dependency) | no, SIGILL | no | many |
| [Docling](https://github.com/docling-project/docling) | yes | yes | torch / onnxruntime | not guaranteed | no | many |
| [Marker](https://github.com/datalab-to/marker) | yes | yes | torch | not guaranteed | no | many |
| [MinerU](https://github.com/opendatalab/MinerU) | yes | yes | torch, VLM models | not guaranteed | no | many |
| [PyMuPDF4LLM](https://github.com/pymupdf/pymupdf4llm) | yes | yes, Tesseract | onnxruntime + numpy (PyMuPDF Layout, installed by default) | not guaranteed | no | PDF and MuPDF formats |
| [Anydoc](https://github.com/firecrawl/anydoc) | yes | **hosted only** (Firecrawl Parse) | none | likely, untested | no | Office, ODF, RTF, EPUB, CSV, PDF |
| [Pandoc](https://pandoc.org) | yes | no | none | yes | no | many, but **no PDF or XLSX input** |

When to pick something else:

- **Complex layouts** (multi-column papers, formulas, nested tables) on a
  modern CPU: Docling, Marker or MinerU reconstruct the reading order far
  better than `pdftotext`.
- **DOCX, PPTX, ODT, EPUB**: Anydoc or MarkItDown. This image does not convert
  them (yet).
- **One-off conversions**: any library above; the sync machinery here only pays
  off on a folder that keeps changing.

## Local build

The `build:` section of `docker-compose.yml` is active. `image` is both the
pull reference and the build tag, so set it in both commands: building with
`IMAGE` unset overwrites `frugan/convsync:latest` in the local cache.

```bash
cp .env.dist .env
IMAGE=convsync:local docker compose build
IMAGE=convsync:local docker compose run --rm convsync
```

The documents go in `./data`, which is gitignored. The end-to-end test needs
no documents of yours:

```bash
docker run --rm --network none --entrypoint /opt/convsync/tests/smoke.sh convsync:local
```

## Limitations

- Only PDF and XLSX are converted; other files are ignored.
- A PDF with a little text and many scanned pages (a typed cover on a scanned
  body) clears the 100-character threshold and is not OCRed.
- XLSX formulas never computed by a spreadsheet application (files written by
  scripts) have no cached value and come out empty.
- OCR quality is Tesseract's: fine on clean scans, poor on photos and
  handwriting.

## Contributing

For your contributions please use:

- [Conventional Commits](https://www.conventionalcommits.org)
- [Pull request workflow](https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project)

See [CONTRIBUTING](.github/CONTRIBUTING.md) for detailed guidelines.

## Sponsor

[<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" width="200" alt="Buy Me A Coffee">](https://buymeacoff.ee/frugan)

## License

(ɔ) Copyleft 2026 [Frugan](https://frugan.it).
[MIT](https://choosealicense.com/licenses/mit/), see the [LICENSE](LICENSE) file.

The bundled tools keep their own licenses: notably ocrmypdf (MPL-2.0),
Tesseract (Apache-2.0), Ghostscript (AGPL-3.0) and poppler (GPL).
