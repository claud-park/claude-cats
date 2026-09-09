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
        self.assertIn("fillRule: .evenOdd", S.swift_layers("x", layers)[0])

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
        self.assertIn("lineJoin: .bevel", S.swift_layers("x", layers)[0])

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
        self.assertIn("fill: .furLight", S.swift_layers("x", S.parse_svg(svg)["body"])[0])

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


class EncodeTests(unittest.TestCase):
    """경로 인코딩([명령코드, 좌표...]). Swift 쪽 짝은 ClaudeCatsCore.PathData 다."""

    SQUARE = [
        ("M", 0.0, 0.0), ("L", 10.0, 0.0), ("L", 10.0, 10.0),
        ("C", 8.0, 12.0, 2.0, 12.0, 0.0, 10.0), ("Z",),
    ]

    def test_opcodes_and_arities(self):
        self.assertEqual((S.OP_MOVE, S.OP_LINE, S.OP_CUBIC, S.OP_CLOSE), (0, 1, 2, 3))
        self.assertEqual(S.OP_ARITY, {0: 2, 1: 2, 2: 6, 3: 0})

    def test_known_command_list_encodes_flat(self):
        self.assertEqual(S.encode_path(self.SQUARE), [
            0, 0.0, 0.0,
            1, 10.0, 0.0,
            1, 10.0, 10.0,
            2, 8.0, 12.0, 2.0, 12.0, 0.0, 10.0,
            3,
        ])

    def test_round_trip(self):
        self.assertEqual(S.decode_path(S.encode_path(self.SQUARE)), self.SQUARE)

    def test_length_is_one_per_command_plus_its_coordinates(self):
        values = S.encode_path(self.SQUARE)
        self.assertEqual(len(values), sum(1 + S.OP_ARITY[
            {"M": S.OP_MOVE, "L": S.OP_LINE, "C": S.OP_CUBIC, "Z": S.OP_CLOSE}[c[0]]
        ] for c in self.SQUARE))

    def test_cubic_keeps_control_points_before_the_end_point(self):
        values = S.encode_path([("C", 1.0, 2.0, 3.0, 4.0, 5.0, 6.0)])
        self.assertEqual(values, [2, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0])

    def test_truncated_array_decodes_up_to_the_last_whole_command(self):
        values = S.encode_path(self.SQUARE)
        self.assertEqual(S.decode_path(values[:-3]), self.SQUARE[:3])
        self.assertEqual(S.decode_path(values[:2]), [])
        self.assertEqual(S.decode_path([]), [])

    def test_unknown_opcode_stops(self):
        self.assertEqual(S.decode_path([0, 1.0, 2.0, 9, 1.0, 2.0]), [("M", 1.0, 2.0)])

    def test_unknown_command_head_aborts(self):
        """조용히 흘리면 획 하나가 사라진 채로 커밋된다 — 이름을 찍고 중단해야 한다."""
        with self.assertRaises(SystemExit) as ctx:
            S.encode_path([("M", 0.0, 0.0), ("A", 1.0, 2.0)])
        self.assertIn("인코딩할 수 없는 명령", str(ctx.exception))
        self.assertIn("A", str(ctx.exception))

    def test_commands_before_any_move_stop(self):
        """Swift PathData.build 의 `!path.isEmpty` 가드와 같은 규칙이어야 한다."""
        self.assertEqual(S.decode_path([S.OP_LINE, 5.0, 5.0]), [])
        self.assertEqual(S.decode_path([S.OP_CUBIC, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0]), [])
        self.assertEqual(S.decode_path([S.OP_CLOSE]), [])
        # move 가 한 번 나온 뒤에는 close 도 정상이다.
        self.assertEqual(S.decode_path([0, 1.0, 2.0, 3]), [("M", 1.0, 2.0), ("Z",)])

    def test_swift_data_puts_one_command_per_line(self):
        text = S.swift_data("x0", S.encode_path(self.SQUARE))
        self.assertEqual(text.splitlines(), [
            "private let x0: [Float] = [",
            "    0, 0, 0,",
            "    1, 10, 0,",
            "    1, 10, 10,",
            "    2, 8, 12, 2, 12, 0, 10,",
            "    3,",
            "]",
        ])

    def test_swift_data_keeps_two_decimals(self):
        text = S.swift_data("x0", S.encode_path([("M", 1.234, 5.678)]))
        self.assertIn("    0, 1.23, 5.68,", text)


class WriteFilesTests(unittest.TestCase):
    def test_stale_pose_file_is_removed(self):
        import tempfile
        with tempfile.TemporaryDirectory() as out_dir:
            stale = os.path.join(out_dir, "CatArt.crouching.generated.swift")
            keep = os.path.join(out_dir, "CatLayer.swift")
            for path in (stale, keep):
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write("// x\n")
            written, removed = S.write_files(out_dir, {
                "CatArt.generated.swift": "// a\n",
                "CatArt.sitting.generated.swift": "// b\n",
            })
            self.assertEqual(written, ["CatArt.generated.swift", "CatArt.sitting.generated.swift"])
            self.assertEqual(removed, ["CatArt.crouching.generated.swift"])
            self.assertFalse(os.path.exists(stale))
            self.assertTrue(os.path.exists(keep))   # 생성물이 아닌 파일은 건드리지 않는다


class RealArtTests(unittest.TestCase):
    # 입력 경로가 생성 파일 헤더 주석에 그대로 박히므로, generate-cat-art.sh 와 똑같이
    # REPO 를 cwd 로 두고 **repo 상대 경로**로 부른다(그래야 커밋된 헤더와 바이트가 같다).
    def setUp(self):
        self._cwd = os.getcwd()
        os.chdir(REPO)
        self.sitting = os.path.join("Design", "cats", "sitting.svg")
        self.sleeping = os.path.join("Design", "cats", "sleeping.svg")
        self.alert = os.path.join("Design", "cats", "alert.svg")
        self.kenji_sitting = os.path.join("Design", "cats", "kenji-sitting.svg")
        self.kenji_sleeping = os.path.join("Design", "cats", "kenji-sleeping.svg")
        self.all_poses = (self.sitting, self.sleeping, self.alert)
        # 커밋된 생성물과 짝을 이루는 컨셉·포즈·경로 입력.
        self.inputs = [
            ("team", "sitting", self.sitting),
            ("team", "sleeping", self.sleeping),
            ("team", "alert", self.alert),
            ("kenji", "sitting", self.kenji_sitting),
            ("kenji", "sleeping", self.kenji_sleeping),
        ]

    def tearDown(self):
        os.chdir(self._cwd)

    def test_groups_split(self):
        with open(self.sitting, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        self.assertIn("body", groups)
        self.assertIn("tailA", groups)
        self.assertIn("tailB", groups)
        self.assertTrue(all(groups[k] for k in ("body", "tailA", "tailB")))

    def joined(self, inputs=None):
        """생성 파일 전부를 한 덩어리로 — "어딘가에는 있어야 한다" 류 검사용."""
        files = S.convert_files(list(inputs if inputs is not None else self.inputs))
        return "\n".join(files[name] for name in sorted(files))

    def test_generated_swift_has_all_constants(self):
        swift = self.joined()
        for name in ("teamSittingBody", "teamSittingTailA", "teamSittingTailB",
                     "teamSleepingBody", "teamAlertBody", "teamAlertTailA", "teamAlertTailB",
                     "kenjiSittingBody", "kenjiSleepingBody"):
            self.assertIn("static let %s: [CatArtLayer]" % name, swift)
        self.assertIn("GENERATED", swift)

    def test_generated_swift_has_scalars(self):
        swift = self.joined()
        self.assertIn("static let teamSittingTailAboveBody: Bool", swift)
        self.assertIn("static let teamSittingTop: CGFloat", swift)
        self.assertIn("static let teamSleepingTop: CGFloat", swift)
        self.assertIn("static let teamAlertTop: CGFloat", swift)
        self.assertIn("static let teamAlertTailAboveBody: Bool", swift)
        self.assertIn("static let kenjiSittingTop: CGFloat", swift)
        # 자는 자세는 꼬리 프레임이 없으므로 z 순서 상수도 나오지 않는다.
        self.assertNotIn("teamSleepingTailAboveBody", swift)
        # 켄지는 꼬리 프레임이 없어 어느 포즈에도 TailAboveBody 상수가 없다.
        self.assertNotIn("kenjiSittingTailAboveBody", swift)

    def test_shared_file_has_concept_sets_and_switch(self):
        shared = S.convert_files(list(self.inputs))["CatArt.generated.swift"]
        self.assertIn("struct CatArtSet", shared)
        self.assertIn("static let team = CatArtSet(", shared)
        self.assertIn("static let kenji = CatArtSet(", shared)
        self.assertIn("static func set(_ concept: CatConcept) -> CatArtSet", shared)
        self.assertIn("case .team: return team", shared)
        self.assertIn("case .kenji: return kenji", shared)

    def test_kenji_set_uses_empty_tails_and_sitting_for_alert(self):
        """켄지는 꼬리 프레임도 alert 원본도 없다 — 꼬리 배열은 비고 alert 는 sitting 으로 폴백한다."""
        shared = S.convert_files(list(self.inputs))["CatArt.generated.swift"]
        block = shared.split("static let kenji = CatArtSet(", 1)[1].split(")", 1)[0]
        self.assertIn("sittingTailA: [],", block)
        self.assertIn("sittingTailB: [],", block)
        self.assertIn("alertBody: kenjiSittingBody,", block)
        self.assertIn("alertTailA: [],", block)
        self.assertIn("sittingTailAboveBody: false,", block)
        # 켄지도 팔레트로 색을 입힌다(FUR/FURDARK 매핑).
        self.assertIn("recolorable: true", block)

    def test_team_set_uses_its_own_alert_art(self):
        shared = S.convert_files(list(self.inputs))["CatArt.generated.swift"]
        block = shared.split("static let team = CatArtSet(", 1)[1].split(")", 1)[0]
        self.assertIn("alertBody: teamAlertBody,", block)
        self.assertIn("sittingTailA: teamSittingTailA,", block)
        self.assertIn("recolorable: true", block)

    def test_alert_groups_split_like_sitting(self):
        with open(self.alert, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        self.assertTrue(all(groups[k] for k in ("body", "tailA", "tailB")))

    def test_missing_alert_svg_falls_back_to_sitting_in_the_set(self):
        """team alert 원본이 없으면 CatArtSet 이 sitting 을 alert 로 쓴다(런타임이 alert* 를 참조)."""
        files = S.convert_files([("team", "sitting", self.sitting),
                                 ("team", "sleeping", self.sleeping)])
        self.assertNotIn("CatArt.team.alert.generated.swift", files)
        shared = files["CatArt.generated.swift"]
        block = shared.split("static let team = CatArtSet(", 1)[1].split(")", 1)[0]
        self.assertIn("alertBody: teamSittingBody,", block)
        self.assertIn("alertTailA: teamSittingTailA,", block)
        self.assertIn("alertTop: teamSittingTop,", block)
        self.assertIn("alertTailAboveBody: teamSittingTailAboveBody,", block)

    def test_one_file_per_concept_pose_plus_a_shared_one(self):
        files = S.convert_files(list(self.inputs))
        self.assertEqual(sorted(files), [
            "CatArt.generated.swift",
            "CatArt.kenji.sitting.generated.swift",
            "CatArt.kenji.sleeping.generated.swift",
            "CatArt.team.alert.generated.swift",
            "CatArt.team.sitting.generated.swift",
            "CatArt.team.sleeping.generated.swift",
        ])

    def test_pose_file_holds_only_its_own_concept_pose(self):
        """컨셉·포즈 하나만 고쳤을 때 그 파일만 다시 컴파일되려면 서로 안 섞여야 한다."""
        files = S.convert_files(list(self.inputs))
        sitting = files["CatArt.team.sitting.generated.swift"]
        self.assertIn("static let teamSittingBody: [CatArtLayer]", sitting)
        self.assertIn("static let teamSittingTop: CGFloat", sitting)
        for other in ("sleeping", "alert", "kenji"):
            self.assertNotIn(other, sitting)

    def test_shared_file_has_the_types_and_no_coordinates(self):
        shared = S.convert_files(list(self.inputs))["CatArt.generated.swift"]
        self.assertIn("struct CatArtLayer", shared)
        self.assertIn("enum CatArtColor", shared)
        self.assertNotIn("[Float]", shared)
        self.assertNotIn("PathData.build", shared)

    def test_paths_are_data_not_statements(self):
        """경로는 CGMutablePath 문장이 아니라 [Float] 리터럴로 나가야 한다(issue #4)."""
        swift = self.joined()
        self.assertNotIn("CGMutablePath", swift)
        self.assertNotIn("addCurve", swift)
        self.assertIn("private let teamSittingBody0: [Float] = [", swift)
        self.assertIn("path: PathData.build(teamSittingBody0),", swift)

    def test_every_layer_gets_its_own_data_array(self):
        import re
        sitting = S.convert_files(list(self.inputs))["CatArt.team.sitting.generated.swift"]
        used = re.findall(r"PathData\.build\((\w+)\)", sitting)
        declared = re.findall(r"private let (\w+): \[Float\] = \[", sitting)
        self.assertEqual(sorted(used), sorted(declared))
        self.assertEqual(len(used), len(set(used)))

    def test_committed_generated_files_match_the_generator(self):
        """커밋된 생성물이 지금 생성기의 출력과 한 바이트도 다르지 않아야 한다.

        어긋나면 누가 생성물을 손으로 고쳤거나 생성기를 고치고 안 돌린 것이다.
        고치는 법: `scripts/generate-cat-art.sh`.
        """
        out_dir = os.path.join(REPO, "Sources", "ClaudeCats")
        files = S.convert_files(list(self.inputs))
        on_disk = sorted(
            name for name in os.listdir(out_dir)
            if name.startswith("CatArt.") and name.endswith(".generated.swift")
        )
        self.assertEqual(on_disk, sorted(files))
        for name in sorted(files):
            with open(os.path.join(out_dir, name), encoding="utf-8") as handle:
                self.assertEqual(handle.read(), files[name],
                                 "%s 가 생성기 출력과 다르다 — generate-cat-art.sh 를 돌려라" % name)

    def test_encoded_art_round_trips_to_the_same_commands(self):
        """진짜 그림 전체가 인코딩 → 디코딩을 거쳐도 명령이 그대로여야 한다."""
        for _, _, path in self.inputs:
            with open(path, encoding="utf-8") as f:
                groups = S.parse_svg(f.read())
            for layers in groups.values():
                for layer in layers:
                    self.assertEqual(S.decode_path(S.encode_path(layer.cmds)), layer.cmds)

    def test_top_is_inside_the_box_and_above_the_middle(self):
        for _, _, path in self.inputs:
            with open(path, encoding="utf-8") as f:
                groups = S.parse_svg(f.read())
            box = S.layers_bounds([l for layers in groups.values() for l in layers])
            self.assertGreater(box[3], 20)
            self.assertLessEqual(box[3], 64)

    def test_all_coordinates_in_range(self):
        for _, _, path in self.inputs:
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

    def test_kenji_body_uses_fur_and_fur_dark_placeholders(self):
        """켄지 몸통 주색·음영은 팔레트 플레이스홀더로 치환된다(recolorable)."""
        with open(self.kenji_sitting, encoding="utf-8") as f:
            groups = S.parse_svg(f.read())
        paints = [layer.fill for layer in groups["body"]]
        self.assertIn(S.FUR, paints)
        self.assertIn(S.FUR_DARK, paints)
        # 켄지는 꼬리 프레임이 없다.
        self.assertNotIn("tailA", groups)
        self.assertNotIn("tailB", groups)


if __name__ == "__main__":
    unittest.main()
