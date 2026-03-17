"""Charts renderer parity checks against ASC source geometry semantics.

This suite validates that chart SVG output preserves source FDL framing/protection
geometry and anchor placement for a prioritized scenario set.
"""

from __future__ import annotations

import json
import os
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

import pytest

from fdl_backend.handlers import chart_gen

DEFAULT_ASC_REPO = Path('/Users/dhall/Documents/GitHub/ascmitc/fdl')


@dataclass(frozen=True)
class ChartParityCase:
    name: str
    source_file: str


# Prioritized coverage set: spherical + anamorphic + top-aligned.
PRIORITY_CASES: list[ChartParityCase] = [
    ChartParityCase(name='spherical-center', source_file='B_4448x3096_1x_FramingChart.fdl'),
    ChartParityCase(name='anamorphic-1p3x', source_file='A_4448x3096_1-3x_FramingChart.fdl'),
    ChartParityCase(name='anamorphic-2x', source_file='C_4448x3096_2x_FramingChart.fdl'),
    ChartParityCase(name='top-aligned', source_file='G_5040x3780_1x_TopAligned-FramingChart.fdl'),
]


def _asc_repo_path() -> Path:
    configured = os.environ.get('ASC_FDL_REPO_PATH', '').strip()
    return Path(configured) if configured else DEFAULT_ASC_REPO


def _source_file_path(source_file: str) -> Path:
    return _asc_repo_path() / 'resources' / 'FDL' / 'Original_Source_Files' / source_file


def _parse_svg(path: Path) -> ET.Element:
    return ET.fromstring(path.read_text(encoding='utf-8'))


def _rects_by_stroke(root: ET.Element, stroke_hex: str) -> list[ET.Element]:
    rects: list[ET.Element] = []
    for elem in root.iter():
        if elem.tag.endswith('rect') and elem.attrib.get('stroke') == stroke_hex:
            rects.append(elem)
    return rects


def _svg_float_tuple(text: str) -> tuple[float, float]:
    parts = [p.strip() for p in text.split(',')]
    return float(parts[0]), float(parts[1])


def _extract_primary_source_geometry(doc: dict) -> tuple[dict, dict]:
    canvas = doc['contexts'][0]['canvases'][0]
    fd = canvas['framing_decisions'][0]
    return canvas, fd


def _build_params(canvas: dict, fd: dict) -> dict:
    dims = canvas['dimensions']
    squeeze = float(canvas.get('anamorphic_squeeze', 1.0))
    fd_dims = fd['dimensions']
    fd_anchor = fd.get('anchor_point', {'x': 0, 'y': 0})
    prot_dims = fd.get('protection_dimensions')
    prot_anchor = fd.get('protection_anchor_point')

    frameline: dict[str, object] = {
        'label': fd.get('label', '') or 'FD',
        'width': float(fd_dims['width']),
        'height': float(fd_dims['height']),
        'anchor_x': float(fd_anchor.get('x', 0)),
        'anchor_y': float(fd_anchor.get('y', 0)),
        'color': '#FF3B30',
        'style': 'full_box',
    }
    if prot_dims and prot_anchor:
        frameline['protection_width'] = float(prot_dims['width'])
        frameline['protection_height'] = float(prot_dims['height'])
        frameline['protection_anchor_x'] = float(prot_anchor.get('x', 0))
        frameline['protection_anchor_y'] = float(prot_anchor.get('y', 0))

    return {
        'canvas_width': int(dims['width']),
        'canvas_height': int(dims['height']),
        'framelines': [frameline],
        'title': '',
        'anamorphic_squeeze': squeeze,
        'preview_desqueeze': True,
        'show_labels': False,
        'background_theme': 'white',
        'layers': {
            'canvas': True,
            'effective': False,
            'protection': True,
            'framing': True,
        },
    }


def _adjust_for_stroke(x: float, y: float, w: float, h: float, line_width: float) -> tuple[float, float, float, float]:
    half = max(1, int(round(line_width / 2.0)))
    return x + half, y + half, max(1.0, w - (half * 2)), max(1.0, h - (half * 2))


def _line_widths(canvas_w: float) -> tuple[float, float]:
    svg_ff = max(1.0, canvas_w / 480.0)
    line_minor = max(2.0, 1.0 * svg_ff * 0.4)
    line_major = max(3.0, 2.0 * svg_ff * 0.4)
    return line_minor, line_major


def _expected_rect(fd: dict, squeeze: float, canvas_w: float) -> tuple[float, float, float, float]:
    d = fd['dimensions']
    a = fd.get('anchor_point', {'x': 0, 'y': 0})
    display_x = squeeze if squeeze > 1.0 else 1.0
    x = float(int(float(a.get('x', 0)) * display_x))
    y = float(int(float(a.get('y', 0))))
    w = float(int(float(d['width']) * display_x))
    h = float(int(float(d['height'])))
    _, line_major = _line_widths(canvas_w)
    return _adjust_for_stroke(x, y, w, h, line_major)


def _expected_protection_rect(fd: dict, squeeze: float, canvas_w: float) -> tuple[float, float, float, float] | None:
    d = fd.get('protection_dimensions')
    a = fd.get('protection_anchor_point')
    if not d or not a:
        return None
    display_x = squeeze if squeeze > 1.0 else 1.0
    x = float(int(float(a.get('x', 0)) * display_x))
    y = float(int(float(a.get('y', 0))))
    w = float(int(float(d['width']) * display_x))
    h = float(int(float(d['height'])))
    line_minor, _ = _line_widths(canvas_w)
    return _adjust_for_stroke(x, y, w, h, line_minor)


def _assert_rect_close(rect: ET.Element, expected: tuple[float, float, float, float], tol: float = 1e-3) -> None:
    x, y = _svg_float_tuple(rect.attrib['x'] + ',' + rect.attrib['y'])
    w, h = _svg_float_tuple(rect.attrib['width'] + ',' + rect.attrib['height'])
    ex, ey, ew, eh = expected
    assert abs(x - ex) <= tol
    assert abs(y - ey) <= tol
    assert abs(w - ew) <= tol
    assert abs(h - eh) <= tol


RUN_ASC_CHARTS_PARITY = os.environ.get('RUN_ASC_CHARTS_PARITY', '').lower() in {'1', 'true', 'yes'}


@pytest.mark.skipif(not RUN_ASC_CHARTS_PARITY, reason='Set RUN_ASC_CHARTS_PARITY=1 to enable charts parity checks')
@pytest.mark.parametrize('case', PRIORITY_CASES, ids=[c.name for c in PRIORITY_CASES])
def test_chart_svg_preserves_source_geometry(case: ChartParityCase) -> None:
    src_path = _source_file_path(case.source_file)
    assert src_path.exists(), f'Missing ASC source file: {src_path}'

    doc = json.loads(src_path.read_text(encoding='utf-8'))
    canvas, fd = _extract_primary_source_geometry(doc)
    squeeze = float(canvas.get('anamorphic_squeeze', 1.0))

    params = _build_params(canvas, fd)
    out = chart_gen.generate_svg(params)
    svg_path = Path(out['file_path'])
    assert svg_path.exists()

    root = _parse_svg(svg_path)
    expected_view_w = int(float(canvas['dimensions']['width']) * (squeeze if squeeze > 1.0 else 1.0))
    expected_view_h = int(canvas['dimensions']['height'])
    assert root.attrib.get('viewBox') == f'0,0,{expected_view_w},{expected_view_h}'

    framing_rects = _rects_by_stroke(root, '#FF3B30')
    assert framing_rects, 'Expected framing rect with #FF3B30 stroke'
    _assert_rect_close(framing_rects[0], _expected_rect(fd, squeeze, float(canvas['dimensions']['width'])))

    expected_protection = _expected_protection_rect(fd, squeeze, float(canvas['dimensions']['width']))
    protection_rects = _rects_by_stroke(root, '#FF9500')
    if expected_protection is None:
        assert not protection_rects
    else:
        assert protection_rects, 'Expected protection rect with #FF9500 stroke'
        _assert_rect_close(protection_rects[0], expected_protection)



def _count_svg_strokes(root: ET.Element) -> dict[str, int]:
    counts: dict[str, int] = {}
    for elem in root.iter():
        stroke = elem.attrib.get('stroke')
        if stroke:
            counts[stroke] = counts.get(stroke, 0) + 1
    return counts


def _count_rect_fills(root: ET.Element) -> dict[str, int]:
    fills: dict[str, int] = {}
    for elem in root.iter():
        if elem.tag.endswith('rect'):
            fill = elem.attrib.get('fill')
            if fill:
                fills[fill] = fills.get(fill, 0) + 1
    return fills


def test_chart_svg_extension_layers_preserved() -> None:
    """Preserve FDL Tool-specific visual layers while doing core parity checks."""
    params = {
        'canvas_width': 4608,
        'canvas_height': 3164,
        'title': '',
        'background_theme': 'white',
        'preview_desqueeze': True,
        'show_labels': False,
        'show_boundary_arrows': True,
        'boundary_arrow_scale': 1.0,
        'show_siemens_stars': True,
        'layers': {
            'canvas': True,
            'effective': False,
            'protection': True,
            'framing': True,
        },
        'framelines': [
            {
                'label': 'Main',
                'width': 4608,
                'height': 1928,
                'anchor_x': 0,
                'anchor_y': 618,
                'color': '#FF3B30',
                'protection_width': 4608,
                'protection_height': 2200,
                'protection_anchor_x': 0,
                'protection_anchor_y': 482,
            }
        ],
    }
    out = chart_gen.generate_svg(params)
    root = _parse_svg(Path(out['file_path']))

    # Preserve grayscale/print boundary styling contract.
    fills = _count_rect_fills(root)
    assert fills.get('#AAAAAA', 0) >= 1  # outer chart gray
    assert fills.get('#FFFFFF', 0) >= 1  # canvas white

    # Preserve extension overlays: Siemens stars and boundary arrows.
    path_count = sum(1 for elem in root.iter() if elem.tag.endswith('path'))
    assert path_count >= 16, 'Expected Siemens star path overlays'

    stroke_counts = _count_svg_strokes(root)
    # Frameline box + boundary arrows share the frameline color.
    assert stroke_counts.get('#FF3B30', 0) >= 5



def _first_framing_rect(root: ET.Element) -> ET.Element:
    rects = _rects_by_stroke(root, '#FF3B30')
    assert rects, 'Expected framing rect with #FF3B30 stroke'
    return rects[0]


def _first_protection_rect(root: ET.Element) -> ET.Element | None:
    rects = _rects_by_stroke(root, '#FF9500')
    return rects[0] if rects else None


def _rect_tuple(rect: ET.Element) -> tuple[float, float, float, float]:
    x = float(rect.attrib['x'])
    y = float(rect.attrib['y'])
    w = float(rect.attrib['width'])
    h = float(rect.attrib['height'])
    return (x, y, w, h)


def test_chart_svg_layer_toggle_semantics_independent_of_core_geometry() -> None:
    """Layer toggles must not perturb core framing/protection geometry."""
    base = {
        'canvas_width': 4608,
        'canvas_height': 3164,
        'title': '',
        'background_theme': 'white',
        'preview_desqueeze': True,
        'show_labels': False,
        'show_boundary_arrows': True,
        'show_siemens_stars': True,
        'show_center_marker': True,
        'show_grid': True,
        'layers': {
            'canvas': True,
            'effective': False,
            'protection': True,
            'framing': True,
        },
        'framelines': [
            {
                'label': 'Main',
                'width': 4608,
                'height': 1928,
                'anchor_x': 0,
                'anchor_y': 618,
                'color': '#FF3B30',
                'protection_width': 4608,
                'protection_height': 2200,
                'protection_anchor_x': 0,
                'protection_anchor_y': 482,
            }
        ],
    }

    root_on = _parse_svg(Path(chart_gen.generate_svg(base)['file_path']))
    framing_on = _rect_tuple(_first_framing_rect(root_on))
    prot_on_elem = _first_protection_rect(root_on)
    assert prot_on_elem is not None
    prot_on = _rect_tuple(prot_on_elem)

    toggled = dict(base)
    toggled.update(
        {
            'show_boundary_arrows': False,
            'show_siemens_stars': False,
            'show_center_marker': False,
            'show_grid': False,
        }
    )
    root_off = _parse_svg(Path(chart_gen.generate_svg(toggled)['file_path']))
    framing_off = _rect_tuple(_first_framing_rect(root_off))
    prot_off_elem = _first_protection_rect(root_off)
    assert prot_off_elem is not None
    prot_off = _rect_tuple(prot_off_elem)

    # Core geometry must remain identical with extension layers toggled.
    assert framing_on == framing_off
    assert prot_on == prot_off

    # Extension overlays should materially change.
    strokes_on = _count_svg_strokes(root_on)
    strokes_off = _count_svg_strokes(root_off)
    assert strokes_on.get('#FF3B30', 0) > strokes_off.get('#FF3B30', 0)

    paths_on = sum(1 for e in root_on.iter() if e.tag.endswith('path'))
    paths_off = sum(1 for e in root_off.iter() if e.tag.endswith('path'))
    assert paths_on > paths_off
