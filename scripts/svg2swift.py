#!/usr/bin/env python3
"""Design/cats/*.svg → Sources/ClaudeCats/CatArt*.generated.swift 변환기.

표준 라이브러리만 쓴다. 사용법:

    python3 scripts/svg2swift.py --out-dir Sources/ClaudeCats Design/cats/*.svg

`--out-dir` 없이 부르면 전체를 stdout 으로 이어 찍는다(눈으로 볼 때만 쓴다).

내보내는 파일은 포즈마다 하나씩 + 공용 타입 하나다.

    CatArt.generated.swift            타입(CatArtColor·CatArtLayer·enum CatArt)과 별칭
    CatArt.<포즈>.generated.swift     그 포즈의 상수·레이어·경로 데이터

경로는 **코드가 아니라 데이터**로 나간다. `p.addCurve(...)` 문장 수천 개 대신
`[명령코드, 좌표...]` 평평한 `[Float]` 리터럴을 싣고, 런타임이
`ClaudeCatsCore.PathData.build` 로 한 번 펴서 CGPath 를 만든다(issue #4).

입력 규약은 README 의 "직접 그린 SVG 넣는 법" 절 참고. 요약:
  - viewBox 필수. 그림은 64×64 박스에 균일 스케일로 맞춘다.
  - `<g id="tail-a">`, `<g id="tail-b">` 는 꼬리 프레임, 나머지는 전부 body.
  - `#FUR`, `#FURDARK`, `#FURLIGHT` 는 런타임 팔레트 플레이스홀더.
  - 좌표는 여기서 AppKit 좌표(y 위로)로 뒤집어 내보낸다. 런타임은 그대로 쓴다.
"""

import math
import os
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Optional

BOX = 64.0

FUR = ("fur",)
FUR_DARK = ("furDark",)
FUR_LIGHT = ("furLight",)

SHAPE_TAGS = {"path", "ellipse", "circle", "rect", "line", "polygon", "polyline"}
IGNORED_TAGS = {"title", "desc", "metadata"}

# 상속되는 표현 속성. transform 은 따로 합성한다.
INHERITED = (
    "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
    "fill-opacity", "stroke-opacity", "fill-rule",
)

NAMED_COLORS = {
    "black": "#000000", "white": "#ffffff", "red": "#ff0000",
    "green": "#008000", "blue": "#0000ff", "gray": "#808080",
    "grey": "#808080", "silver": "#c0c0c0", "maroon": "#800000",
    "navy": "#000080", "olive": "#808000", "purple": "#800080",
    "teal": "#008080", "yellow": "#ffff00", "orange": "#ffa500",
    "fuchsia": "#ff00ff", "aqua": "#00ffff", "lime": "#00ff00",
}

NUMBER_RE = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
SCALAR_RE = re.compile(r"\s*([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)\s*(%|[a-zA-Z]*)\s*\Z")

# 변환할 수 없는데 조용히 무시하면 그림이 달라지는 속성들.
UNSUPPORTED_ATTRS = ("clip-path", "mask", "filter")


def fail(message):
    raise SystemExit("svg2swift: " + message)


def parse_scalar(text, attribute, allow_percent=False):
    """'2', '2px', '50%' → 숫자. 퍼센트는 1/100 로 읽고, 그 밖의 단위는 에러."""
    match = SCALAR_RE.match(text or "")
    if not match:
        fail("%s 값을 읽을 수 없다: %r" % (attribute, text))
    value = float(match.group(1))
    unit = match.group(2).lower()
    if unit == "%":
        if not allow_percent:
            fail("%s 에는 퍼센트를 쓸 수 없다: %r" % (attribute, text))
        return value / 100.0
    if unit not in ("", "px"):
        fail("%s 의 단위 %r 는 지원하지 않는다 (사용자 단위나 px 만 쓴다): %r" % (attribute, unit, text))
    return value


# ---------------------------------------------------------------- 색


def parse_color(text):
    """'#FUR'|'#FURDARK'|'none'|'#rgb'|'#rgba'|'#rrggbb'|'#rrggbbaa'|이름 → 페인트 또는 None."""
    if text is None:
        return None
    s = text.strip()
    low = s.lower()
    if low in ("none", "transparent", ""):
        return None
    if low == "#fur":
        return FUR
    if low == "#furdark":
        return FUR_DARK
    if low == "#furlight":
        return FUR_LIGHT
    if low in NAMED_COLORS:
        s = NAMED_COLORS[low]
    if not s.startswith("#"):
        fail("지원하지 않는 색 표기: %r (16진수 또는 #FUR/#FURDARK/#FURLIGHT 만 지원)" % text)
    digits = s[1:]
    if len(digits) in (3, 4):
        digits = "".join(c * 2 for c in digits)
    if len(digits) not in (6, 8) or any(c not in "0123456789abcdefABCDEF" for c in digits):
        fail("지원하지 않는 색 표기: %r" % text)
    values = [int(digits[i:i + 2], 16) / 255.0 for i in range(0, len(digits), 2)]
    r, g, b = values[0], values[1], values[2]
    a = values[3] if len(values) == 4 else 1.0
    return ("fixed", r, g, b, a)


# ---------------------------------------------------------------- 행렬

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def mat_mul(m1, m2):
    """m1 ∘ m2 — m2 를 먼저 적용한다."""
    a1, b1, c1, d1, e1, f1 = m1
    a2, b2, c2, d2, e2, f2 = m2
    return (
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1,
        b1 * e2 + d1 * f2 + f1,
    )


def mat_apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def mat_scale_factor(m):
    a, b, c, d = m[0], m[1], m[2], m[3]
    return math.sqrt(abs(a * d - b * c))


TRANSFORM_RE = re.compile(r"([a-zA-Z]+)\s*\(([^)]*)\)")


def parse_transform(text):
    if not text:
        return IDENTITY
    result = IDENTITY
    consumed = 0
    for match in TRANSFORM_RE.finditer(text):
        if text[consumed:match.start()].strip(" ,\t\r\n"):
            fail("transform 을 해석할 수 없다: %r" % text)
        consumed = match.end()
        name = match.group(1).lower()
        args = [float(v) for v in NUMBER_RE.findall(match.group(2))]
        if name == "translate":
            tx = args[0] if args else 0.0
            ty = args[1] if len(args) > 1 else 0.0
            m = (1.0, 0.0, 0.0, 1.0, tx, ty)
        elif name == "scale":
            sx = args[0] if args else 1.0
            sy = args[1] if len(args) > 1 else sx
            m = (sx, 0.0, 0.0, sy, 0.0, 0.0)
        elif name == "rotate":
            angle = math.radians(args[0] if args else 0.0)
            cos, sin = math.cos(angle), math.sin(angle)
            m = (cos, sin, -sin, cos, 0.0, 0.0)
            if len(args) >= 3:
                cx, cy = args[1], args[2]
                m = mat_mul((1.0, 0.0, 0.0, 1.0, cx, cy), mat_mul(m, (1.0, 0.0, 0.0, 1.0, -cx, -cy)))
        elif name == "matrix":
            if len(args) != 6:
                fail("matrix() 인자는 6개여야 한다: %r" % text)
            m = tuple(args)
        elif name == "skewx":
            m = (1.0, 0.0, math.tan(math.radians(args[0])), 1.0, 0.0, 0.0)
        elif name == "skewy":
            m = (1.0, math.tan(math.radians(args[0])), 0.0, 1.0, 0.0, 0.0)
        else:
            fail("지원하지 않는 transform: %s" % name)
        result = mat_mul(result, m)
    if text[consumed:].strip(" ,\t\r\n"):
        fail("transform 을 해석할 수 없다: %r" % text)
    return result


# ---------------------------------------------------------------- path 파서


class Scanner:
    def __init__(self, text):
        self.text = text
        self.i = 0

    def skip(self):
        while self.i < len(self.text) and self.text[self.i] in ", \t\r\n":
            self.i += 1

    def eof(self):
        self.skip()
        return self.i >= len(self.text)

    def peek_command(self):
        self.skip()
        if self.i < len(self.text) and self.text[self.i].isalpha():
            return self.text[self.i]
        return None

    def take_command(self):
        cmd = self.peek_command()
        if cmd is None:
            fail("path 명령을 찾을 수 없다: %r" % self.text[self.i:self.i + 12])
        self.i += 1
        return cmd

    def number(self):
        self.skip()
        match = NUMBER_RE.match(self.text, self.i)
        if not match:
            fail("path 에서 숫자를 읽을 수 없다: %r" % self.text[self.i:self.i + 12])
        self.i = match.end()
        return float(match.group(0))

    def flag(self):
        self.skip()
        if self.i >= len(self.text) or self.text[self.i] not in "01":
            fail("호(arc) 플래그는 0 또는 1 이어야 한다: %r" % self.text[self.i:self.i + 12])
        value = self.text[self.i] == "1"
        self.i += 1
        return value


def arc_to_cubics(x1, y1, rx, ry, phi_deg, large, sweep, x2, y2):
    """SVG 1.1 F.6.5 endpoint→center 변환 후 90° 이하 조각으로 나눠 3차 베지어 근사."""
    if x1 == x2 and y1 == y2:
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [("L", x2, y2)]

    phi = math.radians(phi_deg)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2.0, (y1 - y2) / 2.0
    x1p = cos_p * dx + sin_p * dy
    y1p = -sin_p * dx + cos_p * dy

    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1.0:
        scale = math.sqrt(lam)
        rx *= scale
        ry *= scale

    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cos_p * cxp - sin_p * cyp + (x1 + x2) / 2.0
    cy = sin_p * cxp + cos_p * cyp + (y1 + y2) / 2.0

    def angle(ux, uy, vx, vy):
        norm = math.hypot(ux, uy) * math.hypot(vx, vy)
        if norm == 0:
            return 0.0
        value = max(-1.0, min(1.0, (ux * vx + uy * vy) / norm))
        result = math.acos(value)
        return -result if (ux * vy - uy * vx) < 0 else result

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta1 = angle(1.0, 0.0, ux, uy)
    dtheta = angle(ux, uy, vx, vy)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi

    count = max(1, int(math.ceil(abs(dtheta) / (math.pi / 2.0) - 1e-9)))
    delta = dtheta / count
    t = 4.0 / 3.0 * math.tan(delta / 4.0)

    def point(theta):
        return (
            cx + rx * math.cos(theta) * cos_p - ry * math.sin(theta) * sin_p,
            cy + rx * math.cos(theta) * sin_p + ry * math.sin(theta) * cos_p,
        )

    def derivative(theta):
        return (
            -rx * math.sin(theta) * cos_p - ry * math.cos(theta) * sin_p,
            -rx * math.sin(theta) * sin_p + ry * math.cos(theta) * cos_p,
        )

    out = []
    for i in range(count):
        a1 = theta1 + i * delta
        a2 = a1 + delta
        p1 = point(a1)
        p2 = point(a2) if i < count - 1 else (x2, y2)
        d1 = derivative(a1)
        d2 = derivative(a2)
        out.append((
            "C",
            p1[0] + t * d1[0], p1[1] + t * d1[1],
            p2[0] - t * d2[0], p2[1] - t * d2[1],
            p2[0], p2[1],
        ))
    return out


def parse_path_data(d):
    """path d → 절대 좌표 명령 리스트 [('M',x,y) | ('L',x,y) | ('C',...) | ('Z',)]."""
    scanner = Scanner(d)
    out = []
    cx = cy = 0.0          # 현재 점
    sx = sy = 0.0          # 서브패스 시작점
    last_cubic = None      # 직전 3차 제어점 2
    last_quad = None       # 직전 2차 제어점
    command = None
    started = False

    def quad(qx, qy, ex, ey):
        return (
            "C",
            cx + 2.0 / 3.0 * (qx - cx), cy + 2.0 / 3.0 * (qy - cy),
            ex + 2.0 / 3.0 * (qx - ex), ey + 2.0 / 3.0 * (qy - ey),
            ex, ey,
        )

    while not scanner.eof():
        nxt = scanner.peek_command()
        if nxt is not None:
            command = scanner.take_command()
        elif command is None:
            fail("path 가 명령으로 시작하지 않는다: %r" % d)
        elif command in "Mm":
            command = "L" if command == "M" else "l"
        elif command in "Zz":
            fail("Z 뒤에 명령 없이 좌표가 온다: %r" % d)
        if command not in "MmLlHhVvCcSsQqTtAaZz":
            fail("지원하지 않는 path 명령: %r" % command)

        rel = command.islower()
        upper = command.upper()
        if upper == "Z":
            out.append(("Z",))
            cx, cy = sx, sy
            last_cubic = last_quad = None
            continue

        if upper == "M":
            x, y = scanner.number(), scanner.number()
            if rel and started:
                x, y = cx + x, cy + y
            cx, cy = x, y
            sx, sy = x, y
            started = True
            out.append(("M", x, y))
            last_cubic = last_quad = None
            continue

        if not started:
            fail("path 가 M 없이 시작한다: %r" % d)

        if upper == "L":
            x, y = scanner.number(), scanner.number()
            if rel:
                x, y = cx + x, cy + y
            out.append(("L", x, y))
            cx, cy = x, y
            last_cubic = last_quad = None
        elif upper == "H":
            x = scanner.number()
            if rel:
                x += cx
            out.append(("L", x, cy))
            cx = x
            last_cubic = last_quad = None
        elif upper == "V":
            y = scanner.number()
            if rel:
                y += cy
            out.append(("L", cx, y))
            cy = y
            last_cubic = last_quad = None
        elif upper == "C":
            values = [scanner.number() for _ in range(6)]
            if rel:
                values = [v + (cx if i % 2 == 0 else cy) for i, v in enumerate(values)]
            out.append(("C", *values))
            last_cubic = (values[2], values[3])
            last_quad = None
            cx, cy = values[4], values[5]
        elif upper == "S":
            values = [scanner.number() for _ in range(4)]
            if rel:
                values = [v + (cx if i % 2 == 0 else cy) for i, v in enumerate(values)]
            if last_cubic is None:
                c1x, c1y = cx, cy
            else:
                c1x, c1y = 2 * cx - last_cubic[0], 2 * cy - last_cubic[1]
            out.append(("C", c1x, c1y, values[0], values[1], values[2], values[3]))
            last_cubic = (values[0], values[1])
            last_quad = None
            cx, cy = values[2], values[3]
        elif upper == "Q":
            values = [scanner.number() for _ in range(4)]
            if rel:
                values = [v + (cx if i % 2 == 0 else cy) for i, v in enumerate(values)]
            out.append(quad(values[0], values[1], values[2], values[3]))
            last_quad = (values[0], values[1])
            last_cubic = None
            cx, cy = values[2], values[3]
        elif upper == "T":
            values = [scanner.number() for _ in range(2)]
            if rel:
                values = [values[0] + cx, values[1] + cy]
            if last_quad is None:
                qx, qy = cx, cy
            else:
                qx, qy = 2 * cx - last_quad[0], 2 * cy - last_quad[1]
            out.append(quad(qx, qy, values[0], values[1]))
            last_quad = (qx, qy)
            last_cubic = None
            cx, cy = values[0], values[1]
        elif upper == "A":
            rx, ry, rot = scanner.number(), scanner.number(), scanner.number()
            large, sweep = scanner.flag(), scanner.flag()
            x, y = scanner.number(), scanner.number()
            if rel:
                x, y = cx + x, cy + y
            out.extend(arc_to_cubics(cx, cy, rx, ry, rot, large, sweep, x, y))
            cx, cy = x, y
            last_cubic = last_quad = None
    return out


# ---------------------------------------------------------------- 도형 → 명령

KAPPA = 0.5522847498307936


def ellipse_commands(cx, cy, rx, ry):
    """SVG 좌표계(y 아래)에서 시계 방향 4조각 3차 베지어."""
    ox, oy = rx * KAPPA, ry * KAPPA
    return [
        ("M", cx + rx, cy),
        ("C", cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry),
        ("C", cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy),
        ("C", cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry),
        ("C", cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy),
        ("Z",),
    ]


def rect_commands(x, y, w, h, rx, ry):
    if w <= 0 or h <= 0:
        return []
    if rx is None and ry is None:
        rx = ry = 0.0
    elif rx is None:
        rx = ry
    elif ry is None:
        ry = rx
    rx = min(rx, w / 2.0)
    ry = min(ry, h / 2.0)
    if rx <= 0 or ry <= 0:
        return [
            ("M", x, y), ("L", x + w, y), ("L", x + w, y + h), ("L", x, y + h), ("Z",),
        ]
    ox, oy = rx * KAPPA, ry * KAPPA
    return [
        ("M", x + rx, y),
        ("L", x + w - rx, y),
        ("C", x + w - rx + ox, y, x + w, y + ry - oy, x + w, y + ry),
        ("L", x + w, y + h - ry),
        ("C", x + w, y + h - ry + oy, x + w - rx + ox, y + h, x + w - rx, y + h),
        ("L", x + rx, y + h),
        ("C", x + rx - ox, y + h, x, y + h - ry + oy, x, y + h - ry),
        ("L", x, y + ry),
        ("C", x, y + ry - oy, x + rx - ox, y, x + rx, y),
        ("Z",),
    ]


def points_commands(text, close):
    values = [float(v) for v in NUMBER_RE.findall(text or "")]
    if len(values) < 4:
        return []
    out = [("M", values[0], values[1])]
    for i in range(2, len(values) - 1, 2):
        out.append(("L", values[i], values[i + 1]))
    if close:
        out.append(("Z",))
    return out


# ---------------------------------------------------------------- 레이어


@dataclass
class Layer:
    cmds: list = field(default_factory=list)
    fill: Optional[tuple] = None
    stroke: Optional[tuple] = None
    line_width: float = 0.0
    line_cap: str = "butt"
    opacity: float = 1.0
    fill_rule: str = "nonzero"
    line_join: str = "round"

    def style_key(self):
        # fill_rule 이 다르면 절대 합치지 않는다 — 합치면 구멍이 생기거나 메워진다.
        return (self.fill, self.stroke, round(self.line_width, 6), self.line_cap,
                round(self.opacity, 6), self.fill_rule, self.line_join)


def number_attr(element, name, default=None):
    text = element.get(name)
    if text is None or text.strip() == "":
        return default
    return parse_scalar(text, "<%s> 의 %s" % (local_name(element.tag), name))


def local_name(tag):
    return tag.split("}")[-1] if isinstance(tag, str) else str(tag)


def parse_style(text):
    out = {}
    for chunk in (text or "").split(";"):
        if ":" not in chunk:
            continue
        key, value = chunk.split(":", 1)
        out[key.strip().lower()] = value.strip()
    return out


def element_style(element, inherited):
    style = dict(inherited)
    declarations = parse_style(element.get("style"))
    for key in INHERITED + ("opacity",):
        value = declarations.get(key, element.get(key))
        if value is not None and value.strip() != "":
            style[key] = value.strip()
    # opacity 는 상속이 아니라 그룹 합성이지만, 여기서는 곱으로 접는다.
    group_opacity = style.pop("opacity", None)
    if group_opacity is not None:
        alpha = parse_scalar(group_opacity, "opacity", allow_percent=True)
        style["_opacity"] = float(inherited.get("_opacity", 1.0)) * max(0.0, min(1.0, alpha))
    return style


def paint_alpha(style, key):
    value = style.get(key)
    if value is None:
        return 1.0
    return max(0.0, min(1.0, parse_scalar(value, key, allow_percent=True)))


def make_layers(cmds, style, matrix):
    """한 도형 → CatArtLayer 후보 1~2개(불투명도가 접히지 않으면 fill/stroke 분리)."""
    if not cmds:
        return []
    fill = parse_color(style.get("fill", "#000000"))
    stroke = parse_color(style.get("stroke"))
    if fill is None and stroke is None:
        return []

    base_opacity = float(style.get("_opacity", 1.0))
    line_width = 0.0
    if stroke is not None:
        width = style.get("stroke-width")
        width = 1.0 if width is None else parse_scalar(width, "stroke-width")
        line_width = width * mat_scale_factor(matrix)
    line_cap = (style.get("stroke-linecap") or "butt").lower()
    if line_cap not in ("butt", "round", "square"):
        fail("지원하지 않는 stroke-linecap: %s" % line_cap)
    # CAShapeLayer 기본값이 miter 라도 우리 아트는 round 가 기본이다(예전 런타임 동작 유지).
    line_join = (style.get("stroke-linejoin") or "round").lower()
    if line_join not in ("miter", "round", "bevel"):
        fail("지원하지 않는 stroke-linejoin: %s" % line_join)
    fill_rule = (style.get("fill-rule") or "nonzero").lower()
    if fill_rule not in ("nonzero", "evenodd"):
        fail("지원하지 않는 fill-rule: %s" % fill_rule)

    def fold(paint, alpha):
        """(페인트, 레이어 불투명도 배수) — 고정색이면 알파에 접고, 플레이스홀더면 레이어로 뺀다."""
        if paint is None:
            return None, 1.0
        if paint[0] == "fixed":
            return ("fixed", paint[1], paint[2], paint[3], paint[4] * alpha), 1.0
        return paint, alpha

    fill_paint, fill_mul = fold(fill, paint_alpha(style, "fill-opacity"))
    stroke_paint, stroke_mul = fold(stroke, paint_alpha(style, "stroke-opacity"))

    if fill_paint is not None and stroke_paint is not None and abs(fill_mul - stroke_mul) > 1e-9:
        # 팔레트 플레이스홀더에 fill-opacity/stroke-opacity 가 서로 다르게 걸린 경우만.
        return [
            Layer(list(cmds), fill_paint, None, 0.0, line_cap,
                  base_opacity * fill_mul, fill_rule, line_join),
            Layer(list(cmds), None, stroke_paint, line_width, line_cap,
                  base_opacity * stroke_mul, fill_rule, line_join),
        ]
    multiplier = fill_mul if fill_paint is not None else stroke_mul
    return [Layer(list(cmds), fill_paint, stroke_paint, line_width, line_cap,
                  base_opacity * multiplier, fill_rule, line_join)]


# ---------------------------------------------------------------- SVG 순회


def check_only_ignorable(element):
    for child in element.iter():
        name = local_name(child.tag)
        if child is element:
            continue
        if name not in IGNORED_TAGS:
            fail("지원하지 않는 SVG 요소: <%s> (그라디언트·필터·텍스트·이미지 등은 변환할 수 없다)" % name)


def check_unsupported_attrs(element, name):
    """조용히 무시하면 그림이 달라지는 속성은 이름을 찍고 중단한다."""
    declarations = parse_style(element.get("style"))
    for attribute in UNSUPPORTED_ATTRS:
        value = element.get(attribute) or declarations.get(attribute)
        if value and value.strip().lower() != "none":
            fail("<%s> 의 %s 는 변환할 수 없다 (%s=%r). 내보내기 전에 flatten 해야 한다."
                 % (name, attribute, attribute, value))


def shape_commands(element):
    name = local_name(element.tag)
    if name == "path":
        return parse_path_data(element.get("d") or "")
    if name == "ellipse":
        cx = number_attr(element, "cx", 0.0)
        cy = number_attr(element, "cy", 0.0)
        rx = number_attr(element, "rx")
        ry = number_attr(element, "ry")
        if rx is None or ry is None:
            fail("<ellipse> 에 rx/ry 가 필요하다")
        return ellipse_commands(cx, cy, rx, ry)
    if name == "circle":
        r = number_attr(element, "r")
        if r is None:
            fail("<circle> 에 r 이 필요하다")
        return ellipse_commands(number_attr(element, "cx", 0.0), number_attr(element, "cy", 0.0), r, r)
    if name == "rect":
        return rect_commands(
            number_attr(element, "x", 0.0), number_attr(element, "y", 0.0),
            number_attr(element, "width", 0.0), number_attr(element, "height", 0.0),
            number_attr(element, "rx"), number_attr(element, "ry"),
        )
    if name == "line":
        return [
            ("M", number_attr(element, "x1", 0.0), number_attr(element, "y1", 0.0)),
            ("L", number_attr(element, "x2", 0.0), number_attr(element, "y2", 0.0)),
        ]
    if name == "polygon":
        return points_commands(element.get("points"), close=True)
    if name == "polyline":
        return points_commands(element.get("points"), close=False)
    fail("지원하지 않는 SVG 요소: <%s>" % name)


def _cubic_bounds(p0, p1, p2, p3):
    """3차 베지어 한 축의 [min, max] — 제어점 껍데기가 아니라 실제 극값."""
    lo, hi = min(p0, p3), max(p0, p3)
    a = -p0 + 3.0 * p1 - 3.0 * p2 + p3
    b = 2.0 * (p0 - 2.0 * p1 + p2)
    c = p1 - p0
    roots = []
    if abs(a) < 1e-12:
        if abs(b) > 1e-12:
            roots.append(-c / b)
    else:
        disc = b * b - 4.0 * a * c
        if disc >= 0.0:
            root = math.sqrt(disc)
            roots.extend([(-b + root) / (2.0 * a), (-b - root) / (2.0 * a)])
    for t in roots:
        if 0.0 < t < 1.0:
            u = 1.0 - t
            value = (u * u * u * p0 + 3.0 * u * u * t * p1
                     + 3.0 * u * t * t * p2 + t * t * t * p3)
            lo, hi = min(lo, value), max(hi, value)
    return lo, hi


def commands_bounds(cmds):
    """명령 리스트 → (minX, minY, maxX, maxY). 곡선은 극값까지 포함한다. 선 두께는 무시."""
    box = [None, None, None, None]

    def add(x, y):
        if box[0] is None:
            box[0], box[1], box[2], box[3] = x, y, x, y
        else:
            box[0], box[1] = min(box[0], x), min(box[1], y)
            box[2], box[3] = max(box[2], x), max(box[3], y)

    cx = cy = 0.0
    sx = sy = 0.0          # 서브패스 시작점 — Z 는 여기로 되돌아간다
    for cmd in cmds:
        head = cmd[0]
        if head == "Z":
            cx, cy = sx, sy
        elif head in ("M", "L"):
            cx, cy = cmd[1], cmd[2]
            if head == "M":
                sx, sy = cx, cy
            add(cx, cy)
        elif head == "C":
            x_lo, x_hi = _cubic_bounds(cx, cmd[1], cmd[3], cmd[5])
            y_lo, y_hi = _cubic_bounds(cy, cmd[2], cmd[4], cmd[6])
            add(x_lo, y_lo)
            add(x_hi, y_hi)
            cx, cy = cmd[5], cmd[6]
    if box[0] is None:
        return None
    return tuple(box)


def layers_bounds(layers):
    """[Layer] → (minX, minY, maxX, maxY) 또는 None."""
    box = None
    for layer in layers:
        one = commands_bounds(layer.cmds)
        if one is None:
            continue
        box = one if box is None else (
            min(box[0], one[0]), min(box[1], one[1]),
            max(box[2], one[2]), max(box[3], one[3]),
        )
    return box


def transform_commands(cmds, matrix):
    out = []
    for cmd in cmds:
        head, values = cmd[0], cmd[1:]
        points = []
        for i in range(0, len(values), 2):
            points.extend(mat_apply(matrix, values[i], values[i + 1]))
        out.append((head, *points))
    return out


def walk(element, style, matrix, buckets, bucket, order=None):
    """order 가 주어지면 도형이 나온 순서대로 버킷 이름을 기록한다(꼬리 z 순서 판정용)."""
    for child in element:
        name = local_name(child.tag)
        if name in IGNORED_TAGS:
            continue
        if name == "defs":
            check_only_ignorable(child)
            continue
        check_unsupported_attrs(child, name)
        child_matrix = mat_mul(matrix, parse_transform(child.get("transform")))
        child_style = element_style(child, style)
        if name in ("g", "svg", "a"):
            child_bucket = bucket
            group_id = (child.get("id") or "").strip().lower()
            if group_id == "tail-a":
                child_bucket = "tailA"
            elif group_id == "tail-b":
                child_bucket = "tailB"
            elif group_id == "body":
                child_bucket = "body"
            walk(child, child_style, child_matrix, buckets, child_bucket, order)
        elif name in SHAPE_TAGS:
            cmds = transform_commands(shape_commands(child), child_matrix)
            layers = make_layers(cmds, child_style, child_matrix)
            buckets.setdefault(bucket, []).extend(layers)
            if order is not None and layers:
                order.append(bucket)
        else:
            fail("지원하지 않는 SVG 요소: <%s> (그라디언트·필터·텍스트·이미지 등은 변환할 수 없다)" % name)


def merge_layers(layers):
    merged = []
    for layer in layers:
        if merged and merged[-1].style_key() == layer.style_key():
            merged[-1].cmds.extend(layer.cmds)
        else:
            merged.append(layer)
    return merged


def base_matrix(view_box):
    """viewBox → 64×64 박스 균일 스케일·가운데 정렬, 그 뒤 y 뒤집기."""
    values = [float(v) for v in NUMBER_RE.findall(view_box or "")]
    if len(values) != 4 or values[2] <= 0 or values[3] <= 0:
        fail('viewBox="0 0 64 64" 형태의 viewBox 가 필요하다 (받은 값: %r)' % view_box)
    min_x, min_y, width, height = values
    scale = min(BOX / width, BOX / height)
    dx = (BOX - width * scale) / 2.0
    dy = (BOX - height * scale) / 2.0
    fit = mat_mul((scale, 0.0, 0.0, scale, dx, dy), (1.0, 0.0, 0.0, 1.0, -min_x, -min_y))
    flip = (1.0, 0.0, 0.0, -1.0, 0.0, BOX)   # y' = 64 - y (모든 변환 이후에 적용)
    return mat_mul(flip, fit)


def parse_svg(text, want_order=False):
    """SVG 문자열 → {'body'|'tailA'|'tailB': [Layer]} (좌표는 이미 AppKit 방향).

    want_order=True 면 (그룹, tail_above_body) 를 돌려준다. tail_above_body 는
    `tail-a` 의 첫 도형이 `body` 의 마지막 도형보다 뒤에 나왔는지 — 즉 꼬리를 몸통
    **위**에 얹어야 하는지다.
    """
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        fail("SVG 를 파싱할 수 없다: %s" % error)
    if local_name(root.tag) != "svg":
        fail("루트 요소가 <svg> 가 아니다: <%s>" % local_name(root.tag))

    # walk() 는 자식만 검사한다. 루트 <svg> 의 속성은 아무도 안 보고 지나가므로
    # 여기서 직접 막는다 — 조용히 무시하면 그림이 달라진다.
    check_unsupported_attrs(root, "svg")
    if (root.get("transform") or "").strip():
        fail('루트 <svg> 의 transform 은 변환할 수 없다 (transform=%r). '
             "viewBox 로 옮기거나 내보내기 전에 flatten 해야 한다." % root.get("transform"))

    buckets = {}
    order = []
    walk(root, {}, base_matrix(root.get("viewBox")), buckets, "body", order)
    groups = {name: merge_layers(layers) for name, layers in buckets.items() if layers}
    if not want_order:
        return groups
    tail_above = False
    if "tailA" in order and "body" in order:
        tail_above = order.index("tailA") > len(order) - 1 - order[::-1].index("body")
    return groups, tail_above


# ---------------------------------------------------------------- Swift 생성


def num(value, places=2):
    """숫자 → Swift 리터럴. 기본 소수 2자리 — 64pt 상자에서 0.01pt 는 2x 화면의 0.02px 다.
    자릿수를 줄이면 생성 파일이 작아지고 컴파일이 빨라진다. 임포터는 places=4 로 쓴다
    (fit 변환의 scale 을 반올림하면 바닥 정렬이 어긋난다)."""
    text = ("%." + str(places) + "f") % (value + 0.0)
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def swift_color(paint):
    if paint is None:
        return "nil"
    if paint[0] == "fur":
        return ".fur"
    if paint[0] == "furDark":
        return ".furDark"
    if paint[0] == "furLight":
        return ".furLight"
    return ".fixed(r: %s, g: %s, b: %s, a: %s)" % tuple(num(v) for v in paint[1:])


# ---------------------------------------------------------------- 경로 인코딩
#
# 경로를 Swift **문장**으로 펼치면 타입체커가 호출식 수천 개를 씹어야 해서 빌드가
# 100초씩 걸린다(issue #4). 대신 `[명령코드, 좌표...]` 를 이어 붙인 평평한 숫자
# 배열 하나로 내보내고, 런타임의 `PathData.build` 가 한 번에 CGPath 로 편다.

OP_MOVE, OP_LINE, OP_CUBIC, OP_CLOSE = 0, 1, 2, 3

# 명령코드 → 뒤따르는 좌표 개수. Swift 쪽 PathData 와 이 표가 정본이다.
OP_ARITY = {OP_MOVE: 2, OP_LINE: 2, OP_CUBIC: 6, OP_CLOSE: 0}


def encode_path(cmds):
    """명령 리스트 → [명령코드, 좌표...] 평평한 숫자 배열.

    3차 베지어는 명령 리스트 그대로 제어점1·제어점2·끝점 순서로 싣는다.
    """
    out = []
    for cmd in cmds:
        head = cmd[0]
        if head == "M":
            out.extend((OP_MOVE, cmd[1], cmd[2]))
        elif head == "L":
            out.extend((OP_LINE, cmd[1], cmd[2]))
        elif head == "C":
            out.extend((OP_CUBIC, cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6]))
        elif head == "Z":
            out.append(OP_CLOSE)
    return out


def decode_path(values):
    """encode_path 의 역. Swift `PathData.build` 와 같은 규칙으로 읽는다 —
    배열이 잘렸거나 모르는 명령코드가 나오면 그 자리에서 조용히 멈춘다."""
    out = []
    i = 0
    n = len(values)
    while i < n:
        op = values[i]
        if op == OP_MOVE and i + 2 < n:
            out.append(("M", values[i + 1], values[i + 2]))
        elif op == OP_LINE and i + 2 < n:
            out.append(("L", values[i + 1], values[i + 2]))
        elif op == OP_CUBIC and i + 6 < n:
            out.append(("C", *values[i + 1:i + 7]))
        elif op == OP_CLOSE:
            out.append(("Z",))
        else:
            break
        i += 1 + OP_ARITY[op]
    return out


def swift_data(name, values):
    """평평한 숫자 배열 → `private let <name>: [Float] = [...]`.

    한 줄에 명령 하나씩 찍는다 — 그림을 고쳤을 때 diff 가 명령 단위로 남는다.
    """
    lines = ["private let %s: [Float] = [" % name]
    i = 0
    n = len(values)
    while i < n:
        op = int(values[i])
        arity = OP_ARITY[op]
        row = [str(op)] + [num(v) for v in values[i + 1:i + 1 + arity]]
        lines.append("    " + ", ".join(row) + ",")
        i += 1 + arity
    lines.append("]")
    return "\n".join(lines)


def swift_layers(name, layers):
    """(`static let <name>: [CatArtLayer]` 소스, 그 경로 데이터 배열 소스들)."""
    out = ["    static let %s: [CatArtLayer] = [" % name]
    data = []
    for index, layer in enumerate(layers):
        data_name = "%s%d" % (name, index)
        data.append(swift_data(data_name, encode_path(layer.cmds)))
        out.append("        CatArtLayer(")
        out.append("            path: PathData.build(%s)," % data_name)
        out.append("            fill: %s," % swift_color(layer.fill))
        out.append("            stroke: %s," % swift_color(layer.stroke))
        out.append("            lineWidth: %s," % num(layer.line_width))
        out.append("            lineCap: .%s," % layer.line_cap)
        out.append("            lineJoin: .%s," % layer.line_join)
        out.append("            fillRule: .%s," % ("evenOdd" if layer.fill_rule == "evenodd" else "nonZero"))
        out.append("            opacity: %s" % num(layer.opacity))
        out.append("        ),")
    out.append("    ]")
    return "\n".join(out), data


SHARED_FILE = "CatArt.generated.swift"
POSE_FILE = "CatArt.%s.generated.swift"

SHARED_HEADER = """// GENERATED — edit Design/cats/*.svg and run scripts/generate-cat-art.sh
// 여기에는 타입과 별칭만 있다. 포즈별 도형은 CatArt.<포즈>.generated.swift 로 나뉜다
// (그림 한 포즈만 고쳐도 그 파일만 다시 컴파일되게 — issue #4).
import CoreGraphics
import QuartzCore

/// SVG 의 `#FUR`/`#FURDARK`/`#FURLIGHT` 플레이스홀더는 런타임 팔레트에서 색을 받는다.
enum CatArtColor: Equatable, Sendable {
    case fur
    case furDark
    case furLight
    case fixed(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
}

/// CGPath 는 불변이라 값처럼 공유해도 안전하다(생성 후 아무도 변형하지 않는다).
struct CatArtLayer: @unchecked Sendable {
    let path: CGPath
    let fill: CatArtColor?
    let stroke: CatArtColor?
    let lineWidth: CGFloat
    let lineCap: CAShapeLayerLineCap
    let lineJoin: CAShapeLayerLineJoin
    let fillRule: CAShapeLayerFillRule
    let opacity: Float
}

enum CatArt {"""

POSE_HEADER = """// GENERATED — edit Design/cats/%s.svg and run scripts/generate-cat-art.sh
// 좌표는 64×64 박스, AppKit 방향(y 위로)으로 이미 뒤집혀 있다.
// 경로는 코드가 아니라 데이터다 — 파일 끝의 [명령코드, 좌표...] 배열을
// PathData.build 가 처음 쓸 때 한 번 CGPath 로 편다.
import ClaudeCatsCore
import CoreGraphics
import QuartzCore

extension CatArt {"""


def camel(text):
    parts = re.split(r"[^0-9a-zA-Z]+", text)
    parts = [p for p in parts if p]
    if not parts:
        fail("파일 이름에서 식별자를 만들 수 없다: %r" % text)
    return parts[0][0].lower() + parts[0][1:] + "".join(p[0].upper() + p[1:] for p in parts[1:])


# alert.svg 를 아직 안 그렸어도 Swift 는 컴파일돼야 한다(런타임이 CatArt.alert* 를 참조한다).
# 그럴 땐 앉은 자세를 그대로 별칭으로 삼는다.
FALLBACK_POSE = ("alert", "sitting")


def fallback_aliases(stems, section_names, scalar_names):
    """alert 가 입력에 없으면 sitting 의 상수를 alert* 이름으로 다시 노출한다."""
    missing, source = FALLBACK_POSE
    if missing in stems or source not in stems:
        return []
    lines = ["    // %s.svg 가 아직 없다 — %s 자세를 그대로 쓴다." % (missing, source)]
    for suffix in ("Body", "TailA", "TailB"):
        if source + suffix in section_names:
            lines.append("    static let %s%s: [CatArtLayer] = %s%s"
                         % (missing, suffix, source, suffix))
    if source + "Top" in scalar_names:
        lines.append("    static let %sTop: CGFloat = %sTop" % (missing, source))
    if source + "TailAboveBody" in scalar_names:
        lines.append("    static let %sTailAboveBody: Bool = %sTailAboveBody"
                     % (missing, source))
    return ["\n".join(lines)]


def convert_files(paths):
    """[SVG 경로] → {생성 파일 이름: Swift 소스}. 포즈마다 한 파일 + 공용 타입 한 파일."""
    files = {}
    stems = []
    section_names = set()
    scalar_names = set()
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            groups, tail_above = parse_svg(handle.read(), want_order=True)
        stem = camel(os.path.splitext(os.path.basename(path))[0])
        stems.append(stem)

        sections, data = [], []
        for bucket in ("body", "tailA", "tailB"):
            if bucket in groups:
                name = stem + bucket[0].upper() + bucket[1:]
                section_names.add(name)
                text, arrays = swift_layers(name, groups[bucket])
                sections.append(text)
                data.extend(arrays)
        if not sections:
            fail("%s 에 변환할 도형이 없다" % path)

        box = layers_bounds([layer for layers in groups.values() for layer in layers])
        scalar_names.add(stem + "Top")
        scalars = [
            "    /// 말풍선을 얹을 그림 꼭대기(AppKit y). 선 두께는 빼고 경로 bbox 만 본다.\n"
            "    static let %sTop: CGFloat = %s" % (stem, num(box[3] if box else BOX))
        ]
        if "tailA" in groups:
            scalar_names.add(stem + "TailAboveBody")
            scalars.append(
                "    /// 원본 SVG 에서 꼬리가 몸통 뒤에 오면 false — 런타임이 그릇 레이어 순서를 맞춘다.\n"
                "    static let %sTailAboveBody: Bool = %s" % (stem, "true" if tail_above else "false")
            )

        files[POSE_FILE % stem] = (
            (POSE_HEADER % stem) + "\n"
            + "\n\n".join(scalars + sections) + "\n}\n\n"
            + "\n\n".join(data) + "\n"
        )

    if not files:
        fail("변환할 도형이 없다")
    aliases = fallback_aliases(set(stems), section_names, scalar_names)
    files[SHARED_FILE] = SHARED_HEADER + "\n" + "".join(text + "\n" for text in aliases) + "}\n"
    return files


def write_files(out_dir, files):
    """생성 파일을 쓰고, 더는 안 쓰는 예전 생성 파일을 지운다. (쓴 것, 지운 것)."""
    for name in sorted(files):
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as handle:
            handle.write(files[name])
    removed = []
    for name in sorted(os.listdir(out_dir)):
        if name in files or name == SHARED_FILE:
            continue
        # 포즈가 없어지면 그 포즈 파일이 남아 컴파일을 깨뜨린다. 여기서만 지운다.
        if name.startswith("CatArt.") and name.endswith(".generated.swift"):
            os.remove(os.path.join(out_dir, name))
            removed.append(name)
    return sorted(files), removed


USAGE = "사용법: svg2swift.py [--out-dir <디렉터리>] <입력.svg> [입력2.svg ...]"


def main(argv):
    args = list(argv[1:])
    out_dir = None
    if "--out-dir" in args:
        index = args.index("--out-dir")
        if index + 1 >= len(args):
            fail("--out-dir 뒤에 디렉터리가 필요하다. " + USAGE)
        out_dir = args[index + 1]
        del args[index:index + 2]
    if not args:
        fail(USAGE)

    files = convert_files(args)
    if out_dir is None:
        # 디렉터리를 안 주면 전부 이어서 stdout 에 찍는다(눈으로 볼 때만 쓴다).
        sys.stdout.write("\n".join(files[name] for name in sorted(files)))
        return 0
    if not os.path.isdir(out_dir):
        fail("출력 디렉터리가 없다: %s" % out_dir)
    written, removed = write_files(out_dir, files)
    for name in written:
        lines = files[name].count("\n")
        sys.stderr.write("생성: %s (%d 줄)\n" % (os.path.join(out_dir, name), lines))
    for name in removed:
        sys.stderr.write("삭제: %s (더는 쓰지 않는 생성물)\n" % os.path.join(out_dir, name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
