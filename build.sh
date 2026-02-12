#!/usr/bin/env bash
# build.sh - Markdown to PDF build script (Linux/Docker用)
# 使用方法: ./build.sh sample_paper.md

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.md>" >&2
    exit 1
fi

INPUT_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="${INPUT_FILE%.md}.pdf"

echo "Building: $(basename "$INPUT_FILE") -> $(basename "$OUTPUT_FILE")"

# Detect mmdc (mermaid-cli)
MMDC_FILTER_ARGS=()
if command -v mmdc &>/dev/null || [ -n "${MERMAID_MMDC:-}" ]; then
    MMDC_FILTER_ARGS=("--lua-filter=${SCRIPT_DIR}/pandoc/mermaid.lua")
else
    echo "Warning: mmdc not found. Mermaid diagrams will not be rendered."
fi

# Run pandoc
echo "Running pandoc..."
pandoc "$INPUT_FILE" \
    -f markdown-smart \
    -o "$OUTPUT_FILE" \
    --pdf-engine=xelatex \
    "${MMDC_FILTER_ARGS[@]}" \
    --lua-filter="${SCRIPT_DIR}/pandoc/paper-filter.lua" \
    --filter=pandoc-crossref \
    --citeproc \
    --bibliography="${SCRIPT_DIR}/references.bib" \
    --csl="${SCRIPT_DIR}/japanese-reference.csl" \
    --lua-filter="${SCRIPT_DIR}/pandoc/cite-superscript.lua" \
    --number-sections \
    -V mainfont="Harano Aji Mincho" \
    -V geometry:top=30mm,bottom=30mm,left=20mm,right=20mm \
    --include-in-header="${SCRIPT_DIR}/pandoc/header.tex"

echo "Build successful: $OUTPUT_FILE"
