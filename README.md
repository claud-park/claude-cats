# Claude Cats

실행 중인 Claude Code 세션을 바탕화면 위(아이콘 아래) 고양이로 보여주는 macOS 앱.
세션마다 고양이 한 마리, 서브에이전트마다 새끼 고양이 한 마리가 붙는다.
busy 세션은 앉은 자세(꼬리가 1초마다 흔들린다), idle 세션은 웅크려 자는 자세다.
[알림 연동](#알림-연동)을 켜면 사용자를 기다리는 세션은 세 번째 자세 + 노란 말풍선이 된다.

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
| `알림 연동` | Claude Code 훅 설치/해제 (아래 참고) |
| `로그인 시 시작` | 로그인 항목 등록/해제 |
| `종료` | 앱 종료 |

`디스플레이` 하위 메뉴는 `자동 (메인 디스플레이)` 와 지금 연결된 화면 이름들을 보여주고, 고른
항목에 체크가 붙는다(한 번에 한 화면). 선택은 화면 **이름**으로 `UserDefaults`
(`preferredDisplayName`) 에 저장한다 — 디스플레이 ID 는 재부팅·재연결마다 바뀌기 때문이다.
고른 모니터를 뽑으면 자동으로 메인 디스플레이에 그리고, 메뉴에는 `<이름> (연결 안 됨)` 항목이
체크된 채 남아 다시 꽂으면 그 화면으로 돌아간다. 하위 메뉴는 열 때마다 다시 만든다.

## 알림 연동

`~/.claude` 를 훑는 것만으로는 알 수 없는 두 가지가 있다 — **Claude 가 사용자를 기다리는 중인지**
(권한 요청·입력 대기)와 **서브에이전트가 정확히 몇 개 도는지**다. 둘 다 Claude Code 훅이
알려준다. 메뉴바의 `알림 연동` 을 켜면 앱이 훅을 깔고, 끄면 되돌린다.

켜면 이렇게 된다.

- 알림이 있는 세션은 **세 번째 자세(`alert`)** 로 바뀌고(자던 고양이도 깬다) 머리 위에 **노란
  말풍선**이 뜬다: `권한 요청: <무엇을 하려는지>` / `입력 기다리는 중` / `에이전트 입력 대기`.
  세션 제목 말풍선은 그동안 가려진다.
- 새끼 고양이를 훅이 센 값과 합친다. idle 세션이어도 백그라운드 에이전트가 돌면 새끼가 붙고,
  `SubagentStop` 을 받으면 파일 mtime 이 아무리 싱싱해도 사라진다. 새끼 id 는 훅 페이로드의
  `agent_transcript_path`(`agent-<id>.jsonl`)에서 뽑는다 — mtime 휴리스틱이 쓰는 id 와 같아야
  한 에이전트가 두 마리로 보이지 않는다. `agent_id` 는 경로가 없을 때의 대비책이다.

알림이 사라지는 경우는 다섯이다.

| 신호 | 왜 |
| --- | --- |
| `UserPromptSubmit` | 사용자가 답했다 |
| **transcript mtime 이 알림 시각 + 5초를 지나갔다** | 권한을 승인하면 Claude 가 도구를 돌리고 transcript 에 append 한다. 제일 정확한 신호이고, 제목 조회가 이미 `stat` 하고 있어서 공짜다. 5초 유예를 두는 이유는 아래 |
| idle → busy 전이 | 새 작업이 시작됐다 |
| 세션 소멸 | 고양이 자체가 사라진다 |
| 30분 TTL | 훅이 죽어 위 신호가 영영 안 올 때의 안전망 |

busy → idle 은 **지우지 않는다**. 권한 프롬프트가 떠 있는 동안 세션이 idle 로 넘어가는 건
정상이고, 그걸로 지우면 알림이 뜨자마자 사라진다. 서브에이전트가 입력을 기다리는
(`agent_needs_input`) 동안 본 대화가 끝나는 경우도 마찬가지다.

transcript 규칙에 5초 유예(`alertClearGrace`)를 두는 것도 같은 이유다 — 알림을 띄운 그 턴이
직후에 자기 기록을 한두 줄 마저 쓴다. 그걸 "사용자가 답했다"로 읽으면 알림이 뜨자마자
사라진다. 알림 시각은 폴링 틱이 아니라 **이벤트 파일의 mtime**(= 훅이 실제로 터진 때)이라,
폴링 간격이나 앱이 꺼져 있던 시간만큼 시계가 밀리지 않는다.

`SubagentStop` 을 놓쳤을 때(Claude 가 죽거나 훅이 실패하거나)를 대비해 훅이 센 서브에이전트에도
4시간 TTL 이 있다. 서브에이전트는 몇 시간씩 돌기도 해서 넉넉하게 잡았다.

### 무엇을 어디에 쓰나

| 경로 | 내용 |
| --- | --- |
| `~/Library/Application Support/ClaudeCats/claude-cats-hook.sh` | 훅 스크립트(755). stdin 을 파일 하나로 옮기고 끝난다 |
| `~/.claude/settings.json` | 위 스크립트를 `Notification` · `SubagentStart` · `SubagentStop` · `UserPromptSubmit` 네 이벤트에 등록 (`timeout: 5`) |
| `~/.claude/settings.json.claude-cats.bak` | 이 앱이 처음 쓰기 전 원본 백업(앱 실행당 한 번) |
| `~/.claude/claude-cats/events/` | 훅이 떨구는 이벤트 파일. 앱이 읽자마자 지운다 |

`Notification` 만 matcher 가 붙는다(`permission_prompt|idle_prompt|agent_needs_input`). 나머지
셋은 빈 matcher(=전부)다. 훅 스크립트는 파일 하나 쓰고 **항상 exit 0** 이라 Claude 를 막지
않는다. 임시 이름으로 받아 같은 디렉터리에서 rename 하므로 앱이 반쯤 쓰인 파일을 읽지 않는다.

앱이 꺼져 있으면 이벤트 파일을 아무도 치우지 않는다. 양쪽에서 막는다 — 훅은 파일이 5000개를
넘으면 쓰지 않고 나가고(세는 비용은 디렉터리 크기와 무관하다), 앱은 한 틱에 오래된 것부터
200개까지만 삼키고 나머지는 다음 틱으로 넘긴다.

이미 우리 스크립트가 **다른 matcher** 로 걸려 있으면 그 항목을 인정하고 새로 넣지 않는다.
같은 command 를 두 번 걸면 이벤트마다 파일이 두 개씩 생겨 손해가 더 크다. 기본 matcher 로
되돌리려면 껐다가 다시 켜면 된다.

### 끄기

메뉴에서 `알림 연동` 을 다시 누르면 된다 — `settings.json` 에서 **우리 command 를 가진 훅만**
빼고, 그 때문에 비게 된 항목·이벤트 키도 정리한다. 다른 훅과 한 그룹에 섞여 있으면 우리 훅만
빠지고 나머지는 그대로 남는다. 스크립트 파일과 이벤트 디렉터리는 지우지 않으므로, 지우고
싶으면 위 두 경로를 직접 지운다.

직접 손으로 되돌리려면 `settings.json` 의 네 이벤트에서 `claude-cats-hook.sh` 가 든 항목을
지우거나, 백업(`settings.json.claude-cats.bak`)을 되돌리면 된다.

### 서식 주의

앱은 `settings.json` 을 JSON 으로 읽고 다시 쓴다. **내용(의미)은 그대로지만 서식은 다시
짜진다** — 최상위 키가 알파벳 순으로 정렬되고, 들여쓰기는 2칸이 되며, 주석 없는 순수 JSON 이
된다(원래도 JSON 이므로 주석은 애초에 못 쓴다). 값·배열 순서·중첩 구조는 바뀌지 않는다.
설정 파일을 손으로 예쁘게 관리하고 있다면 이 점만 알고 켜면 된다. 파일이 JSON 으로 안 읽히면
앱은 **아무것도 고치지 않고** 경고창만 띄운다.

바뀔 게 없으면 아예 쓰지 않는다(이미 켜져 있는데 또 켜거나, 안 켜져 있는데 끄는 경우).
끄기인데 `settings.json` 이 없으면 만들지도 않는다.

`settings.json` 이 **심볼릭 링크**(dotfiles 저장소로 링크를 건 경우)여도 안전하다 — 링크를
따라간 실제 파일에 쓰므로 링크가 죽지 않는다. 아직 **대상이 없는 링크**면 대상을 만들어 준다
(필요하면 그 디렉터리까지).

쓰기는 임시 파일을 만들어 바꿔치기하는 방식(atomic)이다. 그래서 **파일 inode 가 새로 생긴다** —
POSIX 권한은 읽어 뒀다가 되돌리지만 **ACL·확장 속성(xattr)·하드 링크는 따라오지 않는다**.
`settings.json` 에 ACL 을 걸었거나 하드 링크로 공유하고 있다면 알림 연동을 켜기 전에 확인하자
(심볼릭 링크는 위처럼 안전하다).
백업(`settings.json.claude-cats.bak`)은 **그 자리가 비어 있을 때만** 만든다. 앱을 다시 켤
때마다 덮어쓰면 두 번째 실행에서 "이미 훅이 든 파일"이 백업 자리에 들어가 원본이 사라진다.

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

창은 `visibleFrame`(메뉴바·Dock 을 뺀 영역)이 아니라 `frame`(화면 전체)을 덮는다 — 바탕화면
레이어라 좌표계가 흔들리지 않는 편이 낫고, Dock 이 숨었다 나타날 때마다 창을 다시 잡지 않아도
된다. 대신 **배치**를 Dock 위로 올린다: `LayoutInsets.bottomInset(frame:visibleFrame:base:)`
이 `visibleFrame.minY − frame.minY`(하단 Dock 이 먹은 높이, 없으면 0)에 기본 여백
`SceneConfig.bottomInset`(40pt)을 더해 `Scene.layout` 에 넘긴다. Dock 이 좌·우에 있거나
자동 숨김이면 두 `minY` 가 같아 40pt 그대로다. Dock 크기·위치·자동 숨김을 바꾸면 macOS 가
`didChangeScreenParameters` 를 보내고, 거기서 `refitToScreen()` 이 여백을 다시 잰다.

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
3. 파일을 `Design/cats/source/sitting-figma.svg` / `sleeping-figma.svg` /
   `alert-figma.svg` 로 떨군다.
4. 아래를 돌린다.

```bash
scripts/generate-cat-art.sh                       # import + 생성 + swift build
python3 -m unittest scripts/test_import_cat_svg.py scripts/test_svg2swift.py
```

털색 세 가지(`FUR` / `FUR_DARK` / `FUR_LIGHT`)의 **정본은 `scripts/generate-cat-art.sh`**
맨 위에 있다. Figma 파일의 색을 바꾸면 거기만 고치면 된다.

`alert.svg` 는 아직 없어도 된다 — 그러면 생성기가 앉은 자세를 `CatArt.alert*` 이름으로 그대로
별칭 삼아, 런타임(`CatLayer`)이 참조하는 상수가 항상 존재한다.

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
| `Design/cats/alert.svg` | 사용자 입력을 기다릴 때 쓰는 세 번째 포즈(생성물). 꼬리 처리는 `sitting.svg` 와 같다 |

- `viewBox` 는 필수다. `viewBox="0 0 64 64"` 를 권한다. 다른 크기를 주면 64×64 상자에
  균일 비율로 맞춰 가운데 정렬한다(선 두께도 같이 스케일된다).
- 좌표계는 변환기가 AppKit 방향(y 위로)으로 뒤집어 준다. SVG 는 평소대로 y 아래로 그린다.
- 문서 순서가 그대로 그리는 순서다(뒤에 오는 것이 위에 덮인다).
- 꼬리도 **문서 순서를 따른다**. `tail-a` 가 몸통보다 뒤에 있으면 꼬리를 몸통 위에 얹고,
  앞에 있으면 뒤에 깐다. 변환기가 `CatArt.sittingTailAboveBody` 로 내보내고 런타임이
  꼬리 그릇 레이어 순서를 거기에 맞춘다.
- 말풍선 꼭지 높이도 그림에서 잰다 — 변환기가 `CatArt.sittingTop` / `sleepingTop` / `alertTop`
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
