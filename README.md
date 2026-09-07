# Claude Cats

실행 중인 Claude Code 세션을 바탕화면 위(아이콘 아래) 고양이로 보여주는 macOS 앱.
세션마다 고양이 한 마리, 서브에이전트마다 새끼 고양이 한 마리가 붙는다.
busy 세션은 앉은 자세(꼬리가 1초마다 흔들린다), idle 세션은 웅크려 자는 자세다.

<img width="455" height="148" alt="image" src="https://github.com/user-attachments/assets/17b9f98c-4ecb-4c4d-a30d-8c46edf44b02" />



```bash
swift build               # 빌드
.build/debug/ClaudeCats   # 실행 (창 없이 바탕화면에 그린다)
swift test                # 테스트

./scripts/bundle.sh       # release 빌드 + dist/ClaudeCats.app 생성
open dist/ClaudeCats.app  # 번들 실행 (메뉴바 앱, Dock 아이콘 없음)
```

## 메뉴바 항목

| 항목 | 하는 일 |
| --- | --- |
| `고양이 N마리 · 작업 중 N` | 읽기 전용 요약 |
| `일시정지` / `재개` | 폴링·그리기 정지 |
| `지금 새로고침` | 즉시 한 번 폴링 |
| `디스플레이` | 고양이를 그릴 화면 선택 |
| `로그인 시 시작` | 로그인 항목 등록/해제 |
| `종료` | 앱 종료 |

`디스플레이` 하위 메뉴는 `자동 (메인 디스플레이)` 와 지금 연결된 화면 이름들을 보여주고, 고른
항목에 체크가 붙는다(한 번에 한 화면). 선택은 화면 **이름**으로 `UserDefaults`
(`preferredDisplayName`) 에 저장한다 — 디스플레이 ID 는 재부팅·재연결마다 바뀌기 때문이다.
고른 모니터를 뽑으면 자동으로 메인 디스플레이에 그리고, 메뉴에는 `<이름> (연결 안 됨)` 항목이
체크된 채 남아 다시 꽂으면 그 화면으로 돌아간다. 하위 메뉴는 열 때마다 다시 만든다.

## 동작 원리

`~/.claude/sessions/*.json` 을 3초마다 stat 폴링(내용은 mtime 이 바뀐 파일만 파싱)해서 살아있는
interactive 세션마다 고양이 한 마리를 배치한다. busy 세션의
`~/.claude/projects/<cwd>/<sessionId>/subagents/*.jsonl` mtime 이 15초 이내면 새끼 고양이로
표시한다. 모든 세션(idle 포함)의 transcript 끝에서 최근 `ai-title` 을 읽어 고양이 위 말풍선으로도
보여준다. idle 세션은 transcript mtime 이 더 이상 바뀌지 않으므로 다시 읽지 않는다(매 틱 `stat` 만).
화면 잠금/슬립 시 정지, 배터리/저전력 시 10초 폴링 + 애니메이션 끔.

창은 선택한 디스플레이(기본값은 원점을 포함한 주 디스플레이 `NSScreen.screens.first`) 전체를
덮는다. `NSScreen.main` 은 키보드 포커스가 있는 화면이라 쓰지 않는다 — 포커스를 따라 고양이가
옮겨다닌다. 디스플레이 구성이 바뀌면(`didChangeScreenParameters`) 창을 다시 맞추고 배치를
새 화면 크기로 다시 계산한다.

## 직접 그린 SVG 넣는 법

파이프라인은 두 단계다.

```
Design/cats/source/<포즈>-figma.svg   ← Figma 에서 내보낸 원본(사람이 관리하는 유일한 그림)
  └ scripts/import-cat-svg.py         ← 껍데기 벗기기 · 64 상자 맞추기 · 털색 치환
Design/cats/<포즈>.svg                ← 생성물. 손으로 고치지 말 것
  └ scripts/svg2swift.py              ← CGPath 빌더로 변환
Sources/ClaudeCats/CatArt.generated.swift   ← 생성물. 커밋은 한다
```

런타임에 SVG 를 파싱하지 않으므로 그림을 바꾸면 스크립트를 다시 돌려야 한다.

### 권장 흐름 (Figma)

1. Figma 에서 고양이를 그린다. 꼬리는 **프레임 이름을 `tail-a`** 로 둔다. 흔드는 두 번째
   프레임을 직접 그렸다면 그 이름은 `tail-b` 다(`<path>` 든 `<g>` 든 상관없다).
2. Export SVG 에서 **"Include id attribute"** 를 켠다(이게 꺼져 있으면 꼬리를 못 찾는다).
3. 파일을 `Design/cats/source/sitting-figma.svg` / `sleeping-figma.svg` 로 떨군다.
4. 아래를 돌린다.

```bash
scripts/generate-cat-art.sh                       # import + 생성 + swift build
python3 -m unittest scripts/test_import_cat_svg.py scripts/test_svg2swift.py
```

털색 세 가지(`FUR` / `FUR_DARK` / `FUR_LIGHT`)의 **정본은 `scripts/generate-cat-art.sh`**
맨 위에 있다. Figma 파일의 색을 바꾸면 거기만 고치면 된다.

`generate-cat-art.sh` 는 `Design/cats/source/<포즈>-figma.svg` 가 있을 때만 import 를 돌린다.
원본 없이 `Design/cats/*.svg` 를 손으로 그려 쓰는 예전 방식도 되지만, 그때
`sitting.svg` 에는 `<g id="tail-a">` 와 `<g id="tail-b">` 가 **반드시** 있어야 한다 —
런타임(`CatLayer`)이 `CatArt.sittingTailA` / `sittingTailB` / `sittingTailAboveBody` 를
참조하므로, 없으면 생성된 Swift 가 컴파일되지 않는다.

### import-cat-svg.py 가 하는 일

| 단계 | 내용 |
| --- | --- |
| 껍데기 벗기기 | `<defs>`, viewBox 전체를 덮는 배경 `<rect>`, viewBox 전체를 덮는 `<clipPath>` 를 건 `<g>` 를 벗긴다. 그 밖의 클립·마스크·그라디언트·텍스트·이미지는 이름을 찍고 **중단**한다 |
| 꼬리 뽑기 | `tail-a` / `tail-b` id 를 가진 요소를 꼬리 프레임으로 뽑는다. id 가 없으면 `--tail-paths 12,13,14`(1-based path 순번). 둘 다 없으면 중단 |
| 두 번째 프레임 | 원본에 `tail-b` 가 있으면 **그대로 쓴다**. `tail-a` 만 있으면 꼬리 밑동(bbox 의 minX·maxY)을 축으로 `--tail-angle`(기본 −8°) 만큼 돌린 프레임을 만든다 |
| 상자 맞추기 | 그림 전체 bbox 를 64×64 상자에 균일 스케일로 맞춘다. `scale = (64 − 2·pad) / max(폭, 높이)`, 가로는 가운데, 세로는 **바닥 정렬**(고양이가 바닥에 선다). `--pad` 기본 2 |
| 색 치환 | `--fur` / `--fur-dark` / `--fur-light` 로 준 색을 `#FUR` / `#FURDARK` / `#FURLIGHT` 로 바꾼다(대소문자·3자리 축약 무시) |
| stroke 정리 | 아래 표 참고 |

자는 자세는 런타임에 꼬리 토글이 없다. 그래서 `tail-a` 는 문서 순서 그대로 몸통에 접고
`tail-b` 는 버린다(있어도 에러는 아니고 그냥 쓰이지 않는다).

#### stroke 정리 규칙

Figma 는 한 도형의 fill 과 stroke 를 **자리가 같은 `<path>` 두 벌**로 내보낸다
(fill 조각 여러 개 + stroke 하나인 경우도 있다). 그래서 stroke 는 세 갈래로 나눈다.

| 경우 | 처리 |
| --- | --- |
| 한 `<path>` 에 같은 색 `fill` 과 `stroke` 가 같이 있다 | stroke 를 버린다 |
| stroke 만 있는데 같은 색 fill 도형과 자리(bbox)가 같다 | 이미 칠해져 있으니 그 도형을 통째로 버린다 |
| stroke 만 있는데 **다른 색** 도형과 자리가 같다 (눈 테두리 등) | 선으로 남긴다 |
| 남은 stroke 전부 (외곽선 · 수염 · 입 · 바닥선) | 축소 후 두께가 최소 0.6pt 가 되게 키운다 — 안 그러면 64pt 상자에서 사라진다 |

"자리가 같다"는 판정은 bbox 가 **도형 크기의 25%(최대 0.5) 안에서** 일치하고 path 명령
개수도 비슷할 때만 한다(작은 도형은 개수가 정확히 같아야 한다). 그래도 미심쩍으면
`--keep-stroke-twins` 로 이 정리를 통째로 끄고 비교해 보면 된다. 버린 stroke 는 하나씩
stderr 에 찍는다(`path 번호`, 색, bbox, `d` 앞 40자).

### 파일 규약

| 파일 | 쓰임 |
| --- | --- |
| `Design/cats/source/*-figma.svg` | 원본. 여기만 사람이 고친다 |
| `Design/cats/sitting.svg` | busy 포즈(생성물). `<g id="tail-a">`, `<g id="tail-b">` 는 1초마다 번갈아 보이는 꼬리 두 프레임, 그 외 전부 몸통 |
| `Design/cats/sleeping.svg` | idle 포즈(생성물). 꼬리를 포함해 전부 몸통(정지 그림) |

- `viewBox` 는 필수다. `viewBox="0 0 64 64"` 를 권한다. 다른 크기를 주면 64×64 상자에
  균일 비율로 맞춰 가운데 정렬한다(선 두께도 같이 스케일된다).
- 좌표계는 변환기가 AppKit 방향(y 위로)으로 뒤집어 준다. SVG 는 평소대로 y 아래로 그린다.
- 문서 순서가 그대로 그리는 순서다(뒤에 오는 것이 위에 덮인다).
- 꼬리도 **문서 순서를 따른다**. `tail-a` 가 몸통보다 뒤에 있으면 꼬리를 몸통 위에 얹고,
  앞에 있으면 뒤에 깐다. 변환기가 `CatArt.sittingTailAboveBody` 로 내보내고 런타임이
  꼬리 그릇 레이어 순서를 거기에 맞춘다.
- 말풍선 꼭지 높이도 그림에서 잰다 — 변환기가 `CatArt.sittingTop` / `sleepingTop`
  (그림 꼭대기 y)을 내보내고, 런타임은 그 2pt 위에 꼭지를 둔다.

### 색

| 값 | 뜻 |
| --- | --- |
| `#FUR` | 세션마다 다른 털색. 런타임 팔레트(`CatShapes.palette`) 에서 받는다 |
| `#FURDARK` | 같은 팔레트의 어두운 털색(귀 안쪽·목덜미 그림자 등) |
| `#FURLIGHT` | 같은 팔레트의 밝은 털색(하이라이트) |
| `#rgb` `#rgba` `#rrggbb` `#rrggbbaa`, 기본 색 이름 | 고정색. 흰 패치·눈·코·수염처럼 털색과 무관한 부분에 쓴다 |
| `none` | 칠하지 않음 |

`#FUR` 이 **주 털색**이고 나머지 둘은 거기서 파생된 톤이다 — `#FURDARK`(약 15% 어둡게)와
`#FURLIGHT`(흰색 쪽으로 약 27%)는 **선택 사항**이다. 안 써도 되고, 쓰면 팔레트를 바꿔도
명도 관계가 그대로 유지된다(`CatShapes.palette` 의 8쌍이 모두 이 관계로 만들어져 있다).
지금 원본 기준으로 `#FURLIGHT` 는 앉은 자세에서 한 군데 쓰이고, **`#FURDARK` 는 두 포즈
어디에도 쓰이지 않는다**(사용자가 마지막 내보내기에서 뺐다). 팔레트는 세 색을 다 지원하므로
다음 내보내기에서 다시 쓰면 그대로 살아난다. 세 색의 실제 값은
`scripts/generate-cat-art.sh` 에 있다.

털색은 팔레트를 갈아끼워도 경로를 다시 만들지 않고 색만 바꾼다. 그래서 `#FUR` 을 쓴
도형에는 `fill-opacity` / `stroke-opacity` 대신 `opacity` 를 쓰는 편이 결과가 깔끔하다.

### 지원 범위

- 요소: `g`(중첩 가능), `path`, `ellipse`, `circle`, `rect`, `line`, `polygon`, `polyline`
- 속성: `fill`, `fill-rule`(`nonzero` / `evenodd`), `stroke`, `stroke-width`,
  `stroke-linecap`, `stroke-linejoin`(기본 `round`), `opacity`, `fill-opacity`,
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

털색 8쌍(`fur` / `furDark` / `furLight`)은 `Sources/ClaudeCats/CatShapes.swift` 의
`palette` 에 있다. 0번이 원본 그림의 색이고 나머지 7쌍은 같은 명도 관계로 만들었다.
세션 이름 해시로 `paletteIndex % 8` 을 고르므로 쌍 개수를 바꾸면 `SceneConfig.paletteSize`
도 같이 맞춘다.
