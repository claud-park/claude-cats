"""import-cat-svg 검증. 실행: python3 -m unittest scripts/test_import_cat_svg.py"""

import importlib.util
import os
import re
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import svg2swift as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 파일 이름에 하이픈이 있어 일반 import 가 안 된다.
_SPEC = importlib.util.spec_from_file_location(
    "import_cat_svg", os.path.join(REPO, "scripts", "import-cat-svg.py"))
I = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(I)

# 꼬리·몸통으로 쓰는 100×200 사각 경로. bbox 는 (100, 100)~(200, 300).
BOXY = "M 100 100 L 200 100 L 200 300 L 100 300 Z"


def frame(body, view_box="0 0 775 775"):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s" fill="none">%s</svg>'
            % (view_box, body))


def args(**over):
    """기본 플래그 + 덮어쓸 값. argparse 는 뒤에 온 값을 쓴다."""
    argv = ["src.svg", "--pose", over.pop("pose", "sitting"), "--out", "out.svg",
            "--fur", "#7D6C62", "--fur-dark", "#66584F", "--fur-light", "#A09084"]
    for key, value in over.items():
        argv.extend(["--" + key.replace("_", "-"), str(value)])
    return I.build_arguments(argv)


def convert(body, **over):
    return I.convert(frame(body), args(**over))


def groups_of(svg_text):
    """출력 SVG → {id: [도형 엘리먼트]} (문서 순서)."""
    out = {}
    for child in ET.fromstring(svg_text):
        if S.local_name(child.tag) == "g":
            out[child.get("id")] = [e for e in child.iter()
                                    if S.local_name(e.tag) in S.SHAPE_TAGS]
    return out


def group_ids(svg_text):
    return [child.get("id") for child in ET.fromstring(svg_text)
            if S.local_name(child.tag) == "g"]


# ---------------------------------------------------------------- 상자 맞추기


class FitTests(unittest.TestCase):
    def test_rect_is_scaled_centered_and_bottom_aligned(self):
        """775 프레임 안의 100×50 사각형 → 폭 60, 바닥 62, 가로 가운데."""
        svg, _ = convert('<rect x="300" y="400" width="100" height="50" fill="#123456"/>',
                         pose="sleeping")
        min_x, min_y, max_x, max_y = S.layers_bounds(S.parse_svg(svg)["body"])
        self.assertAlmostEqual(max_x - min_x, 60.0, places=3)
        self.assertAlmostEqual(max_y - min_y, 30.0, places=3)
        self.assertAlmostEqual(min_x, 2.0, places=3)      # 가운데 정렬 → 좌우 여백 2
        self.assertAlmostEqual(max_x, 62.0, places=3)
        self.assertAlmostEqual(min_y, 2.0, places=3)      # AppKit y 2 = SVG y 62 (바닥)

    def test_taller_than_wide_fits_by_height(self):
        svg, _ = convert('<rect x="0" y="0" width="50" height="100" fill="#123456"/>',
                         pose="sleeping")
        min_x, min_y, max_x, max_y = S.layers_bounds(S.parse_svg(svg)["body"])
        self.assertAlmostEqual(max_y - min_y, 60.0, places=3)
        self.assertAlmostEqual(max_x - min_x, 30.0, places=3)
        self.assertAlmostEqual((min_x + max_x) / 2, 32.0, places=3)

    def test_pad_changes_the_margin(self):
        svg, _ = convert('<rect x="0" y="0" width="100" height="100" fill="#123456"/>',
                         pose="sleeping", pad=6)
        min_x, min_y, max_x, _ = S.layers_bounds(S.parse_svg(svg)["body"])
        self.assertAlmostEqual(max_x - min_x, 52.0, places=3)
        self.assertAlmostEqual(min_y, 6.0, places=3)

    def test_curves_count_towards_the_bbox(self):
        """제어점이 아니라 곡선의 실제 극값으로 재야 위아래가 딱 맞는다."""
        svg, _ = convert('<path d="M0 0 C0 100 100 100 100 0" fill="#123456"/>',
                         pose="sleeping")
        min_x, min_y, max_x, max_y = S.layers_bounds(S.parse_svg(svg)["body"])
        self.assertAlmostEqual(max_x - min_x, 60.0, places=3)   # 폭 100 이 60 으로
        self.assertAlmostEqual(max_y - min_y, 45.0, places=3)   # 높이 75(=100×0.75) → 45

    def test_output_view_box_is_64(self):
        svg, _ = convert('<rect x="0" y="0" width="10" height="10" fill="#123456"/>',
                         pose="sleeping")
        self.assertEqual(ET.fromstring(svg).get("viewBox"), "0 0 64 64")


# ---------------------------------------------------------------- 색


class ColorTests(unittest.TestCase):
    def test_three_fur_colors_become_placeholders(self):
        svg, _ = convert('<path d="%s" fill="#7d6c62"/>'
                         '<path d="M0 0 L1 1" fill="#66584F"/>'
                         '<path d="M0 0 L2 2" fill="#a09084"/>' % BOXY, pose="sleeping")
        self.assertIn('fill="#FUR"', svg)
        self.assertIn('fill="#FURDARK"', svg)
        self.assertIn('fill="#FURLIGHT"', svg)

    def test_shorthand_and_case_are_matched(self):
        svg, _ = convert('<path d="%s" fill="#FFF" stroke="#7d6c62" stroke-width="4"/>' % BOXY,
                         pose="sleeping", fur="#ffffff", fur_dark="#7D6C62")
        self.assertIn('fill="#FUR"', svg)
        self.assertIn('stroke="#FURDARK"', svg)

    def test_other_colors_survive_untouched(self):
        svg, _ = convert('<path d="%s" fill="#9FBA65"/>' % BOXY, pose="sleeping")
        self.assertIn('fill="#9FBA65"', svg)

    def test_named_color_is_kept(self):
        svg, _ = convert('<path d="%s" fill="white"/>' % BOXY, pose="sleeping")
        self.assertIn('fill="white"', svg)

    def test_clip_rule_is_dropped_and_fill_rule_kept(self):
        svg, _ = convert('<path d="%s" fill="#7D6C62" fill-rule="evenodd" clip-rule="evenodd"/>'
                         % BOXY, pose="sleeping")
        self.assertIn('fill-rule="evenodd"', svg)
        self.assertNotIn("clip-rule", svg)


# ---------------------------------------------------------------- Figma 껍데기


class FigmaWrapperTests(unittest.TestCase):
    def test_full_frame_background_rect_is_dropped(self):
        svg, info = convert('<rect width="775" height="775" fill="white"/>'
                            '<path d="%s" fill="#7D6C62"/>' % BOXY, pose="sleeping")
        self.assertEqual(info["body"], 1)
        self.assertEqual(len(groups_of(svg)["body"]), 1)
        self.assertNotIn('width="775"', svg)

    def test_full_frame_clip_group_is_unwrapped(self):
        svg, info = convert(
            '<g clip-path="url(#c0)"><path d="%s" fill="#7D6C62"/>'
            '<path d="M0 0 L1 1" fill="white"/></g>'
            '<defs><clipPath id="c0"><rect width="775" height="775" fill="white"/></clipPath></defs>'
            % BOXY, pose="sleeping")
        self.assertEqual(group_ids(svg), ["body"])
        self.assertEqual(info["body"], 2)          # 자식 둘이 순서대로 살아남는다
        self.assertNotIn("clip-path", svg)

    def test_non_rect_clip_aborts(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<g clip-path="url(#c0)"><path d="%s" fill="#7D6C62"/></g>'
                    '<defs><clipPath id="c0"><path d="M0 0 L1 1"/></clipPath></defs>' % BOXY,
                    pose="sleeping")
        self.assertIn("clip-path", str(ctx.exception))

    def test_partial_rect_clip_aborts(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<g clip-path="url(#c0)"><path d="%s" fill="#7D6C62"/></g>'
                    '<defs><clipPath id="c0"><rect width="100" height="100"/></clipPath></defs>'
                    % BOXY, pose="sleeping")
        self.assertIn("clip-path", str(ctx.exception))

    def test_gradient_paint_aborts(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<defs><linearGradient id="g"/></defs>'
                    '<path d="%s" fill="url(#g)"/>' % BOXY, pose="sleeping")
        self.assertIn("url", str(ctx.exception))

    def test_text_element_aborts(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<path d="%s" fill="#7D6C62"/><text x="0" y="0">냥</text>' % BOXY,
                    pose="sleeping")
        self.assertIn("text", str(ctx.exception))

    def test_mask_attribute_aborts(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<path d="%s" fill="#7D6C62" mask="url(#m)"/>' % BOXY, pose="sleeping")
        self.assertIn("mask", str(ctx.exception))

    def test_group_transform_is_baked_into_the_shape(self):
        svg, _ = convert('<g transform="translate(100 0)"><path d="%s" fill="#7D6C62"/></g>' % BOXY,
                         pose="sleeping")
        self.assertIn("matrix(1 0 0 1 100 0)", svg)


# ---------------------------------------------------------------- 꼬리


class TailTests(unittest.TestCase):
    def test_tail_paths_makes_tail_a_and_a_rotated_tail_b(self):
        svg, info = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                            '<path d="%s" fill="#7D6C62"/>' % BOXY, tail_paths="2")
        self.assertTrue(info["synthesizedTailB"])
        self.assertEqual((info["body"], info["tailA"], info["tailB"]), (1, 1, 1))
        # 회전 중심은 꼬리 bbox 의 (minX, maxY) — 꼬리가 몸에 닿는 자리다.
        self.assertIn('transform="rotate(-8 100 300)"', svg)
        self.assertEqual(len(groups_of(svg)["tail-b"]), 1)

    def test_tail_angle_and_pivot_flags(self):
        svg, _ = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                         '<path d="%s" fill="#7D6C62"/>' % BOXY,
                         tail_paths="2", tail_angle=-15, tail_pivot="1,2")
        self.assertIn('transform="rotate(-15 1 2)"', svg)

    def test_multiple_tail_paths(self):
        _, info = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                          '<path d="%s" fill="#7D6C62"/>'
                          '<path d="M120 120 L180 120 L180 160 Z" fill="#66584F"/>' % BOXY,
                          tail_paths="2,3")
        self.assertEqual((info["body"], info["tailA"], info["tailB"]), (1, 2, 2))

    def test_bad_tail_paths_abort(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<path d="%s" fill="#7D6C62"/>' % BOXY, tail_paths="9")
        self.assertIn("--tail-paths", str(ctx.exception))

    def test_tail_a_group_id_is_honored_without_flags(self):
        svg, info = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                            '<g id="tail-a"><path d="%s" fill="#7D6C62"/></g>' % BOXY)
        self.assertEqual(info["tailA"], 1)
        self.assertTrue(info["synthesizedTailB"])
        self.assertIn("rotate(", svg)

    def test_tail_a_path_and_tail_b_group_are_used_verbatim(self):
        svg, info = convert(
            '<path d="M0 0 L1 1" fill="#F6EEE7"/>'
            '<path id="tail-a" d="%s" fill="#7D6C62"/>'
            '<g id="tail-b"><path d="M110 110 L190 110 L190 290 Z" fill="#7D6C62"/>'
            '<path d="M120 200 L180 200 L180 280 Z" fill="#66584F"/></g>' % BOXY)
        self.assertFalse(info["synthesizedTailB"])
        self.assertEqual((info["tailA"], info["tailB"]), (1, 2))
        self.assertNotIn("rotate(", svg)
        self.assertEqual(len(groups_of(svg)["tail-b"]), 2)

    def test_tail_paths_ignored_when_ids_are_present(self):
        _, info = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                          '<g id="tail-a"><path d="%s" fill="#7D6C62"/></g>' % BOXY,
                          tail_paths="1")
        self.assertEqual((info["body"], info["tailA"]), (1, 1))

    def test_sitting_without_any_tail_aborts(self):
        with self.assertRaises(SystemExit) as ctx:
            convert('<path d="%s" fill="#7D6C62"/>' % BOXY)
        self.assertIn("tail-a", str(ctx.exception))

    def test_synthesized_tail_b_stays_inside_the_box(self):
        svg, _ = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                         '<path d="%s" fill="#7D6C62"/>' % BOXY, tail_paths="2")
        for layers in S.parse_svg(svg).values():
            for layer in layers:
                for cmd in layer.cmds:
                    for value in cmd[1:]:
                        self.assertGreaterEqual(value, 0)
                        self.assertLessEqual(value, 64)


class TailOrderTests(unittest.TestCase):
    def test_tail_after_the_biggest_body_path_goes_above(self):
        svg, info = convert('<path d="%s" fill="#F6EEE7"/>'
                            '<path id="tail-a" d="M300 300 L320 300 L320 340 Z" fill="#7D6C62"/>'
                            % BOXY)
        self.assertTrue(info["tailAboveBody"])
        self.assertEqual(group_ids(svg), ["body", "tail-a", "tail-b"])

    def test_tail_before_the_biggest_body_path_goes_below(self):
        svg, info = convert('<path id="tail-a" d="M300 300 L320 300 L320 340 Z" fill="#7D6C62"/>'
                            '<path d="%s" fill="#F6EEE7"/>' % BOXY)
        self.assertFalse(info["tailAboveBody"])
        self.assertEqual(group_ids(svg), ["tail-a", "tail-b", "body"])

    def test_converter_reads_the_same_order_back(self):
        svg, info = convert('<path d="%s" fill="#F6EEE7"/>'
                            '<path id="tail-a" d="M300 300 L320 300 L320 340 Z" fill="#7D6C62"/>'
                            % BOXY)
        _, above = S.parse_svg(svg, want_order=True)
        self.assertEqual(above, info["tailAboveBody"])


class SleepingTests(unittest.TestCase):
    def test_tail_a_folds_into_body_and_tail_b_is_dropped(self):
        svg, info = convert('<path d="%s" fill="#F6EEE7"/>'
                            '<path id="tail-b" d="M110 110 L120 120 L120 110 Z" fill="#7D6C62"/>'
                            '<path id="tail-a" d="M130 130 L140 140 L140 130 Z" fill="#7D6C62"/>'
                            % BOXY, pose="sleeping")
        self.assertEqual(group_ids(svg), ["body"])
        self.assertEqual((info["body"], info["tailA"], info["tailB"]), (2, 0, 0))
        self.assertIn("M130 130", svg)      # tail-a 는 문서 위치 그대로 몸통에 남는다
        self.assertNotIn("M110 110", svg)   # tail-b 는 쓰이지 않으므로 버린다

    def test_sleeping_without_tails_is_fine(self):
        svg, info = convert('<path d="%s" fill="#7D6C62"/>' % BOXY, pose="sleeping")
        self.assertEqual(group_ids(svg), ["body"])
        self.assertEqual(info["body"], 1)


class IdTests(unittest.TestCase):
    def test_body_id_on_a_path_is_not_special(self):
        """Figma 레이어 이름이 'body' 여도 그냥 몸통 도형 하나일 뿐이다."""
        svg, info = convert('<path id="body" d="%s" fill="#F6EEE7"/>'
                            '<path id="tail-a" d="M300 300 L320 340 L320 300 Z" fill="#7D6C62"/>'
                            % BOXY)
        self.assertEqual(info["body"], 1)
        self.assertEqual(group_ids(svg), ["body", "tail-a", "tail-b"])
        self.assertEqual(len(groups_of(svg)["body"]), 1)

    def test_other_ids_do_not_split_the_body(self):
        svg, info = convert('<g id="Vector"><path d="%s" fill="#F6EEE7"/>'
                            '<path d="M0 0 L1 1" fill="white"/></g>'
                            '<path id="Vector_3" d="M2 2 L3 3" fill="#66584F"/>'
                            '<path id="tail-a" d="M300 300 L320 340 L320 300 Z" fill="#7D6C62"/>'
                            % BOXY)
        self.assertEqual(info["body"], 3)
        self.assertEqual(len(groups_of(svg)["body"]), 3)

    def test_ids_are_not_carried_into_the_output_shapes(self):
        svg, _ = convert('<path id="Vector_9" d="%s" fill="#7D6C62"/>' % BOXY, pose="sleeping")
        self.assertNotIn("Vector_9", svg)


# ---------------------------------------------------------------- stroke


class StrokeTests(unittest.TestCase):
    def test_same_color_fill_and_stroke_drops_the_stroke(self):
        svg, _ = convert('<path d="%s" fill="#7D6C62" stroke="#7d6c62" stroke-width="0.25" '
                         'stroke-linejoin="round"/>' % BOXY, pose="sleeping")
        self.assertIn('fill="#FUR"', svg)
        self.assertNotIn("stroke", svg)

    def test_stroke_only_hairline_is_widened(self):
        """0.25 짜리 헤어라인은 축소하면 0.02pt 라 사라진다. 최소 0.6pt 로 키운다."""
        svg, info = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                            '<path d="%s" stroke="#66584F" stroke-width="0.25"/>' % BOXY,
                            pose="sleeping")
        width = float(re.search(r'stroke-width="([\d.]+)"', svg).group(1))
        self.assertAlmostEqual(width * info["scale"], 0.6, places=3)

    def test_thick_stroke_is_left_alone(self):
        svg, info = convert('<path d="M0 0 L1 1" fill="#F6EEE7"/>'
                            '<path d="%s" stroke="#66584F" stroke-width="40"/>' % BOXY,
                            pose="sleeping")
        width = float(re.search(r'stroke-width="([\d.]+)"', svg).group(1))
        self.assertAlmostEqual(width, 40.0, places=3)

    def test_different_color_stroke_survives(self):
        svg, _ = convert('<path d="%s" fill="#F6EEE7" stroke="#66584F" stroke-width="4"/>' % BOXY,
                         pose="sleeping")
        self.assertIn('stroke="#FURDARK"', svg)
        self.assertIn('stroke-width="4"', svg)

    def test_figma_stroke_twin_of_the_same_color_is_dropped(self):
        """Figma 는 한 도형의 fill 과 stroke 를 자리가 같은 path 두 벌로 내보낸다."""
        svg, info = convert('<path d="%s" fill="#7D6C62"/>'
                            '<path d="%s" stroke="#7D6C62" stroke-width="0.25"/>' % (BOXY, BOXY),
                            pose="sleeping")
        self.assertEqual(info["droppedStrokeTwins"], 1)
        self.assertEqual(info["body"], 1)
        self.assertNotIn("stroke", svg)

    def test_stroke_twin_of_a_run_of_fills_is_dropped(self):
        svg, info = convert('<path d="M0 0 L10 0 L10 10 Z" fill="white"/>'
                            '<path d="M20 0 L30 0 L30 10 Z" fill="white"/>'
                            '<path d="M0 0 L30 0 L30 10 L0 10 Z" stroke="white" '
                            'stroke-width="0.25"/>', pose="sleeping")
        self.assertEqual(info["droppedStrokeTwins"], 1)
        self.assertEqual(info["body"], 2)
        self.assertNotIn("stroke", svg)

    def test_outline_of_a_different_colored_shape_keeps_its_width(self):
        """눈 테두리처럼 다른 색 외곽선은 작가가 정한 두께를 그대로 둔다(굵히지 않는다)."""
        svg, info = convert('<path d="%s" fill="#9FBA65"/>'
                            '<path d="%s" stroke="#E9BEAF" stroke-width="0.25"/>' % (BOXY, BOXY),
                            pose="sleeping")
        self.assertEqual(info["droppedStrokeTwins"], 0)
        self.assertIn('stroke-width="0.25"', svg)

    def test_line_join_and_cap_survive(self):
        svg, _ = convert('<path d="%s" stroke="#66584F" stroke-width="4" '
                         'stroke-linejoin="round" stroke-linecap="square"/>' % BOXY,
                         pose="sleeping")
        self.assertIn('stroke-linejoin="round"', svg)
        self.assertIn('stroke-linecap="square"', svg)


# ---------------------------------------------------------------- 실제 파일


class RealSourceTests(unittest.TestCase):
    def setUp(self):
        self.sources = {
            "sitting": os.path.join(REPO, "Design", "cats", "source", "sitting-figma.svg"),
            "sleeping": os.path.join(REPO, "Design", "cats", "source", "sleeping-figma.svg"),
        }
        for path in self.sources.values():
            if not os.path.exists(path):
                self.skipTest("원본 Figma SVG 가 없다: %s" % path)

    def run_pose(self, pose):
        options = args(pose=pose)
        options.source = self.sources[pose]     # 헤더 주석에 원본 파일 이름이 들어간다
        with open(options.source, encoding="utf-8") as handle:
            return I.convert(handle.read(), options)

    def test_sitting_round_trips_through_the_converter(self):
        svg, info = self.run_pose("sitting")
        groups, above = S.parse_svg(svg, want_order=True)
        self.assertEqual(set(groups), {"body", "tailA", "tailB"})
        self.assertTrue(above)
        self.assertTrue(info["tailAboveBody"])
        self.assertFalse(info["synthesizedTailB"])   # 사용자가 tail-b 를 직접 그렸다

    def test_sleeping_round_trips_through_the_converter(self):
        svg, info = self.run_pose("sleeping")
        self.assertEqual(set(S.parse_svg(svg)), {"body"})
        self.assertEqual((info["tailA"], info["tailB"]), (0, 0))

    def test_both_stay_inside_the_box(self):
        for pose in ("sitting", "sleeping"):
            svg, _ = self.run_pose(pose)
            for layers in S.parse_svg(svg).values():
                for layer in layers:
                    for cmd in layer.cmds:
                        for value in cmd[1:]:
                            self.assertGreaterEqual(value, -4, pose)
                            self.assertLessEqual(value, 68, pose)

    def test_fur_placeholder_is_present(self):
        """#FUR 은 주 털색이라 반드시 나온다. FURDARK/FURLIGHT 는 원본이 쓸 때만 나온다."""
        for pose in ("sitting", "sleeping"):
            svg, _ = self.run_pose(pose)
            self.assertIn('"#FUR"', svg, pose)

    def test_generated_files_match_the_checked_in_art(self):
        """Design/cats/*.svg 는 이 스크립트의 출력이다. 손으로 고치면 여기서 걸린다."""
        for pose in ("sitting", "sleeping"):
            svg, _ = self.run_pose(pose)
            with open(os.path.join(REPO, "Design", "cats", "%s.svg" % pose),
                      encoding="utf-8") as handle:
                self.assertEqual(handle.read(), svg, pose)


if __name__ == "__main__":
    unittest.main()
