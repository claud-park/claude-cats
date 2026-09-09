#!/usr/bin/env python3
"""Figma 로 내보낸 고양이 SVG → `Design/cats/<포즈>.svg` (svg2swift 입력 규약).

표준 라이브러리만 쓴다. 사용법:

    python3 scripts/import-cat-svg.py Design/cats/source/sitting-figma.svg \\
        --pose sitting --out Design/cats/sitting.svg \\
        --fur '#7D6C62' --fur-dark '#66584F' --fur-light '#A09084'

하는 일:
  - Figma 가 붙이는 껍데기(전체 프레임 `<clipPath>`, 배경 `<rect>`, `<defs>`)를 벗긴다.
  - `<g id="tail-a">` / `<g id="tail-b">`(또는 같은 id 의 `<path>`)를 꼬리 프레임으로 뽑는다.
    id 가 없으면 `--tail-paths 12,13,14` 처럼 1-based path 순번으로 지정할 수 있고,
    `tail-b` 가 없으면 `tail-a` 를 살짝 회전시켜 두 번째 프레임을 만든다.
  - 그림 bbox 를 64×64 상자에 균일 스케일로 맞춘다(가로 가운데, 바닥 정렬).
  - 털색 세 가지를 `#FUR` / `#FURDARK` / `#FURLIGHT` 플레이스홀더로 바꾼다.
  - Figma 가 fill 과 stroke 를 쪼개 놓은 stroke 쌍을 정리하고, 남은 선은 축소 후에도
    보이도록 최소 두께를 준다. 버린 stroke 는 stderr 에 하나씩 찍는다.
    의심스러우면 `--keep-stroke-twins` 로 이 정리를 끄고 비교하면 된다.
"""

import argparse
import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import svg2swift as S  # noqa: E402

BOX = S.BOX
# 홀로 선 그림(수염·입·바닥선)은 이만큼은 돼야 64pt 상자에서 읽힌다.
MIN_SCALED_STROKE = 0.6
# 이미 칠해진 도형 위에 얹힌 외곽선은 더 얇아도 된다 — 다만 완전히 사라지면 안 되므로
# 2x 화면에서 0.5px 인 0.25pt 를 바닥으로 둔다. 775 프레임 원본의 0.25(→0.02pt)를 살리고,
# 64 프레임 원본(scale≈1)에서는 작가가 정한 0.25 를 그대로 통과시킨다.
MIN_SCALED_OUTLINE = 0.25
# fit 변환의 scale 을 2자리로 반올림하면 바닥 정렬이 어긋난다. 임포터는 4자리를 쓴다.
PLACES = 4


def num(value):
    return S.num(value, PLACES)

# 그대로 실어 나르는 표현 속성(상속된다). transform·불투명도는 따로 처리한다.
STYLE_KEYS = (
    "fill", "fill-rule", "fill-opacity",
    "stroke", "stroke-width", "stroke-linejoin", "stroke-linecap", "stroke-opacity",
)
# 도형별 기하 속성. 출력할 때 스타일보다 앞에 둔다.
GEOMETRY_KEYS = (
    "d", "points", "cx", "cy", "r", "rx", "ry", "x", "y", "width", "height",
    "x1", "y1", "x2", "y2",
)
CONTAINER_TAGS = {"g", "a"}
SKIPPED_TAGS = {"title", "desc", "metadata"}


def fail(message):
    raise SystemExit("import-cat-svg: " + message)


# ---------------------------------------------------------------- 색


def normal_color(text):
    """비교용 정규화. '#FFF'/'#ffffff'/'white' → '#ffffff', 'none' → None."""
    if text is None:
        return None
    value = text.strip().lower()
    if value in ("", "none", "transparent"):
        return None
    if value in S.NAMED_COLORS:
        value = S.NAMED_COLORS[value]
    if not value.startswith("#"):
        return value
    digits = value[1:]
    if len(digits) in (3, 4):
        digits = "".join(c * 2 for c in digits)
    return "#" + digits


# ---------------------------------------------------------------- 도형 기록


class Shape:
    """출력할 도형 하나. attrs 는 상속을 다 접은 결과다."""

    def __init__(self, tag, attrs, matrix, index, element):
        self.tag = tag
        self.attrs = attrs
        self.matrix = matrix
        self.index = index
        self.element = element
        self.bucket = "body"
        # 'same'   = 앞선 fill 도형의 stroke 쌍(Figma 가 쪼개 놓은 것) → stroke 를 버린다
        # 'outline'= 같은 자리 다른 색 도형의 외곽선 → 두께는 그대로 두되 최소 두께는 건다
        self.twin = None
        self.twin_of = []
        self._cmds = None

    def label(self):
        return "path %s" % self.index if self.index is not None else "<%s>" % self.tag

    def cmds(self):
        """원본 좌표계 기준 절대 명령 리스트(자기 transform 까지 적용)."""
        if self._cmds is None:
            self._cmds = S.transform_commands(S.shape_commands(self.element), self.matrix)
        return self._cmds

    def bounds(self):
        return S.commands_bounds(self.cmds())


def parse_style_declarations(element):
    return S.parse_style(element.get("style"))


def resolve_style(element, inherited):
    """부모에게서 받은 표현 속성에 이 요소의 속성·인라인 style 을 덮어쓴다."""
    style = dict(inherited)
    declarations = parse_style_declarations(element)
    for key in STYLE_KEYS:
        value = declarations.get(key, element.get(key))
        if value is not None and value.strip() != "":
            style[key] = value.strip()
    own = declarations.get("opacity", element.get("opacity"))
    if own is not None and own.strip() != "":
        alpha = S.parse_scalar(own, "opacity", allow_percent=True)
        style["_opacity"] = float(inherited.get("_opacity", 1.0)) * max(0.0, min(1.0, alpha))
    return style


def check_paint(style):
    for key in ("fill", "stroke"):
        value = (style.get(key) or "").strip().lower()
        if value.startswith("url("):
            fail("%s=%r 는 변환할 수 없다 (그라디언트·패턴은 내보내기 전에 flatten 해야 한다)."
                 % (key, style.get(key)))


class Importer:
    def __init__(self, root, view_box):
        self.min_x, self.min_y, self.width, self.height = view_box
        self.clip_paths = {}
        self.shapes = []
        self.path_count = 0
        self._collect_defs(root)

    # ------------------------------------------------------------ defs

    def _collect_defs(self, element):
        for child in element.iter():
            if S.local_name(child.tag) == "clipPath":
                ident = (child.get("id") or "").strip()
                if ident:
                    self.clip_paths[ident] = child

    def _covers_view_box(self, rect, matrix):
        if S.local_name(rect.tag) != "rect":
            return False
        matrix = S.mat_mul(matrix, S.parse_transform(rect.get("transform")))
        x = S.number_attr(rect, "x", 0.0)
        y = S.number_attr(rect, "y", 0.0)
        w = S.number_attr(rect, "width", 0.0)
        h = S.number_attr(rect, "height", 0.0)
        x0, y0 = S.mat_apply(matrix, x, y)
        x1, y1 = S.mat_apply(matrix, x + w, y + h)
        eps = 1e-6
        return (x0 <= self.min_x + eps and y0 <= self.min_y + eps
                and x1 >= self.min_x + self.width - eps
                and y1 >= self.min_y + self.height - eps)

    def check_clip(self, element, name, matrix):
        """clip-path 는 그 요소의 (transform 이 적용된) 사용자 좌표계에서 해석된다."""
        raw = (element.get("clip-path")
               or parse_style_declarations(element).get("clip-path") or "").strip()
        if not raw or raw.lower() == "none":
            return
        if not (raw.lower().startswith("url(#") and raw.endswith(")")):
            fail("<%s> 의 clip-path=%r 는 변환할 수 없다 (url(#id) 형태만 본다)." % (name, raw))
        ident = raw[len("url(#"):-1].strip()
        clip = self.clip_paths.get(ident)
        if clip is None:
            fail("<%s> 가 참조하는 clipPath #%s 를 찾을 수 없다." % (name, ident))
        children = [c for c in clip if S.local_name(c.tag) not in SKIPPED_TAGS]
        if len(children) != 1 or not self._covers_view_box(children[0], matrix):
            fail("<%s> 의 clip-path #%s 는 viewBox 전체를 덮는 <rect> 가 아니라 변환할 수 없다. "
                 "내보내기 전에 flatten 해야 한다." % (name, ident))
        # 전체 프레임 클립은 아무것도 자르지 않는다 — 그냥 벗긴다.

    # ------------------------------------------------------------ 순회

    def walk(self, element, style, matrix, bucket):
        for child in element:
            name = S.local_name(child.tag)
            if name in SKIPPED_TAGS or name == "defs":
                continue
            if name in ("linearGradient", "radialGradient", "pattern", "filter",
                        "mask", "image", "text", "tspan", "use", "symbol", "style",
                        "foreignObject", "switch", "marker"):
                fail("<%s> 는 변환할 수 없다 (그라디언트·마스크·이미지·텍스트·use 는 "
                     "내보내기 전에 flatten 하거나 지워야 한다)." % name)
            for attribute in ("mask", "filter"):
                value = (child.get(attribute)
                         or parse_style_declarations(child).get(attribute) or "").strip()
                if value and value.lower() != "none":
                    fail("<%s> 의 %s=%r 는 변환할 수 없다." % (name, attribute, value))
            child_matrix = S.mat_mul(matrix, S.parse_transform(child.get("transform")))
            self.check_clip(child, name, child_matrix)
            child_style = resolve_style(child, style)
            check_paint(child_style)
            ident = (child.get("id") or "").strip().lower()
            child_bucket = ident if ident in ("tail-a", "tail-b") else bucket

            if name in CONTAINER_TAGS or name == "svg":
                self.walk(child, child_style, child_matrix, child_bucket)
            elif name in S.SHAPE_TAGS:
                if name == "path":
                    self.path_count += 1
                if name == "rect" and self._covers_view_box(child, child_matrix):
                    continue           # Figma 가 깔아 주는 배경. 버린다.
                shape = Shape(name, dict(child_style), child_matrix,
                              self.path_count if name == "path" else None, child)
                shape.bucket = child_bucket
                self.shapes.append(shape)
            else:
                fail("<%s> 는 변환할 수 없다." % name)


# ---------------------------------------------------------------- 출력


def shape_attributes(shape, fit_scale, colors):
    """도형 하나의 출력 속성(순서 고정). 색 치환·stroke 정리까지 여기서 한다."""
    out = []
    for key in GEOMETRY_KEYS:
        value = shape.element.get(key)
        if value is not None and value.strip() != "":
            out.append((key, value.strip()))

    style = shape.attrs
    fill = normal_color(style.get("fill", "#000000"))
    stroke = normal_color(style.get("stroke"))
    keep_stroke = stroke is not None and stroke != fill and shape.twin != "same"

    def paint(value):
        key = normal_color(value)
        return colors.get(key, value) if key else "none"

    if "fill" in style or fill is not None:
        out.append(("fill", paint(style.get("fill", "#000000"))))
    if style.get("fill-rule"):
        out.append(("fill-rule", style["fill-rule"]))
    if style.get("fill-opacity"):
        out.append(("fill-opacity", style["fill-opacity"]))

    if keep_stroke:
        out.append(("stroke", paint(style.get("stroke"))))
        raw = style.get("stroke-width")
        width = 1.0 if raw is None else S.parse_scalar(raw, "stroke-width")
        own = S.mat_scale_factor(shape.matrix) * fit_scale
        if fill is None and own > 0:
            # 선이 축소 후 사라지지 않게 **렌더링 두께** 기준으로 최소치를 준다.
            # 다른 도형의 외곽선에도 (더 낮은) 바닥을 건다 — 775 프레임에서 내보낸
            # 0.25 는 축소하면 0.02pt 라 안 걸면 사라진다.
            floor = MIN_SCALED_OUTLINE if shape.twin == "outline" else MIN_SCALED_STROKE
            width = max(width, floor / own)
        out.append(("stroke-width", num(width)))
        for key in ("stroke-linejoin", "stroke-linecap", "stroke-opacity"):
            if style.get(key):
                out.append((key, style[key]))

    opacity = float(style.get("_opacity", 1.0))
    if abs(opacity - 1.0) > 1e-9:
        out.append(("opacity", num(opacity)))

    if shape.matrix != S.IDENTITY:
        out.append(("transform", "matrix(%s)" % " ".join(num(v) for v in shape.matrix)))
    return out


def shape_xml(shape, fit_scale, colors, indent):
    attrs = shape_attributes(shape, fit_scale, colors)
    text = " ".join('%s="%s"' % (key, value) for key, value in attrs)
    return "%s<%s %s/>" % (" " * indent, shape.tag, text)


def group_xml(ident, shapes, fit, fit_scale, colors, inner_transform=None):
    lines = ['  <g id="%s">' % ident, '    <g transform="%s">' % fit]
    indent = 6
    if inner_transform:
        lines.append('      <g transform="%s">' % inner_transform)
        indent = 8
    for shape in shapes:
        lines.append(shape_xml(shape, fit_scale, colors, indent))
    if inner_transform:
        lines.append("      </g>")
    lines.append("    </g>")
    lines.append("  </g>")
    return "\n".join(lines)


# ---------------------------------------------------------------- 메인


def bounds_of(shapes, matrix=None):
    box = None
    for shape in shapes:
        cmds = shape.cmds()
        if matrix is not None:
            cmds = S.transform_commands(cmds, matrix)
        one = S.commands_bounds(cmds)
        if one is None:
            continue
        box = one if box is None else (
            min(box[0], one[0]), min(box[1], one[1]),
            max(box[2], one[2]), max(box[3], one[3]),
        )
    return box


def union_box(boxes):
    boxes = [b for b in boxes if b]
    if not boxes:
        return None
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def box_tolerance(box):
    """bbox 비교 허용 오차. 도형보다 큰 오차를 쓰면 작은 도형끼리 아무렇게나 짝지어진다.
    그래서 절대값 0.5 와 도형 크기의 25% 중 작은 쪽을 쓴다."""
    if not box:
        return 0.0
    return min(0.5, 0.25 * max(box[2] - box[0], box[3] - box[1]))


def same_box(a, b, tolerance):
    return bool(a) and bool(b) and max(abs(x - y) for x, y in zip(a, b)) <= tolerance


def similar_counts(a, b):
    """명령 개수 비교. 작은 도형은 정확히 같아야 하고, 큰 도형은 20% 까지 봐준다 —
    Figma 는 큰 실루엣의 stroke 를 fill 보다 촘촘하게 내보낸다(측정: 374 vs 440)."""
    biggest = max(a, b)
    return abs(a - b) <= (0 if biggest < 20 else 0.2 * biggest)


def mark_stroke_twins(shapes):
    """Figma 는 한 도형의 fill 과 stroke 를 **자리가 같은 path 두 벌**로 내보낸다
    (fill 조각 여러 개 + stroke 하나인 경우도 있다). 그런 stroke 를 찾아 표시한다.

    같은 색이면 그 fill 이 이미 칠하고 있으니 stroke 를 통째로 버린다. 색이 다르면 그
    도형의 외곽선이다(눈 테두리 등) — 두께는 유지하되 축소 후 사라지지 않게 최소 두께
    규칙은 똑같이 건다.

    짝짓기 조건은 두 가지다: bbox 가 도형 크기에 비례한 오차 안에서 같고, path 명령
    개수도 비슷해야 한다. 둘 다 봐야 작은 도형이 엉뚱하게 짝지어지지 않는다.
    """
    boxes = [shape.bounds() for shape in shapes]
    counts = [len(shape.cmds()) for shape in shapes]
    fills = [normal_color(shape.attrs.get("fill")) for shape in shapes]
    strokes = [normal_color(shape.attrs.get("stroke")) for shape in shapes]
    for i, shape in enumerate(shapes):
        if strokes[i] is None or fills[i] is not None:
            continue
        tolerance = box_tolerance(boxes[i])
        # 1) 바로 앞의 "같은 색 fill" 연속 구간과 자리·명령 수가 같은가.
        run, j = [], i - 1
        while j >= 0 and fills[j] == strokes[i] and strokes[j] is None:
            run.append(j)
            j -= 1
        if (run and same_box(union_box([boxes[k] for k in run]), boxes[i], tolerance)
                and similar_counts(sum(counts[k] for k in run), counts[i])):
            shape.twin = "same"
            shape.twin_of = [shapes[k] for k in run]
            continue
        # 2) 자리·명령 수가 같은 fill 도형을 찾는다. 같은 색이 있으면 그쪽을 고른다.
        match = None
        for k in range(len(shapes)):
            if k == i or fills[k] is None:
                continue
            if same_box(boxes[k], boxes[i], tolerance) and similar_counts(counts[k], counts[i]):
                if fills[k] == strokes[i]:
                    match = k
                    break
                if match is None:
                    match = k
        if match is not None:
            shape.twin = "same" if fills[match] == strokes[i] else "outline"
            shape.twin_of = [shapes[match]]


def twin_report(shape):
    """버린 stroke 쌍 한 줄 — 선이 사라졌다는 신고가 오면 여기부터 본다."""
    box = shape.bounds()
    data = (shape.element.get("d") or "").strip().replace("\n", " ")
    return "%s stroke=%s bbox=(%s) ← %s  d=%s%s" % (
        shape.label(), shape.attrs.get("stroke"),
        ", ".join(num(v) for v in box) if box else "",
        ", ".join(other.label() for other in shape.twin_of),
        data[:40], "…" if len(data) > 40 else "",
    )


def largest_body_index(body):
    """bbox 면적이 가장 큰 몸통 도형의 문서 순번. 꼬리 z 순서 판정 기준이다."""
    best, best_area = None, -1.0
    for shape in body:
        box = shape.bounds()
        if box is None:
            continue
        area = (box[2] - box[0]) * (box[3] - box[1])
        if area > best_area:
            best, best_area = shape, area
    return -1 if best is None else (best.index if best.index is not None else -1)


def parse_view_box(root):
    values = [float(v) for v in S.NUMBER_RE.findall(root.get("viewBox") or "")]
    if len(values) != 4 or values[2] <= 0 or values[3] <= 0:
        fail('viewBox="0 0 775 775" 형태의 viewBox 가 필요하다 (받은 값: %r)' % root.get("viewBox"))
    return values


def build_arguments(argv):
    parser = argparse.ArgumentParser(
        prog="import-cat-svg.py", description="Figma SVG → Design/cats/<포즈>.svg")
    parser.add_argument("source")
    # alert 는 sitting 과 같게 다룬다 — 꼬리 두 프레임을 그대로 살린다.
    parser.add_argument("--pose", required=True, choices=("sitting", "sleeping", "alert"))
    parser.add_argument("--out", required=True)
    parser.add_argument("--fur", required=True, help="몸통 털색 (예: '#7D6C62')")
    parser.add_argument("--fur-dark", required=True, help="어두운 털색 (예: '#66584F')")
    parser.add_argument("--fur-light", required=True, help="밝은 털색 (예: '#A09084')")
    parser.add_argument("--tail-paths", default=None,
                        help="id 가 없을 때 쓰는 1-based path 순번 목록 (예: 12,13,14)")
    parser.add_argument("--tail-angle", type=float, default=-8.0,
                        help="tail-b 를 만들 때 쓰는 회전 각(도). 기본 -8")
    parser.add_argument("--tail-pivot", default=None,
                        help="회전 중심 'X,Y' (원본 좌표). 기본값은 꼬리 bbox 의 (minX, maxY)")
    parser.add_argument("--pad", type=float, default=2.0, help="64 상자 안쪽 여백. 기본 2")
    parser.add_argument("--keep-stroke-twins", action="store_true",
                        help="Figma 의 fill/stroke 쌍 정리를 끈다 (선이 사라졌을 때 확인용)")
    return parser.parse_args(argv)


def convert(text, args):
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        fail("SVG 를 파싱할 수 없다: %s" % error)
    if S.local_name(root.tag) != "svg":
        fail("루트 요소가 <svg> 가 아니다: <%s>" % S.local_name(root.tag))
    if (root.get("transform") or "").strip():
        fail("루트 <svg> 의 transform 은 변환할 수 없다.")

    view_box = parse_view_box(root)
    importer = Importer(root, view_box)
    importer.check_clip(root, "svg", S.IDENTITY)
    # 루트 <svg> 의 표현 속성도 상속된다 — Figma 는 fill="none" 을 여기 단다.
    importer.walk(root, resolve_style(root, {}), S.IDENTITY, "body")
    if not importer.shapes:
        fail("변환할 도형이 없다.")

    tail_a = [s for s in importer.shapes if s.bucket == "tail-a"]
    tail_b = [s for s in importer.shapes if s.bucket == "tail-b"]
    synthesized = False

    if not tail_a and not tail_b and args.tail_paths:
        wanted = set()
        for chunk in args.tail_paths.split(","):
            chunk = chunk.strip()
            if not chunk.isdigit():
                fail("--tail-paths 는 쉼표로 이은 1-based 정수여야 한다: %r" % args.tail_paths)
            wanted.add(int(chunk))
        tail_a = [s for s in importer.shapes if s.index in wanted]
        if len(tail_a) != len(wanted):
            fail("--tail-paths 가 가리키는 path 를 다 찾지 못했다 (문서에는 path 가 %d 개다)."
                 % importer.path_count)
        for shape in tail_a:
            shape.bucket = "tail-a"

    if args.pose == "sleeping":
        # 자는 자세는 꼬리 토글이 없다. tail-a 는 문서 순서 그대로 몸통에 접고 tail-b 는 버린다.
        for shape in tail_a:
            shape.bucket = "body"
        for shape in tail_b:
            shape.bucket = "drop"
        tail_a, tail_b = [], []
    elif not tail_a:
        fail("꼬리를 찾을 수 없다. Figma 에서 꼬리 프레임 이름을 'tail-a'(두 번째 프레임은 "
             "'tail-b')로 바꾸고 \"Include id attribute\" 를 켜서 다시 내보내거나, "
             "--tail-paths 12,13,14 처럼 path 순번을 넘겨라.")

    # stroke 쌍 정리는 **버킷을 나눈 뒤** 한다 — 버려질 tail-b 의 fill 과 몸통 stroke 가
    # 짝지어져 몸통 선이 조용히 사라지면 안 된다.
    kept = [s for s in importer.shapes if s.bucket != "drop"]
    dropped_twins = []
    if not args.keep_stroke_twins:
        mark_stroke_twins(kept)
        dropped_twins = [s for s in kept
                         if s.twin == "same" and normal_color(s.attrs.get("fill")) is None]
        gone = {id(s) for s in dropped_twins}
        kept = [s for s in kept if id(s) not in gone]

    body = [s for s in kept if s.bucket == "body"]
    tail_a = [s for s in kept if s.bucket == "tail-a"]
    tail_b = [s for s in kept if s.bucket == "tail-b"]
    drawn = body + tail_a + tail_b

    rotate = None
    if tail_a and not tail_b:
        # 두 번째 프레임이 없으면 꼬리 밑동을 축으로 살짝 돌려 만든다.
        box = bounds_of(tail_a)
        if args.tail_pivot:
            parts = [p.strip() for p in args.tail_pivot.split(",")]
            if len(parts) != 2:
                fail("--tail-pivot 은 'X,Y' 형태여야 한다: %r" % args.tail_pivot)
            pivot = (float(parts[0]), float(parts[1]))
        else:
            pivot = (box[0], box[3])      # 꼬리가 몸에 닿는 쪽(왼쪽 아래)
        rotate = "rotate(%s %s %s)" % (num(args.tail_angle), num(pivot[0]), num(pivot[1]))
        tail_b = tail_a
        synthesized = True
        drawn = drawn + tail_a           # 회전본도 상자 안에 들어와야 한다
        rotate_matrix = S.parse_transform(rotate)
    else:
        rotate_matrix = None

    box = bounds_of(body + tail_a)
    if rotate_matrix is not None:
        rotated = bounds_of(tail_a, rotate_matrix)
        if rotated is not None:
            box = (min(box[0], rotated[0]), min(box[1], rotated[1]),
                   max(box[2], rotated[2]), max(box[3], rotated[3]))
    elif tail_b:
        other = bounds_of(tail_b)
        if other is not None:
            box = (min(box[0], other[0]), min(box[1], other[1]),
                   max(box[2], other[2]), max(box[3], other[3]))
    if box is None:
        fail("그림의 bbox 를 잴 수 없다.")

    bw, bh = box[2] - box[0], box[3] - box[1]
    if bw <= 0 and bh <= 0:
        fail("그림의 bbox 가 비어 있다.")
    scale = (BOX - 2.0 * args.pad) / max(bw, bh)
    tx = BOX / 2.0 - scale * (box[0] + box[2]) / 2.0        # 가로 가운데
    ty = BOX - args.pad - scale * box[3]                    # 바닥 정렬
    fit = "translate(%s %s) scale(%s)" % (num(tx), num(ty), num(scale))

    colors = {
        normal_color(args.fur): "#FUR",
        normal_color(args.fur_dark): "#FURDARK",
        normal_color(args.fur_light): "#FURLIGHT",
    }

    tail_above = bool(tail_a) and tail_a[0].index is not None \
        and tail_a[0].index > largest_body_index(body)

    header = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="256" height="256">\n'
        "  <!-- GENERATED — scripts/import-cat-svg.py 가 %s 에서 만든다. 손으로 고치지 말 것.\n"
        "       다시 만들려면: scripts/generate-cat-art.sh -->"
        % os.path.basename(args.source)
    )
    body_xml = group_xml("body", body, fit, scale, colors)
    parts = [header]
    tails = []
    if tail_a:
        tails.append(group_xml("tail-a", tail_a, fit, scale, colors))
    if tail_b:
        tails.append(group_xml("tail-b", tail_b, fit, scale, colors,
                               inner_transform=rotate if synthesized else None))
    parts.extend(([body_xml] + tails) if tail_above else (tails + [body_xml]))
    parts.append("</svg>\n")
    return "\n".join(parts), {
        "shapes": len(drawn),
        "droppedStrokeTwins": len(dropped_twins),
        "droppedTwinLines": [twin_report(s) for s in dropped_twins],
        "body": len(body),
        "tailA": len(tail_a),
        "tailB": len(tail_b),
        "scale": scale,
        "tailAboveBody": tail_above,
        "synthesizedTailB": synthesized,
    }


def main(argv):
    args = build_arguments(argv[1:])
    with open(args.source, encoding="utf-8") as handle:
        text = handle.read()
    svg, info = convert(text, args)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(svg)
    for line in info["droppedTwinLines"]:
        sys.stderr.write("  stroke 쌍 제거: %s\n" % line)
    sys.stderr.write(
        "import-cat-svg: %s → %s (body %d, tail-a %d, tail-b %d%s, stroke 쌍 %d개 제거, "
        "scale %s, tailAboveBody %s)\n"
        % (os.path.basename(args.source), args.out, info["body"], info["tailA"],
           info["tailB"], " 합성" if info["synthesizedTailB"] else "",
           info["droppedStrokeTwins"], num(info["scale"]),
           "true" if info["tailAboveBody"] else "false")
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
