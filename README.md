# Claude Cats

실행 중인 Claude Code 세션을 바탕화면 위(아이콘 아래) 고양이로 보여주는 macOS 앱.
세션마다 고양이 한 마리, 서브에이전트마다 새끼 고양이 한 마리가 붙는다.
busy 세션은 앉은 자세(꼬리가 1초마다 흔들린다), idle 세션은 웅크려 자는 자세다.

```bash
swift build               # 빌드
.build/debug/ClaudeCats   # 실행 (창 없이 바탕화면에 그린다)
swift test                # 테스트

./scripts/bundle.sh       # release 빌드 + dist/ClaudeCats.app 생성
open dist/ClaudeCats.app  # 번들 실행 (메뉴바 앱, Dock 아이콘 없음)
```

## 동작 원리

`~/.claude/sessions/*.json` 을 3초마다 stat 폴링(내용은 mtime 이 바뀐 파일만 파싱)해서 살아있는
interactive 세션마다 고양이 한 마리를 배치한다. busy 세션의
`~/.claude/projects/<cwd>/<sessionId>/subagents/*.jsonl` mtime 이 15초 이내면 새끼 고양이로
표시한다. 모든 세션(idle 포함)의 transcript 끝에서 최근 `ai-title` 을 읽어 고양이 위 말풍선으로도
보여준다. idle 세션은 transcript mtime 이 더 이상 바뀌지 않으므로 다시 읽지 않는다(매 틱 `stat` 만).
화면 잠금/슬립 시 정지, 배터리/저전력 시 10초 폴링 + 애니메이션 끔.

## 직접 그린 SVG 넣는 법

고양이 그림은 `Design/cats/*.svg` 하나가 원본이고, `scripts/svg2swift.py` 가 이걸
`Sources/ClaudeCats/CatArt.generated.swift`(CGPath 빌더) 로 바꾼다. 런타임에 SVG 를
파싱하지 않으므로 그림을 바꾸려면 스크립트를 다시 돌려야 한다.

```bash
# Design/cats/sitting.svg, sleeping.svg 를 고친 뒤
scripts/generate-cat-art.sh    # 생성 + swift build
python3 -m unittest scripts/test_svg2swift.py   # 변환기 회귀 테스트
```

생성된 `CatArt.generated.swift` 는 커밋한다(손으로 고치지 말 것).

### 파일 규약

| 파일 | 쓰임 |
| --- | --- |
| `Design/cats/sitting.svg` | busy 포즈. `<g id="tail-a">`, `<g id="tail-b">` 는 1초마다 번갈아 보이는 꼬리 두 프레임, 그 외 전부 몸통 |
| `Design/cats/sleeping.svg` | idle 포즈. 꼬리를 포함해 전부 몸통(정지 그림) |

- `viewBox` 는 필수다. `viewBox="0 0 64 64"` 를 권한다. 다른 크기를 주면 64×64 상자에
  균일 비율로 맞춰 가운데 정렬한다(선 두께도 같이 스케일된다).
- 좌표계는 변환기가 AppKit 방향(y 위로)으로 뒤집어 준다. SVG 는 평소대로 y 아래로 그린다.
- 문서 순서가 그대로 그리는 순서다(뒤에 오는 것이 위에 덮인다).
- 단, 꼬리(`tail-a` / `tail-b`)는 문서 순서와 상관없이 **항상 몸통 뒤에** 깔린다.
  런타임이 꼬리 그릇 레이어를 몸통 아래에 넣기 때문이다.

### 색

| 값 | 뜻 |
| --- | --- |
| `#FUR` | 세션마다 다른 털색. 런타임 팔레트(`CatShapes.palette`) 에서 받는다 |
| `#FURDARK` | 같은 팔레트의 어두운 털색(꼬리 끝 그림자 등) |
| `#rgb` `#rgba` `#rrggbb` `#rrggbbaa`, 기본 색 이름 | 고정색. 흰 패치·눈·코·수염처럼 털색과 무관한 부분에 쓴다 |
| `none` | 칠하지 않음 |

털색은 팔레트를 갈아끼워도 경로를 다시 만들지 않고 색만 바꾼다. 그래서 `#FUR` 을 쓴
도형에는 `fill-opacity` / `stroke-opacity` 대신 `opacity` 를 쓰는 편이 결과가 깔끔하다.

### 지원 범위

- 요소: `g`(중첩 가능), `path`, `ellipse`, `circle`, `rect`, `line`, `polygon`, `polyline`
- 속성: `fill`, `stroke`, `stroke-width`, `stroke-linecap`, `opacity`, `fill-opacity`,
  `stroke-opacity`, `transform`(`translate` / `scale` / `rotate` / `matrix` / `skewX` / `skewY`,
  그룹에서 상속·합성), 인라인 `style="fill:...;stroke:..."`
- `path` 의 `d`: `M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z` 전부. 호(`A`)는 90° 이하 조각의
  3차 베지어로 근사한다.
- 숫자 값은 사용자 단위와 `px` 만 받는다(`em`·`pt` 등은 에러). `opacity`·`fill-opacity`·
  `stroke-opacity` 는 `0.5` 와 `50%` 둘 다 된다.
- 그라디언트·필터·텍스트·이미지·`use` 등은 변환할 수 없다. `clip-path` / `mask` / `filter`
  **속성**(인라인 `style` 포함)도 마찬가지다 — 조용히 무시하면 그림이 달라지므로 요소 이름과
  속성 이름을 찍고 중단한다. Figma·Illustrator 에서 내보낼 때 "윤곽선으로 만들기 / flatten"
  을 먼저 하면 된다.

인접한 도형이 같은 스타일(fill·stroke·선 두께·캡·불투명도)이면 한 레이어로 합쳐 레이어 수를 줄인다.
합친 결과는 `CAShapeLayer` 기본 채우기 규칙인 **nonZero** 로 칠해지므로, 같은 스타일의 도형 안에
반대 방향으로 감긴 도형을 겹쳐 두면 원본 SVG 에서는 둘로 보이던 것이 구멍으로 뚫려 보인다.
구멍을 의도했다면 그대로 두고, 아니라면 두 도형의 스타일을 다르게 하거나 사이에 다른 스타일의
도형을 끼워 병합을 끊는다.

### 팔레트 바꾸기

털색 8쌍은 `Sources/ClaudeCats/CatShapes.swift` 의 `palette` 에 있다. 세션 이름 해시로
`paletteIndex % 8` 을 고르므로 쌍 개수를 바꾸면 `SceneConfig.paletteSize` 도 같이 맞춘다.
