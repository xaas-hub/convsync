# syntax=docker/dockerfile:1

# Mirrors a tree of PDF and XLSX documents into Markdown, OCRing the scanned
# PDFs locally, for LLM agents and RAG tooling to read.
#
# The image deliberately carries NO machine learning runtime (numpy, onnxruntime,
# torch): that is what keeps it free of the AVX2 requirement that makes
# markitdown, docling and friends abort with SIGILL on older x86-64 CPUs, and
# what keeps it small. Tesseract selects its SIMD path at runtime and falls back
# to SSE on CPUs without AVX2. tests/smoke.sh fails the build if one sneaks in.

FROM debian:trixie-slim

# Tesseract language packs, space separated (Debian names without the
# tesseract-ocr- prefix). English comes with tesseract-ocr itself.
ARG TESSERACT_LANGS="ita"

ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/xaas-hub/convsync" \
      org.opencontainers.image.title="convsync" \
      org.opencontainers.image.description="Incremental PDF/XLSX to Markdown sync with local OCR, no ML runtime, no AVX2" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/venv/bin:/opt/convsync/bin:${PATH} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CONVSYNC_ROOT=/data \
    OCR_LANGS=ita+eng \
    # Any uid may run the image (see DOCKER_USER in docker-compose.yml): give
    # it a writable home for the caches ocrmypdf and its libraries look for.
    HOME=/tmp

# ghostscript, unpaper and tesseract are ocrmypdf runtime dependencies;
# poppler-utils provides pdftotext for both scripts.
# hadolint ignore=DL3008,SC2046
RUN apt-get update && apt-get install -y --no-install-recommends \
        ghostscript \
        poppler-utils \
        python3 \
        python3-venv \
        tesseract-ocr \
        unpaper \
        $(printf 'tesseract-ocr-%s ' ${TESSERACT_LANGS}) \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

# --only-binary: a dependency without a wheel for this platform fails the build
# instead of compiling from source with whatever the toolchain defaults to.
RUN python3 -m venv /opt/venv \
    && pip install --no-cache-dir --only-binary=:all: -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY src/ /opt/convsync/
COPY bin/ /opt/convsync/bin/
COPY tests/ /opt/convsync/tests/

WORKDIR /data

ENTRYPOINT ["convsync"]
CMD ["sync"]
