# AGENTS.md

Instructions for AI agents working on this repository. Everything a human
contributor needs is in [CONTRIBUTING](.github/CONTRIBUTING.md): read it, this
file does not repeat it.

## Hard rules

- **No machine learning runtime in the image.** numpy, onnxruntime, torch and
  magika must not be installed, directly or through a dependency: they bring
  back the AVX2 requirement this project exists to avoid. `tests/smoke.sh`
  fails the build if one appears.
- **Never read `data/`.** It holds the maintainer's documents (invoices, tax
  returns, contracts) and their conversions. Test against the fixtures that
  `tests/smoke.sh` generates, or add a generated one: the repository carries
  no binary test files.
- **Never read `.env`.** Only `.env.dist` is tracked.
- **Do not edit `CHANGELOG.md`.** semantic-release writes it from the commit
  log.
- Originals are never modified: everything generated goes under `_md/` and
  `_ocr/`.

## Commands

Everything runs in Docker. If you cannot run it, say which commands have to be
run and what output to look for.

```bash
IMAGE=convsync:local docker compose build
docker run --rm --network none --entrypoint /opt/convsync/tests/smoke.sh convsync:local
```

Lint as described in the header of `.megalinter.yml`, which mirrors `ci.yml`.

## Conventions

- Code, comments and commit messages in English. Comments explain why, not
  what.
- Conventional Commits, plus the `deps` type: the type decides the release
  (see CONTRIBUTING). Body lines up to 150 characters.
- Python follows `ruff.toml`; shell scripts must pass shellcheck and are
  indented with tabs, like the existing ones.
- A change to how documents are detected or converted comes with a generated
  fixture and an assertion in `tests/smoke.sh`.
- A new input format is a function plus an entry in `CONVERTERS` in
  `src/convert.py`. OCR is PDF-only: `src/ocr.sh` and `ocr_variant()` would
  need changing too. Update the tables in `README.md`.

## Private notes

`agents/` is gitignored. If your checkout has it, it holds the maintainer's
notes: read what is relevant to the task, never reference it from versioned
files.