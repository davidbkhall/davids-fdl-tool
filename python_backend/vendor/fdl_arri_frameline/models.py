"""Data models for ARRI Frame Line Tool (FLT) XML files.

The FLT exports XML v2.2 where each frameline box is represented as
four individual ``<line>`` elements (top, bottom, left, right) grouped
by a ``framelineRect`` attribute (``"formatA"``, ``"formatB"``, etc.).

Example (abbreviated)::

    <framelines version='2.2'>
      <camera>
        <aspect>1.46</aspect>
      </camera>
      <framelineName framelineRect="formatA">2.39:1</framelineName>
      <framelineScaling framelineRect="formatA">100</framelineScaling>
      <!-- Top Line -->
      <line framelineRect="formatA">
        <top>0.256</top>
        <left>0.100</left>
        <right>0.100</right>
        <width>4</width>
      </line>
      <!-- Bottom Line -->
      <line framelineRect="formatA">
        <bottom>0.256</bottom>
        <left>0.100</left>
        <right>0.100</right>
        <width>4</width>
      </line>
      <!-- Left Line -->
      <line framelineRect="formatA">
        <top>0.256</top>
        <bottom>0.256</bottom>
        <left>0.100</left>
        <width>4</width>
      </line>
      <!-- Right Line -->
      <line framelineRect="formatA">
        <top>0.256</top>
        <bottom>0.256</bottom>
        <right>0.100</right>
        <width>4</width>
      </line>
      <centerMarker>
        <left>0.5</left>
        <top>0.5</top>
        <width>4</width>
      </centerMarker>
    </framelines>

Coordinates are normalised inset distances from each edge (0.0 = edge,
0.5 = centre).
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class FramelineBox:
    """A single frameline rectangle derived from four ``<line>`` elements.

    Coordinates are normalised inset distances from each edge of the
    sensor area.
    """

    format_id: str = "formatA"
    name: str = ""
    scaling: float = 100.0
    left: float = 0.0
    right: float = 0.0
    top: float = 0.0
    bottom: float = 0.0
    line_width: int = 4
    line_color: str = ""

    @property
    def width_fraction(self) -> float:
        """Fraction of horizontal resolution covered by the box."""
        return max(0.0, 1.0 - self.left - self.right)

    @property
    def height_fraction(self) -> float:
        """Fraction of vertical resolution covered by the box."""
        return max(0.0, 1.0 - self.top - self.bottom)


@dataclass
class CenterMarker:
    left: float = 0.5
    top: float = 0.5
    width: int = 4
    style: str = "none"


@dataclass
class Surround:
    opacity: float = 0.0


@dataclass
class CameraInfo:
    aspect: float = 0.0
    camera_type: str = ""
    sensor_mode: str = ""
    hres: int = 0
    vres: int = 0
    lens_squeeze: float = 1.0


@dataclass
class ArriFrameline:
    """Root model for an ARRI FLT frameline XML file."""

    version: str = "2.2"
    camera: CameraInfo = field(default_factory=CameraInfo)
    boxes: list[FramelineBox] = field(default_factory=list)
    center_marker: CenterMarker | None = None
    surround: Surround | None = None


# ---------------------------------------------------------------------------
# XML serialisation
# ---------------------------------------------------------------------------


def write_xml(frameline: ArriFrameline, path: str | Path) -> None:
    """Serialise an ArriFrameline to an XML file."""
    root = to_xml_element(frameline)
    tree = ET.ElementTree(root)
    ET.indent(tree, space="\t")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(str(path), encoding="UTF-8", xml_declaration=True)
    with open(path, "a") as fh:
        fh.write("\n")


def to_xml_string(frameline: ArriFrameline) -> str:
    """Serialise an ArriFrameline to an XML string."""
    root = to_xml_element(frameline)
    ET.indent(root, space="\t")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode")


def _fmt(value: float) -> str:
    """Format a normalised coordinate with full precision."""
    return f"{value}"


def _sub(parent: ET.Element, tag: str, text: str, **attribs: str) -> ET.Element:
    el = ET.SubElement(parent, tag, **attribs)
    el.text = text
    return el


def _is_old_format(frameline: ArriFrameline) -> bool:
    """Old format: no version attr, rich <camera>, <surround>, <color>."""
    return not frameline.version


def to_xml_element(frameline: ArriFrameline) -> ET.Element:
    """Build an ElementTree Element from an ArriFrameline.

    Emits the correct XML variant based on ``frameline.version``:

    * ``""`` (empty) -- old format (ALEXA LF / Mini LF): ``<camera>``
      includes ``<type>``, ``<sensor>``, ``<hres>``, ``<vres>``;
      ``<surround>`` block; ``<color>`` inside lines; no
      ``<framelineScaling>``.
    * ``"2.1"`` -- ALEXA 35 <= SUP 1.1: ``<camera>`` has ``<aspect>``
      only; ``<framelineScaling>`` is commented out.
    * ``"2.2"`` -- ALEXA 35 >= SUP 1.2 / Xtreme: ``<camera>`` has
      ``<aspect>`` only; ``<framelineScaling>`` present.
    """
    attribs: dict[str, str] = {}
    if frameline.version:
        attribs["version"] = frameline.version
    root = ET.Element("framelines", **attribs)

    cam = frameline.camera
    old = _is_old_format(frameline)

    # --- <camera> block ---
    cam_el = ET.SubElement(root, "camera")
    if old:
        if cam.camera_type:
            _sub(cam_el, "type", cam.camera_type)
        if cam.sensor_mode:
            _sub(cam_el, "sensor", cam.sensor_mode)
        _sub(cam_el, "aspect", f"{cam.aspect:.2f}")
        if cam.hres:
            _sub(cam_el, "hres", str(cam.hres))
        if cam.vres:
            _sub(cam_el, "vres", str(cam.vres))
    else:
        _sub(cam_el, "aspect", f"{cam.aspect:.2f}")

    # --- <surround> (old format only) ---
    if old and frameline.surround is not None:
        sur_el = ET.SubElement(root, "surround")
        _sub(sur_el, "opacity", str(int(frameline.surround.opacity)))

    # --- frameline boxes ---
    for box in frameline.boxes:
        fid = box.format_id

        _sub(root, "framelineName", box.name, framelineRect=fid)

        if frameline.version == "2.2":
            _sub(root, "framelineScaling", f"{box.scaling:.15f}", framelineRect=fid)

        color = box.line_color if old and box.line_color else ""

        def _write_line(parent: ET.Element, **coords: str) -> None:
            line_el = ET.SubElement(parent, "line", framelineRect=fid)
            for tag, val in coords.items():
                _sub(line_el, tag, val)
            _sub(line_el, "width", str(box.line_width))
            if color:
                _sub(line_el, "color", color)

        _write_line(root, top=_fmt(box.top), left=_fmt(box.left), right=_fmt(box.right))
        _write_line(root, bottom=_fmt(box.bottom), left=_fmt(box.left), right=_fmt(box.right))
        _write_line(root, top=_fmt(box.top), bottom=_fmt(box.bottom), left=_fmt(box.left))
        _write_line(root, top=_fmt(box.top), bottom=_fmt(box.bottom), right=_fmt(box.right))

    # --- center marker (v2.1 / v2.2 only) ---
    if frameline.center_marker and not old:
        cm = frameline.center_marker
        cm_el = ET.SubElement(root, "centerMarker")
        _sub(cm_el, "left", _fmt(cm.left))
        _sub(cm_el, "top", _fmt(cm.top))
        _sub(cm_el, "width", str(cm.width))

    return root


# ---------------------------------------------------------------------------
# XML parsing
# ---------------------------------------------------------------------------


def read_xml(path: str | Path) -> ArriFrameline:
    """Parse an ARRI FLT frameline XML file into an ArriFrameline model."""
    path = Path(path)
    raw = path.read_text(encoding="utf-8")
    return from_xml_string(raw)


def from_xml_string(xml_str: str) -> ArriFrameline:
    """Parse an ARRI FLT frameline XML string into an ArriFrameline model."""
    metadata = _parse_comment_metadata(xml_str)
    root = ET.fromstring(xml_str)
    return _from_xml_element(root, metadata)


def _text(parent: ET.Element, tag: str, default: str = "") -> str:
    el = parent.find(tag)
    if el is not None and el.text:
        return el.text.strip()
    return default


def _parse_comment_metadata(xml_str: str) -> dict[str, str]:
    """Extract key-value metadata from the XML comment block."""
    result: dict[str, str] = {}
    for m in re.finditer(r"<!--(.*?)-->", xml_str, re.DOTALL):
        block = m.group(1)
        for line in block.splitlines():
            if ":" in line and "+++" not in line:
                key, _, val = line.partition(":")
                key = key.strip().lower()
                val = val.strip()
                if key and val:
                    result[key] = val
    return result


_HRES_KEYS = (
    "recording file active image pixel h",
    "sensor active image dimension photosites h",
    "active sensor pixel h",
    "clip resolution h",
    "sensor photosites h",
)
_VRES_KEYS = (
    "recording file active image pixel v",
    "sensor active image dimension photosites v",
    "active sensor pixel v",
    "clip resolution v",
    "sensor photosites v",
)


def _from_xml_element(root: ET.Element, metadata: dict[str, str]) -> ArriFrameline:
    """Build an ArriFrameline from a parsed XML Element + comment metadata."""
    version = root.get("version", "")

    camera = CameraInfo()
    cam_el = root.find("camera")
    if cam_el is not None:
        camera.aspect = float(_text(cam_el, "aspect", "0"))
        xml_type = _text(cam_el, "type")
        xml_hres = _text(cam_el, "hres")
        xml_vres = _text(cam_el, "vres")
        xml_sensor = _text(cam_el, "sensor")
        if xml_type:
            camera.camera_type = xml_type
        if xml_hres:
            camera.hres = int(xml_hres)
        if xml_vres:
            camera.vres = int(xml_vres)
        if xml_sensor:
            camera.sensor_mode = xml_sensor

    if not camera.camera_type:
        camera.camera_type = metadata.get("camera model", "")
    if not camera.sensor_mode:
        camera.sensor_mode = metadata.get("sensor mode", "")
    if not camera.hres:
        for k in _HRES_KEYS:
            if k in metadata:
                camera.hres = int(metadata[k])
                break
    if not camera.vres:
        for k in _VRES_KEYS:
            if k in metadata:
                camera.vres = int(metadata[k])
                break
    squeeze_raw = metadata.get("lens squeeze factor", "")
    if squeeze_raw:
        camera.lens_squeeze = float(squeeze_raw.replace("x", "").strip())

    # Collect lines grouped by framelineRect
    line_groups: dict[str, list[ET.Element]] = {}
    for line_el in root.findall("line"):
        fid = line_el.get("framelineRect", "formatA")
        line_groups.setdefault(fid, []).append(line_el)

    # Collect names and scaling per format
    names: dict[str, str] = {}
    for el in root.findall("framelineName"):
        fid = el.get("framelineRect", "formatA")
        names[fid] = (el.text or "").strip()

    scalings: dict[str, float] = {}
    for el in root.findall("framelineScaling"):
        fid = el.get("framelineRect", "formatA")
        scalings[fid] = float((el.text or "100").strip())

    boxes: list[FramelineBox] = []
    for fid, lines in line_groups.items():
        box = _lines_to_box(fid, lines)
        box.name = names.get(fid, "")
        box.scaling = scalings.get(fid, 100.0)
        boxes.append(box)

    center_marker = None
    cm_el = root.find("centerMarker")
    if cm_el is not None:
        center_marker = CenterMarker(
            left=float(_text(cm_el, "left", "0.5")),
            top=float(_text(cm_el, "top", "0.5")),
            width=int(_text(cm_el, "width", "4")),
        )

    surround = None
    sur_el = root.find("surround")
    if sur_el is not None:
        surround = Surround(
            opacity=float(_text(sur_el, "opacity", "0")),
        )

    return ArriFrameline(
        version=version,
        camera=camera,
        boxes=boxes,
        center_marker=center_marker,
        surround=surround,
    )


def _lines_to_box(format_id: str, lines: list[ET.Element]) -> FramelineBox:
    """Reconstruct a FramelineBox from the four <line> elements of a format."""
    top = 0.0
    bottom = 0.0
    left = 0.0
    right = 0.0
    line_width = 4
    line_color = ""

    for line_el in lines:
        t = _text(line_el, "top")
        b = _text(line_el, "bottom")
        le = _text(line_el, "left")
        r = _text(line_el, "right")
        w = _text(line_el, "width")
        c = _text(line_el, "color")

        if w:
            line_width = int(w)
        if c and not line_color:
            line_color = c

        # Top line: has <top>, <left>, <right> but no <bottom>
        if t and le and r and not b:
            top = float(t)
            left = float(le)
            right = float(r)
        # Bottom line: has <bottom>, <left>, <right> but no <top>
        elif b and le and r and not t:
            bottom = float(b)
        # Left line: has <top>, <bottom>, <left> but no <right>
        elif t and b and le and not r:
            left = float(le)
        # Right line: has <top>, <bottom>, <right> but no <left>
        elif t and b and r and not le:
            right = float(r)

    return FramelineBox(
        format_id=format_id,
        left=left,
        right=right,
        top=top,
        bottom=bottom,
        line_width=line_width,
        line_color=line_color,
    )
