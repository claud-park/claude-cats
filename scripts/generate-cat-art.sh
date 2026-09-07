#!/bin/bash
# Design/cats/*.svg → Sources/ClaudeCats/CatArt.generated.swift 재생성 후 빌드.
#
# Design/cats/source/<포즈>-figma.svg 가 있으면 먼저 import 해서
# Design/cats/<포즈>.svg 를 다시 만든다(그래서 그 두 파일은 손으로 고치지 않는다).
set -euo pipefail

cd "$(dirname "$0")/.."

# 원본 그림의 털색 3종. Figma 파일의 색을 바꾸면 여기도 같이 바꾼다.
FUR="#7D6C62"
FUR_DARK="#66584F"
FUR_LIGHT="#A09084"

for POSE in sitting sleeping alert; do
  SRC="Design/cats/source/$POSE-figma.svg"
  if [ -f "$SRC" ]; then
    python3 scripts/import-cat-svg.py "$SRC" \
      --pose "$POSE" \
      --out "Design/cats/$POSE.svg" \
      --fur "$FUR" --fur-dark "$FUR_DARK" --fur-light "$FUR_LIGHT"
  fi
done

OUT="Sources/ClaudeCats/CatArt.generated.swift"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

INPUTS="Design/cats/sitting.svg Design/cats/sleeping.svg"
# alert.svg 는 아직 없을 수 있다. 없으면 생성기가 앉은 자세를 alert* 로 별칭 삼는다.
[ -f Design/cats/alert.svg ] && INPUTS="$INPUTS Design/cats/alert.svg"

# shellcheck disable=SC2086
python3 scripts/svg2swift.py $INPUTS > "$TMP"
mv "$TMP" "$OUT"
echo "생성: $OUT ($(wc -l < "$OUT" | tr -d ' ') 줄)"

swift build
