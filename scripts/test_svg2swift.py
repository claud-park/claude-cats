"""svg2swift 변환기 검증. 실행: python3 -m unittest scripts/test_svg2swift.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import svg2swift as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def wrap(body, view_box="0 0 64 64"):
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">%s</svg>' % (view_box, body)


class ColorTests(unittest.TestCase):
    def test_fur_placeholder(self):
        self.assertEqual(S.parse_color("#FUR"), S.FUR)
        self.assertEqual(S.parse_color("#furdark"), S.FUR_DARK)

    def test_hex3(self):
        kind, r, g, b, a = S.parse_color("#abc")
        self.assertEqual(kind, "fixed")
        self.assertAlmostEqual(r, 0.667, places=3)
        self.assertAlmostEqual(g, 0.733, places=3)
        self.assertAlmostEqual(b, 0.800, places=3)
        self.assertAlmostEqual(a, 1.0, places=6)

    def test_hex8_alpha(self):
        kind, r, g, b, a = S.parse_color("#11223380")
        self.assertEqual(kind, "fixed")
        self.assertAlmostEqual(a, 0.5, places=2)

    def test_none(self):
        self.assertIsNone(S.parse_color("none"))


class TransformTests(unittest.TestCase):
    def test_group_and_element_transform_compose(self):
        svg = wrap(
            '<g transform="translate(10,0)">'
            '<rect x="1" y="2" width="3" height="4" transform="scale(2)" fill="#FUR"/>'
            "</g>"
        )
        layers = S.parse_svg(svg)["body"]
        self.assertEqual(layers[0].cmds[0][0], "M")
        x, y = layers[0].cmds[0][1], layers[0].cmds[0][2]
        self.assertAlmostEqual(x, 12.0, places=6)
        self.assertAlmostEqual(y, 60.0, places=6)   # 64 - 4

    def test_stroke_width_scales_with_transform(self):
        svg = wrap('<g transform="scale(2)"><path d="M0 0 L4 0" stroke="#FUR" stroke-width="1.5"/></g>')
        layers = S.parse_svg(svg)["body"]
        self.assertAlmostEqual(layers[0].line_width, 3.0, places=6)


class UnitTests(unittest.TestCase):
    def test_percentage_fill_opacity(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#123456" fill-opacity="50%"/>')
        layer = S.parse_svg(svg)["body"][0]
        self.assertAlmostEqual(layer.fill[4], 0.5, places=6)

    def test_px_stroke_width(self):
        svg = wrap('<path d="M0 0 L4 0" stroke="#FUR" stroke-width="2px"/>')
        self.assertAlmostEqual(S.parse_svg(svg)["body"][0].line_width, 2.0, places=6)

    def test_percentage_opacity(self):
        svg = wrap('<g opacity="40%"><path d="M0 0 L1 1" fill="#FUR"/></g>')
        self.assertAlmostEqual(S.parse_svg(svg)["body"][0].opacity, 0.4, places=6)

    def test_unknown_unit_fails_with_attribute_name(self):
        svg = wrap('<path d="M0 0 L4 0" stroke="#FUR" stroke-width="2em"/>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("stroke-width", str(ctx.exception))

    def test_percentage_length_fails(self):
        svg = wrap('<rect x="0" y="0" width="50%" height="4" fill="#FUR"/>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("width", str(ctx.exception))


class PathCommandTests(unittest.TestCase):
    def test_relative_h_v_q(self):
        svg = wrap('<path d="M10 10 h5 v5 q5 0 5 -5" fill="none" stroke="#FUR"/>')
        cmds = S.parse_svg(svg)["body"][0].cmds
        self.assertEqual(cmds[0], ("M", 10.0, 54.0))
        self.assertEqual(cmds[1], ("L", 15.0, 54.0))
        self.assertEqual(cmds[2], ("L", 15.0, 49.0))
        self.assertEqual(cmds[3][0], "C")
        # q 5 0 5 -5 → 제어점 (20,15), 끝점 (20,10) → 뒤집으면 (20,49)/(20,54)
        self.assertAlmostEqual(cmds[3][5], 20.0, places=6)
        self.assertAlmostEqual(cmds[3][6], 54.0, places=6)
        # 2차 → 3차 승격: 제어점은 시작·끝점의 1/3 지점
        self.assertAlmostEqual(cmds[3][1], 15.0 + (20.0 - 15.0) * 2 / 3, places=6)

    def test_relative_moveto_after_close(self):
        svg = wrap('<path d="M10 10 h4 v4 Z m2 2 l1 0" fill="#FUR"/>')
        cmds = S.parse_svg(svg)["body"][0].cmds
        self.assertIn(("Z",), cmds)
        after = cmds[cmds.index(("Z",)) + 1]
        # Z 뒤의 m 은 서브패스 시작점(10,10) 기준 → (12,12) → 뒤집으면 (12,52)
        self.assertEqual(after, ("M", 12.0, 52.0))

    def test_arc_becomes_few_cubics_with_exact_endpoint(self):
        svg = wrap('<path d="M8 32 A16 16 0 1 1 40 32" fill="none" stroke="#FUR"/>')
        cmds = S.parse_svg(svg)["body"][0].cmds
        curves = [c for c in cmds if c[0] == "C"]
        self.assertGreaterEqual(len(curves), 1)
        self.assertLessEqual(len(curves), 4)
        self.assertAlmostEqual(curves[-1][5], 40.0, places=6)
        self.assertAlmostEqual(curves[-1][6], 32.0, places=6)   # 64 - 32

    def test_relative_arc(self):
        svg = wrap('<path d="M8 32 a16 16 0 1 1 32 0" fill="none" stroke="#FUR"/>')
        cmds = S.parse_svg(svg)["body"][0].cmds
        curves = [c for c in cmds if c[0] == "C"]
        self.assertLessEqual(len(curves), 4)
        self.assertAlmostEqual(curves[-1][5], 40.0, places=6)
        self.assertAlmostEqual(curves[-1][6], 32.0, places=6)

    def test_smooth_curve_reflects_control_point(self):
        svg = wrap('<path d="M0 0 C0 10 10 10 10 0 s10 -10 10 0" fill="none" stroke="#FUR"/>')
        cmds = S.parse_svg(svg)["body"][0].cmds
        c2 = [c for c in cmds if c[0] == "C"][1]
        # 반사 제어점: (10,0)*2 - (10,10) = (10,-10) → 뒤집으면 y=74
        self.assertAlmostEqual(c2[1], 10.0, places=6)
        self.assertAlmostEqual(c2[2], 74.0, places=6)


class MergeTests(unittest.TestCase):
    def test_adjacent_same_style_merges(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR"/><path d="M2 2 L3 3" fill="#FUR"/>')
        self.assertEqual(len(S.parse_svg(svg)["body"]), 1)

    def test_different_style_does_not_merge(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR"/><path d="M2 2 L3 3" fill="#FURDARK"/>')
        self.assertEqual(len(S.parse_svg(svg)["body"]), 2)


class FailureTests(unittest.TestCase):
    def test_gradient_aborts(self):
        svg = wrap('<linearGradient id="g"/><path d="M0 0 L1 1" fill="#FUR"/>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("linearGradient", str(ctx.exception))

    def test_clip_path_attribute_aborts(self):
        svg = wrap('<g clip-path="url(#c)"><path d="M0 0 L1 1" fill="#FUR"/></g>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("clip-path", str(ctx.exception))
        self.assertIn("g", str(ctx.exception))

    def test_mask_in_inline_style_aborts(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR" style="mask:url(#m)"/>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("mask", str(ctx.exception))

    def test_clip_path_none_is_fine(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR" clip-path="none"/>')
        self.assertEqual(len(S.parse_svg(svg)["body"]), 1)

    def test_gradient_inside_defs_aborts(self):
        svg = wrap('<defs><linearGradient id="g"/></defs>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("linearGradient", str(ctx.exception))


class RealArtTests(unittest.TestCase):
    def setUp(self):
        self.sitting = os.path.join(REPO, "Design", "cats", "sitting.svg")
        self.sleeping = os.path.join(REPO, "Design", "cats", "sleeping.svg")

    def test_groups_split(self):
        with open(self.sitting, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        self.assertIn("body", groups)
        self.assertIn("tailA", groups)
        self.assertIn("tailB", groups)
        self.assertTrue(all(groups[k] for k in ("body", "tailA", "tailB")))

    def test_generated_swift_has_all_constants(self):
        swift = S.convert_files([self.sitting, self.sleeping])
        for name in ("sittingBody", "sittingTailA", "sittingTailB", "sleepingBody"):
            self.assertIn("static let %s: [CatArtLayer]" % name, swift)
        self.assertIn("GENERATED", swift)

    def test_all_coordinates_in_range(self):
        for path in (self.sitting, self.sleeping):
            with open(path, encoding="utf-8") as f:
                groups = S.parse_svg(f.read())
            for name, layers in groups.items():
                for layer in layers:
                    for cmd in layer.cmds:
                        for value in cmd[1:]:
                            self.assertGreaterEqual(value, -4, "%s %s" % (path, name))
                            self.assertLessEqual(value, 68, "%s %s" % (path, name))

    def test_fur_placeholders_survive(self):
        with open(self.sitting, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        paints = [layer.fill for layer in groups["body"]] + [layer.stroke for layer in groups["tailA"]]
        self.assertIn(S.FUR, paints)


if __name__ == "__main__":
    unittest.main()
