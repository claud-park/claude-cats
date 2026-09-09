#!/bin/bash
# Design/cats/*.svg → Sources/ClaudeCats/CatArt*.generated.swift 재생성 후 빌드.
#
# 생성물은 포즈마다 한 파일 + 공용 타입 한 파일이다(포즈 하나만 고쳐도 그 파일만
# 다시 컴파일되게 — issue #4). 경로는 코드가 아니라 [명령코드, 좌표...] 데이터로 나간다.
#
# Design/cats/source/<포즈>-figma.svg 가 있으면 먼저 import 해서
# Design/cats/<포즈>.svg 를 다시 만든다(그래서 그 두 파일은 손으로 고치지 않는다).
set -euo pipefail

cd "$(dirname "$0")/.."

# 원본 그림의 털색 3종. Figma 파일의 색을 바꾸면 여기도 같이 바꾼다.
FUR="#7D6C62"
FUR_DARK="#66584F"
FUR_LIGHT="#A09084"

# 기본 고양이(team = 푹신캣). 팔레트로 색을 바꾸므로 털색 3종을 플레이스홀더로 치환한다.
for POSE in sitting sleeping alert; do
  SRC="Design/cats/source/$POSE-figma.svg"
  if [ -f "$SRC" ]; then
    python3 scripts/import-cat-svg.py "$SRC" \
      --pose "$POSE" \
      --out "Design/cats/$POSE.svg" \
      --fur "$FUR" --fur-dark "$FUR_DARK" --fur-light "$FUR_LIGHT"
  fi
done

# 켄지(kenji = 동글캣). 꼬리 프레임(tail-a/tail-b)도 alert 원본도 없다. 두 포즈 다 정적으로
# (꼬리를 몸통에 접어) import 한다 — sleeping 경로와 같다.
#
# 색: 동글캣도 푹신캣처럼 세션 팔레트로 색이 갈린다(recolorable). 몸통 주색과 그 음영만 치환한다.
#   #817671 (가장 큰 영역, 몸통 주색)     → #FUR
#   #746965 (더 어두운 털 음영·귀 접힘)   → #FURDARK
# FURDARK 를 함께 묶는 건 판단이다 — FUR 만 바꾸면 음영이 회갈색으로 남아 세션색과 안 어울린다.
# 몸통색이 움직일 때 음영도 같이 움직여야 코헤런트하다. "817671 하나만" 을 원하면 --fur-dark 를 빼면 된다.
# 나머지(#292827 눈·코 윤곽, #D6BCA1 코, #F1EAE3 얼굴 크림, white 수염·하이라이트)는 .fixed 로 둔다.
# FURLIGHT 에 해당하는 색은 원본에 없어 플래그를 주지 않는다.
for POSE in sitting sleeping; do
  SRC="Design/cats/source/kenji-$POSE-figma.svg"
  if [ -f "$SRC" ]; then
    python3 scripts/import-cat-svg.py "$SRC" \
      --pose sleeping \
      --out "Design/cats/kenji-$POSE.svg" \
      --fur "#817671" --fur-dark "#746965"
  fi
done

# 몽글개(monggle). 켄지와 같이 꼬리 프레임도 alert 원본도 없어 두 포즈 다 정적으로 import 한다.
#
# 색: 몽글개도 세션 팔레트로 색이 갈린다(recolorable). 가장 넓은 몸통색과 그 밝은 톤을 치환한다.
#   #847D7D (가장 큰 영역, 몸통 주색)  → #FUR
#   #9C9494 (더 밝은 털 톤)            → #FURLIGHT
# 나머지(#CAC2C0 밝은 회색, #E3C9AE 얼굴/발 크림, #3F322E 눈·코 진갈색)는 .fixed 로 둔다.
# FURDARK 에 해당하는 색은 원본에 없어 플래그를 주지 않는다.
for POSE in sitting sleeping; do
  SRC="Design/cats/source/monggle-$POSE-figma.svg"
  if [ -f "$SRC" ]; then
    python3 scripts/import-cat-svg.py "$SRC" \
      --pose sleeping \
      --out "Design/cats/monggle-$POSE.svg" \
      --fur "#847D7D" --fur-light "#9C9494"
  fi
done

OUT_DIR="Sources/ClaudeCats"

# 입력은 <컨셉:포즈=경로>. 컨셉·포즈마다 파일 하나가 나온다(CatArt.<컨셉>.<포즈>.generated.swift).
INPUTS="team:sitting=Design/cats/sitting.svg team:sleeping=Design/cats/sleeping.svg"
# alert.svg 는 아직 없을 수 있다. 없으면 CatArtSet 이 앉은 자세를 alert 로 폴백한다.
[ -f Design/cats/alert.svg ] && INPUTS="$INPUTS team:alert=Design/cats/alert.svg"
# 켄지는 원본이 있을 때만 넣는다(꼬리·alert 없음 → CatArtSet 이 빈 꼬리·sitting 폴백으로 채운다).
[ -f Design/cats/kenji-sitting.svg ] && INPUTS="$INPUTS kenji:sitting=Design/cats/kenji-sitting.svg"
[ -f Design/cats/kenji-sleeping.svg ] && INPUTS="$INPUTS kenji:sleeping=Design/cats/kenji-sleeping.svg"
# 몽글개도 원본이 있을 때만(꼬리·alert 없음 → CatArtSet 이 빈 꼬리·sitting 폴백으로 채운다).
[ -f Design/cats/monggle-sitting.svg ] && INPUTS="$INPUTS monggle:sitting=Design/cats/monggle-sitting.svg"
[ -f Design/cats/monggle-sleeping.svg ] && INPUTS="$INPUTS monggle:sleeping=Design/cats/monggle-sleeping.svg"

# 생성기가 파일을 직접 쓰고, 더는 안 쓰는 예전 생성물은 스스로 지운다.
# shellcheck disable=SC2086
python3 scripts/svg2swift.py --out-dir "$OUT_DIR" $INPUTS

swift build
