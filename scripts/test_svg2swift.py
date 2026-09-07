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


class FillRuleTests(unittest.TestCase):
    def test_evenodd_survives(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR" fill-rule="evenodd"/>')
        self.assertEqual(S.parse_svg(svg)["body"][0].fill_rule, "evenodd")

    def test_default_is_nonzero(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR"/>')
        self.assertEqual(S.parse_svg(svg)["body"][0].fill_rule, "nonzero")

    def test_inherited_from_group(self):
        svg = wrap('<g fill-rule="evenodd"><path d="M0 0 L1 1" fill="#FUR"/></g>')
        self.assertEqual(S.parse_svg(svg)["body"][0].fill_rule, "evenodd")

    def test_different_fill_rules_never_merge(self):
        """같은 색이어도 채우기 규칙이 다르면 합치면 안 된다 — 구멍이 메워진다."""
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR" fill-rule="evenodd"/>'
                   '<path d="M2 2 L3 3" fill="#FUR"/>')
        layers = S.parse_svg(svg)["body"]
        self.assertEqual(len(layers), 2)
        self.assertEqual([layer.fill_rule for layer in layers], ["evenodd", "nonzero"])

    def test_swift_emits_fill_rule(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR" fill-rule="evenodd"/>')
        layers = S.parse_svg(svg)["body"]
        self.assertIn("fillRule: .evenOdd", S.swift_layers("x", layers))

    def test_unknown_fill_rule_aborts(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR" fill-rule="wat"/>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("fill-rule", str(ctx.exception))


class LineJoinTests(unittest.TestCase):
    def test_default_is_round(self):
        svg = wrap('<path d="M0 0 L4 0" stroke="#FUR"/>')
        self.assertEqual(S.parse_svg(svg)["body"][0].line_join, "round")

    def test_explicit_bevel(self):
        svg = wrap('<path d="M0 0 L4 0" stroke="#FUR" stroke-linejoin="bevel"/>')
        layers = S.parse_svg(svg)["body"]
        self.assertEqual(layers[0].line_join, "bevel")
        self.assertIn("lineJoin: .bevel", S.swift_layers("x", layers))

    def test_different_line_joins_do_not_merge(self):
        svg = wrap('<path d="M0 0 L4 0" stroke="#FUR" stroke-linejoin="miter"/>'
                   '<path d="M0 4 L4 4" stroke="#FUR"/>')
        self.assertEqual(len(S.parse_svg(svg)["body"]), 2)

    def test_unknown_line_join_aborts(self):
        svg = wrap('<path d="M0 0 L4 0" stroke="#FUR" stroke-linejoin="wat"/>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("stroke-linejoin", str(ctx.exception))


class FurLightTests(unittest.TestCase):
    def test_placeholder(self):
        self.assertEqual(S.parse_color("#FURLIGHT"), S.FUR_LIGHT)
        self.assertEqual(S.parse_color("#furlight"), S.FUR_LIGHT)

    def test_swift_case(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FURLIGHT"/>')
        self.assertIn("fill: .furLight", S.swift_layers("x", S.parse_svg(svg)["body"]))

    def test_does_not_merge_with_fur(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR"/><path d="M2 2 L3 3" fill="#FURLIGHT"/>')
        self.assertEqual(len(S.parse_svg(svg)["body"]), 2)


class BoundsTests(unittest.TestCase):
    def test_line_bounds(self):
        self.assertEqual(S.commands_bounds([("M", 1.0, 2.0), ("L", 5.0, 8.0)]), (1.0, 2.0, 5.0, 8.0))

    def test_curve_extreme_is_tighter_than_control_hull(self):
        """제어점 껍데기는 y=10 까지 가지만 실제 곡선은 7.5 까지만 간다."""
        box = S.commands_bounds([("M", 0.0, 0.0), ("C", 0.0, 10.0, 10.0, 10.0, 10.0, 0.0)])
        self.assertAlmostEqual(box[1], 0.0, places=6)
        self.assertAlmostEqual(box[3], 7.5, places=6)

    def test_empty(self):
        self.assertIsNone(S.commands_bounds([]))


class TailOrderTests(unittest.TestCase):
    def test_tail_after_body_is_above(self):
        svg = wrap('<g id="body"><path d="M0 0 L1 1" fill="#FUR"/></g>'
                   '<g id="tail-a"><path d="M2 2 L3 3" fill="#FUR"/></g>')
        _, above = S.parse_svg(svg, want_order=True)
        self.assertTrue(above)

    def test_tail_before_body_is_below(self):
        svg = wrap('<g id="tail-a"><path d="M2 2 L3 3" fill="#FUR"/></g>'
                   '<g id="body"><path d="M0 0 L1 1" fill="#FUR"/></g>')
        _, above = S.parse_svg(svg, want_order=True)
        self.assertFalse(above)

    def test_no_tail_is_below(self):
        _, above = S.parse_svg(wrap('<path d="M0 0 L1 1" fill="#FUR"/>'), want_order=True)
        self.assertFalse(above)


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

    def test_root_clip_path_aborts(self):
        """walk() 는 자식만 본다 — 루트 <svg> 의 clip-path 도 막아야 한다."""
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" clip-path="url(#c)">'
               '<path d="M0 0 L1 1" fill="#FUR"/></svg>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("clip-path", str(ctx.exception))
        self.assertIn("svg", str(ctx.exception))

    def test_root_mask_in_inline_style_aborts(self):
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" style="mask:url(#m)">'
               '<path d="M0 0 L1 1" fill="#FUR"/></svg>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("mask", str(ctx.exception))

    def test_root_transform_aborts(self):
        """루트 transform 은 조용히 무시됐다. 적용하는 대신 이름을 찍고 중단한다."""
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" transform="translate(10,0)">'
               '<path d="M0 0 L1 1" fill="#FUR"/></svg>')
        with self.assertRaises(SystemExit) as ctx:
            S.parse_svg(svg)
        self.assertIn("transform", str(ctx.exception))
        self.assertIn("svg", str(ctx.exception))

    def test_root_without_transform_is_fine(self):
        svg = wrap('<path d="M0 0 L1 1" fill="#FUR"/>')
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
        self.alert = os.path.join(REPO, "Design", "cats", "alert.svg")
        self.all_poses = (self.sitting, self.sleeping, self.alert)

    def test_groups_split(self):
        with open(self.sitting, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        self.assertIn("body", groups)
        self.assertIn("tailA", groups)
        self.assertIn("tailB", groups)
        self.assertTrue(all(groups[k] for k in ("body", "tailA", "tailB")))

    def test_generated_swift_has_all_constants(self):
        swift = S.convert_files(list(self.all_poses))
        for name in ("sittingBody", "sittingTailA", "sittingTailB", "sleepingBody",
                     "alertBody", "alertTailA", "alertTailB"):
            self.assertIn("static let %s: [CatArtLayer]" % name, swift)
        self.assertIn("GENERATED", swift)

    def test_generated_swift_has_scalars(self):
        swift = S.convert_files(list(self.all_poses))
        self.assertIn("static let sittingTailAboveBody: Bool", swift)
        self.assertIn("static let sittingTop: CGFloat", swift)
        self.assertIn("static let sleepingTop: CGFloat", swift)
        self.assertIn("static let alertTop: CGFloat", swift)
        self.assertIn("static let alertTailAboveBody: Bool", swift)
        # 자는 자세는 꼬리 프레임이 없으므로 z 순서 상수도 나오지 않는다.
        self.assertNotIn("sleepingTailAboveBody", swift)

    def test_alert_groups_split_like_sitting(self):
        with open(self.alert, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        self.assertTrue(all(groups[k] for k in ("body", "tailA", "tailB")))

    def test_missing_alert_svg_falls_back_to_sitting(self):
        """alert.svg 를 아직 안 그렸어도 런타임이 참조하는 alert* 상수는 나와야 한다."""
        swift = S.convert_files([self.sitting, self.sleeping])
        self.assertIn("static let alertBody: [CatArtLayer] = sittingBody", swift)
        self.assertIn("static let alertTailA: [CatArtLayer] = sittingTailA", swift)
        self.assertIn("static let alertTailB: [CatArtLayer] = sittingTailB", swift)
        self.assertIn("static let alertTop: CGFloat = sittingTop", swift)
        self.assertIn("static let alertTailAboveBody: Bool = sittingTailAboveBody", swift)

    def test_real_alert_svg_beats_the_fallback(self):
        swift = S.convert_files(list(self.all_poses))
        self.assertNotIn("= sittingBody", swift)
        self.assertNotIn("= sittingTop", swift)

    def test_top_is_inside_the_box_and_above_the_middle(self):
        for path in self.all_poses:
            with open(path, encoding="utf-8") as f:
                groups = S.parse_svg(f.read())
            box = S.layers_bounds([l for layers in groups.values() for l in layers])
            self.assertGreater(box[3], 20)
            self.assertLessEqual(box[3], 64)

    def test_all_coordinates_in_range(self):
        for path in self.all_poses:
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
