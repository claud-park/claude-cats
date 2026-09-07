#!/bin/bash
# Design/cats/*.svg → Sources/ClaudeCats/CatArt.generated.swift 재생성 후 빌드.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="Sources/ClaudeCats/CatArt.generated.swift"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

python3 scripts/svg2swift.py Design/cats/sitting.svg Design/cats/sleeping.svg > "$TMP"
mv "$TMP" "$OUT"
echo "생성: $OUT ($(wc -l < "$OUT" | tr -d ' ') 줄)"

swift build
