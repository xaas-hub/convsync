# Contributing to ConvSync

Thank you for your interest in contributing!

## Repository Structure

```text
├── Dockerfile                  # Image definition (Debian + Tesseract + ocrmypdf)
├── requirements.txt            # Pinned Python dependencies
├── docker-compose.yml          # Service definition for standalone use
├── bin/
│   └── convsync                # Entry point: sync | ocr | convert | <command>
├── src/
│   ├── ocr.sh                  # Adds a text layer to scanned PDFs, into _ocr/
│   └── convert.py              # PDF/XLSX to Markdown, into _md/
├── tests/
│   └── smoke.sh                # End-to-end check, fixtures generated on the fly
├── data/                       # Documents for standalone use (gitignored)
├── .github/workflows/
│   ├── ci.yml                  # Lint, build, smoke test, push
│   ├── release.yml             # Semantic release automation
│   ├── commitlint.yml          # Commit message linting on PRs
│   ├── labeler.yml             # Auto-label PRs
│   ├── auto-merge.yml          # Auto-merge Dependabot PRs
│   └── stale.yml               # Stale issue/PR housekeeping
├── ruff.toml                   # Python lint rules, shared by CI and MegaLinter
└── .releaserc.json             # Semantic release configuration
```

The image must not carry a machine learning runtime (numpy, onnxruntime,
torch): it is what keeps it usable on CPUs without AVX2. Please do not submit
changes that would add one, directly or through a dependency — `tests/smoke.sh`
rejects them anyway.

## How to Contribute

### Reporting Issues

When reporting:

- Specify which image tag you're using
- Include Docker version (`docker version`) and whether the daemon uses
  `userns-remap`
- Include the CPU model and flags if the problem is a crash
  (`grep -m1 'model name' /proc/cpuinfo`, `grep -m1 -o 'avx[^ ]*' /proc/cpuinfo`)
- Never attach the documents themselves: reproduce with a sample that holds no
  personal data

### Proposing Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test locally (see below)
5. Submit a pull request

## Testing Locally

### Build Test Image

```bash
IMAGE=convsync:local docker compose build
# or
docker build -t convsync:local .
```

### Test the Image

```bash
# Generated fixtures: born digital PDF, scan, spreadsheet
docker run --rm --network none --entrypoint /opt/convsync/tests/smoke.sh convsync:local

# Against your own documents in ./data
IMAGE=convsync:local docker compose run --rm convsync
```

### Lint

```bash
docker run --rm -i hadolint/hadolint < Dockerfile
shellcheck bin/convsync src/ocr.sh tests/smoke.sh
ruff check src
```

## Code Style

- Comments and any other text inside the code are in English
- Explain *why*, not *what*: the non-obvious constraints (the AVX2-free
  dependency set, pdftotext `-layout` for form-like PDFs, `--force-ocr` for
  tagged scans) are the ones worth documenting
- Originals are never modified: everything generated goes under `_md/` and
  `_ocr/`

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org). Allowed
types are the conventional ones plus `deps` (used by Dependabot):

```bash
feat: convert ODS spreadsheets
fix: keep the OCR copy when the source mtime goes backwards
docs(readme): document OCR_LANGS
deps: bump ocrmypdf to 17.11.0
chore: tidy up the compose file
```

Commit types drive the release: `feat` bumps the minor version, `fix`,
`perf`, `refactor`, `deps` and `docs(readme)` bump the patch version, and a
`BREAKING CHANGE` footer bumps the major version.

## Build Workflow

1. **On push to `main`** — lint, build, smoke test, push to Docker Hub as
   `latest` (amd64 and arm64), update the Docker Hub description
2. **On pull request** — lint, build and smoke test only, no push
3. **Monthly** (1st of the month, 04:00 UTC) — rebuild, to pick up the Debian
   security updates
4. **On release** — `release.yml` calls `ci.yml` to push the versioned tags
5. **Manual trigger** — "Actions" tab → "Run workflow"

## Questions?

- Open a [Discussion](https://github.com/xaas-hub/convsync/discussions)
- Check the [Documentation](https://github.com/xaas-hub/convsync)

## License

By contributing, you agree your contributions will be licensed under the MIT
License.
