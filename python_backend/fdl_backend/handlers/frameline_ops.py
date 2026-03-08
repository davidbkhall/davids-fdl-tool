"""Manufacturer frameline conversion handlers (ARRI / Sony).

These handlers are designed for app bundling:
- prefer installed packages
- then bundled vendor modules in ``python_backend/vendor``
- then optional explicit env-var paths
"""

from __future__ import annotations

import importlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from fdl_backend.utils.fdl_convert import fdl_to_dict

PY_BACKEND_ROOT = Path(__file__).resolve().parents[2]
VENDOR_ROOT = PY_BACKEND_ROOT / "vendor"


def _add_sys_path_if_exists(path: str | Path) -> None:
    path = str(path)
    if path and os.path.isdir(path) and path not in sys.path:
        sys.path.insert(0, path)


def _env_paths(var_name: str) -> list[str]:
    raw = os.environ.get(var_name, "")
    if not raw:
        return []
    return [part for part in raw.split(os.pathsep) if part]


def _candidate_paths(vendor_subdir: str, env_var: str) -> list[str | Path]:
    candidates: list[str | Path] = []
    candidates.extend(_env_paths(env_var))
    candidates.append(VENDOR_ROOT)
    candidates.append(VENDOR_ROOT / vendor_subdir)
    return candidates


def _load_module(module_name: str, vendor_subdir: str, env_var: str) -> Any:
    if importlib.util.find_spec(module_name):
        return importlib.import_module(module_name)
    for path in _candidate_paths(vendor_subdir, env_var):
        _add_sys_path_if_exists(path)
        if importlib.util.find_spec(module_name):
            return importlib.import_module(module_name)
    raise ImportError(
        f"{module_name} is not available. Install it or bundle it in python_backend/vendor (or set {env_var})."
    )


def _load_arri_module() -> Any:
    return _load_module("fdl_arri_frameline", "fdl_arri_frameline", "FDL_ARRI_FRAMELINE_PATH")


def _load_sony_module() -> Any:
    return _load_module("fdl_sony_frameline", "fdl_sony_frameline", "FDL_SONY_FRAMELINE_PATH")


def _module_status(name: str, vendor_subdir: str, env_var: str) -> dict:
    if importlib.util.find_spec(name):
        return {"available": True, "source": "installed", "module": name}
    for path in _candidate_paths(vendor_subdir, env_var):
        _add_sys_path_if_exists(path)
        if importlib.util.find_spec(name):
            return {"available": True, "source": str(path), "module": name}
    return {
        "available": False,
        "module": name,
        "hint": f"Bundle in python_backend/vendor/{vendor_subdir} or set {env_var}",
    }


def status(_: dict) -> dict:
    return {
        "arri": _module_status("fdl_arri_frameline", "fdl_arri_frameline", "FDL_ARRI_FRAMELINE_PATH"),
        "sony": _module_status("fdl_sony_frameline", "fdl_sony_frameline", "FDL_SONY_FRAMELINE_PATH"),
    }


def _coerce_json_string(value: Any) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value)


def _run_cli(command: list[str]) -> None:
    proc = subprocess.run(command, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"Conversion CLI failed ({proc.returncode}): {proc.stderr.strip() or proc.stdout.strip()}")


def _conversion_report(
    conversion: str,
    mapped_fields: list[str],
    warnings: list[str],
    mapping_details: list[dict] | None = None,
    dropped_fields: list[str] | None = None,
) -> dict:
    mapping_details = mapping_details or []
    dropped_fields = dropped_fields or []
    return {
        "conversion": conversion,
        "mapped_fields": mapped_fields,
        "mapping_details": mapping_details,
        "dropped_fields": dropped_fields,
        "warnings": warnings,
        "lossy": len(warnings) > 0 or len(dropped_fields) > 0,
    }


def _read_text_file(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8")


def _write_text_file(path: str | Path, value: str) -> None:
    Path(path).write_text(value, encoding="utf-8")


def _parse_json_object(value: Any) -> dict:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _load_fdl_input_object(fdl_path: str | None, fdl_json: Any) -> dict:
    if fdl_json is not None:
        return _parse_json_object(fdl_json)
    if fdl_path:
        try:
            return _parse_json_object(_read_text_file(fdl_path))
        except Exception:
            return {}
    return {}


def _first_canvas_and_fd(fdl_obj: dict) -> tuple[dict, dict]:
    contexts = fdl_obj.get("contexts")
    if not isinstance(contexts, list) or not contexts:
        return {}, {}
    first_ctx = contexts[0] if isinstance(contexts[0], dict) else {}
    canvases = first_ctx.get("canvases")
    if not isinstance(canvases, list) or not canvases:
        return {}, {}
    first_canvas = canvases[0] if isinstance(canvases[0], dict) else {}
    fds = first_canvas.get("framing_decisions")
    if not isinstance(fds, list) or not fds:
        return first_canvas, {}
    first_fd = fds[0] if isinstance(fds[0], dict) else {}
    return first_canvas, first_fd


def _dim_text(value: Any) -> str:
    if isinstance(value, dict):
        w = value.get("width")
        h = value.get("height")
        if w is not None and h is not None:
            return f"{w}x{h}"
    return "n/a"


def _point_text(value: Any) -> str:
    if isinstance(value, dict):
        x = value.get("x")
        y = value.get("y")
        if x is not None and y is not None:
            return f"({x}, {y})"
    return "n/a"


def _mapping_detail(
    source_field: str,
    source_value: str,
    target_field: str,
    target_value: str,
    note: str = "",
    status: str = "mapped",
) -> dict:
    return {
        "source_field": source_field,
        "source_value": source_value,
        "target_field": target_field,
        "target_value": target_value,
        "note": note,
        "status": status,
    }


def arri_list_cameras(_: dict) -> dict:
    mod = _load_arri_module()
    cams = []
    for cam in mod.list_cameras():
        cams.append(
            {
                "camera_type": cam.camera_type,
                "xml_version": getattr(cam, "xml_version", ""),
                "sensor_modes": [
                    {
                        "name": mode.name,
                        "hres": mode.hres,
                        "vres": mode.vres,
                        "aspect": mode.aspect,
                    }
                    for mode in cam.sensor_modes
                ],
            }
        )
    return {"cameras": cams}


def sony_list_cameras(_: dict) -> dict:
    mod = _load_sony_module()
    cams = []
    for cam in mod.list_cameras():
        cams.append(
            {
                "camera_type": cam.camera_type,
                "model_code": cam.model_code,
                "sensor_modes": [
                    {
                        "name": mode.name,
                        "hres": mode.hres,
                        "vres": mode.vres,
                        "aspect": mode.aspect,
                    }
                    for mode in cam.sensor_modes
                ],
            }
        )
    return {"cameras": cams}


def arri_to_xml(params: dict) -> dict:
    camera_type = params.get("camera_type")
    sensor_mode = params.get("sensor_mode")
    if not camera_type or not sensor_mode:
        raise ValueError("camera_type and sensor_mode are required")

    fdl_path = params.get("fdl_path")
    fdl_json = params.get("fdl_json")
    if not fdl_path and not fdl_json:
        raise ValueError("Provide either fdl_path or fdl_json")
    mod = _load_arri_module()

    with tempfile.TemporaryDirectory() as tmp:
        source_path = Path(fdl_path) if fdl_path else Path(tmp) / "source.fdl.json"
        if fdl_json:
            _write_text_file(source_path, _coerce_json_string(fdl_json))

        result = mod.fdl_to_arri_frameline(
            source_path,
            camera_type=camera_type,
            sensor_mode=sensor_mode,
            include_protection=bool(params.get("include_protection", True)),
            include_effective=bool(params.get("include_effective", False)),
            line_width=int(params.get("line_width", 4)),
            context_label=params.get("context_label"),
            canvas_id=params.get("canvas_id"),
        )
        xml_string = mod.to_xml_string(result.frameline)

        output_path = params.get("output_path")
        if output_path:
            mod.write_xml(result.frameline, output_path)

        src_fdl = _load_fdl_input_object(fdl_path, fdl_json)
        src_canvas, src_fd = _first_canvas_and_fd(src_fdl)
        mapping_details = [
            _mapping_detail(
                "contexts[0].canvases[0].dimensions",
                _dim_text(src_canvas.get("dimensions")),
                "arri_xml.frame.window",
                _dim_text(src_fd.get("dimensions")),
                "ARRI frameline window derives from selected framing decision dimensions.",
            ),
            _mapping_detail(
                "contexts[0].canvases[0].framing_decisions[0].anchor_point",
                _point_text(src_fd.get("anchor_point")),
                "arri_xml.frame.position",
                _point_text(src_fd.get("anchor_point")),
            ),
            _mapping_detail(
                "contexts[0].canvases[0].framing_decisions[0].protection_dimensions",
                _dim_text(src_fd.get("protection_dimensions")),
                "arri_xml.protection.window",
                _dim_text(src_fd.get("protection_dimensions")),
                status="conditional",
            ),
        ]
        dropped_fields = [
            "fdl.header.default_framing_intent",
            "fdl.contexts[>0]",
            "fdl.canvases[>0]",
            "fdl.framing_decisions[>1]",
        ]
        warnings: list[str] = [
            "ARRI XML export may flatten multi-context/multi-canvas FDL structures to a single frameline context."
        ]
        if not bool(params.get("include_protection", True)):
            warnings.append("Protection box omitted from export (include_protection=false).")
        if bool(params.get("include_effective", False)):
            warnings.append("Effective dimensions included where supported by target ARRI XML format.")
        report = _conversion_report(
            conversion="fdl_to_arri_xml",
            mapped_fields=[
                "canvas.dimensions",
                "canvas.anamorphic_squeeze",
                "framing_decision.dimensions",
                "framing_decision.anchor_point",
                "framing_decision.protection_dimensions",
            ],
            warnings=warnings,
            mapping_details=mapping_details,
            dropped_fields=dropped_fields,
        )

        return {
            "xml_string": xml_string,
            "camera_type": result.camera_type,
            "sensor_mode": result.sensor_mode,
            "boxes_generated": result.boxes_generated,
            "report": report,
        }


def arri_to_fdl(params: dict) -> dict:
    xml_path = params.get("xml_path")
    xml_string = params.get("xml_string")
    if not xml_path and not xml_string:
        raise ValueError("Provide either xml_path or xml_string")
    mod = _load_arri_module()

    with tempfile.TemporaryDirectory() as tmp:
        source_path = Path(xml_path) if xml_path else Path(tmp) / "source.xml"
        if xml_string:
            _write_text_file(source_path, str(xml_string))

        try:
            result = mod.arri_frameline_to_fdl(
                source_path,
                context_label=params.get("context_label", "ARRI Frameline"),
                canvas_label=params.get("canvas_label"),
                hres=params.get("hres"),
                vres=params.get("vres"),
            )
        except NotImplementedError:
            # Some builds expose read-only fdl collection wrappers; CLI path remains stable.
            out_fdl = Path(tmp) / "converted.fdl.json"
            _run_cli(["fdl-arri-frameline", "to-fdl", str(source_path), "-o", str(out_fdl)])
            fdl_obj = json.loads(_read_text_file(out_fdl))
            out_canvas, out_fd = _first_canvas_and_fd(fdl_obj)
            report = _conversion_report(
                conversion="arri_xml_to_fdl",
                mapped_fields=[
                    "frameline.window -> framing_decision.dimensions",
                    "frameline.position -> framing_decision.anchor_point",
                    "sensor metadata -> canvas.dimensions",
                ],
                mapping_details=[
                    _mapping_detail(
                        "arri_xml.frame.window",
                        "see XML",
                        "contexts[0].canvases[0].framing_decisions[0].dimensions",
                        _dim_text(out_fd.get("dimensions")),
                    ),
                    _mapping_detail(
                        "arri_xml.frame.position",
                        "see XML",
                        "contexts[0].canvases[0].framing_decisions[0].anchor_point",
                        _point_text(out_fd.get("anchor_point")),
                    ),
                    _mapping_detail(
                        "arri_xml.sensor_mode",
                        "see XML",
                        "contexts[0].canvases[0].dimensions",
                        _dim_text(out_canvas.get("dimensions")),
                    ),
                ],
                dropped_fields=[
                    "arri_xml.vendor_extension_nodes.*",
                    "arri_xml.unrecognized_metadata.*",
                ],
                warnings=[
                    "Converted via CLI fallback due to Python binding incompatibility.",
                    "Some ARRI-specific XML metadata may not map to canonical ASC FDL fields.",
                ],
            )
            return {
                "fdl": fdl_obj,
                "framing_decisions_created": 1,
                "report": report,
            }
        fdl_dict = fdl_to_dict(result.fdl)
        out_canvas, out_fd = _first_canvas_and_fd(fdl_dict)

        output_path = params.get("output_path")
        if output_path:
            if hasattr(mod, "convert_xml_to_fdl_file"):
                mod.convert_xml_to_fdl_file(source_path, output_path)
            else:
                _write_text_file(output_path, json.dumps(fdl_dict, indent=2))

        return {
            "fdl": fdl_dict,
            "framing_decisions_created": result.framing_decisions_created,
            "report": _conversion_report(
                conversion="arri_xml_to_fdl",
                mapped_fields=[
                    "frameline.window -> framing_decision.dimensions",
                    "frameline.position -> framing_decision.anchor_point",
                    "sensor metadata -> canvas.dimensions",
                ],
                mapping_details=[
                    _mapping_detail(
                        "arri_xml.frame.window",
                        "see XML",
                        "contexts[0].canvases[0].framing_decisions[0].dimensions",
                        _dim_text(out_fd.get("dimensions")),
                    ),
                    _mapping_detail(
                        "arri_xml.frame.position",
                        "see XML",
                        "contexts[0].canvases[0].framing_decisions[0].anchor_point",
                        _point_text(out_fd.get("anchor_point")),
                    ),
                    _mapping_detail(
                        "arri_xml.sensor_mode",
                        "see XML",
                        "contexts[0].canvases[0].dimensions",
                        _dim_text(out_canvas.get("dimensions")),
                    ),
                ],
                dropped_fields=[
                    "arri_xml.vendor_extension_nodes.*",
                    "arri_xml.unrecognized_metadata.*",
                ],
                warnings=["Some ARRI-specific XML metadata may not map to canonical ASC FDL fields."],
            ),
        }


def sony_to_xml(params: dict) -> dict:
    camera_type = params.get("camera_type")
    imager_mode = params.get("imager_mode")
    if not camera_type or not imager_mode:
        raise ValueError("camera_type and imager_mode are required")

    fdl_path = params.get("fdl_path")
    fdl_json = params.get("fdl_json")
    if not fdl_path and not fdl_json:
        raise ValueError("Provide either fdl_path or fdl_json")
    mod = _load_sony_module()

    with tempfile.TemporaryDirectory() as tmp:
        source_path = Path(fdl_path) if fdl_path else Path(tmp) / "source.fdl.json"
        if fdl_json:
            _write_text_file(source_path, _coerce_json_string(fdl_json))

        result = mod.fdl_to_sony_frameline(
            source_path,
            camera_type=camera_type,
            imager_mode=imager_mode,
            include_protection=bool(params.get("include_protection", False)),
            framing_color=params.get("framing_color", "White"),
            protection_color=params.get("protection_color", "Yellow"),
            context_label=params.get("context_label"),
            canvas_id=params.get("canvas_id"),
        )
        xml_strings = [mod.to_xml_string(fl) for fl in result.framelines]

        output_path = params.get("output_path")
        if output_path:
            mod.convert_and_write(
                source_path,
                output_path,
                camera_type=camera_type,
                imager_mode=imager_mode,
                include_protection=bool(params.get("include_protection", False)),
                framing_color=params.get("framing_color", "White"),
                protection_color=params.get("protection_color", "Yellow"),
                context_label=params.get("context_label"),
                canvas_id=params.get("canvas_id"),
            )

        src_fdl = _load_fdl_input_object(fdl_path, fdl_json)
        src_canvas, src_fd = _first_canvas_and_fd(src_fdl)
        mapping_details = [
            _mapping_detail(
                "contexts[0].canvases[0].dimensions",
                _dim_text(src_canvas.get("dimensions")),
                "sony_xml.frame.window",
                _dim_text(src_fd.get("dimensions")),
                "Sony frameline window derives from selected framing decision dimensions.",
            ),
            _mapping_detail(
                "contexts[0].canvases[0].framing_decisions[0].anchor_point",
                _point_text(src_fd.get("anchor_point")),
                "sony_xml.frame.position",
                _point_text(src_fd.get("anchor_point")),
            ),
            _mapping_detail(
                "contexts[0].canvases[0].framing_decisions[0].protection_dimensions",
                _dim_text(src_fd.get("protection_dimensions")),
                "sony_xml.protection.window",
                _dim_text(src_fd.get("protection_dimensions")),
                status="conditional",
            ),
        ]
        dropped_fields = [
            "fdl.header.default_framing_intent",
            "fdl.contexts[>0]",
            "fdl.canvases[>0]",
            "fdl.framing_decisions[>1]",
        ]
        warnings: list[str] = [
            "Sony export may emit multiple XML files (e.g. L1/L2) for framing/protection variants.",
            "Sony XML export may flatten multi-context/multi-canvas FDL structures to a single target context.",
        ]
        if not bool(params.get("include_protection", False)):
            warnings.append("Protection box omitted from export (include_protection=false).")
        report = _conversion_report(
            conversion="fdl_to_sony_xml",
            mapped_fields=[
                "canvas.dimensions",
                "canvas.anamorphic_squeeze",
                "framing_decision.dimensions",
                "framing_decision.anchor_point",
                "framing_decision.protection_dimensions",
            ],
            warnings=warnings,
            mapping_details=mapping_details,
            dropped_fields=dropped_fields,
        )

        return {
            "xml_strings": xml_strings,
            "camera_type": result.camera_type,
            "imager_mode": result.imager_mode,
            "frame_lines_generated": result.frame_lines_generated,
            "report": report,
        }


def sony_to_fdl(params: dict) -> dict:
    xml_path = params.get("xml_path")
    xml_string = params.get("xml_string")
    if not xml_path and not xml_string:
        raise ValueError("Provide either xml_path or xml_string")
    mod = _load_sony_module()

    with tempfile.TemporaryDirectory() as tmp:
        source_path = Path(xml_path) if xml_path else Path(tmp) / "source.xml"
        if xml_string:
            _write_text_file(source_path, str(xml_string))

        result = mod.sony_frameline_to_fdl(
            source_path,
            context_label=params.get("context_label", "Sony Frameline"),
            canvas_label=params.get("canvas_label"),
        )
        fdl_dict = fdl_to_dict(result.fdl)
        out_canvas, out_fd = _first_canvas_and_fd(fdl_dict)

        output_path = params.get("output_path")
        if output_path and hasattr(mod, "convert_xml_to_fdl_file"):
            mod.convert_xml_to_fdl_file(source_path, output_path)

        return {
            "fdl": fdl_dict,
            "framing_decisions_created": result.framing_decisions_created,
            "report": _conversion_report(
                conversion="sony_xml_to_fdl",
                mapped_fields=[
                    "frameline.window -> framing_decision.dimensions",
                    "frameline.position -> framing_decision.anchor_point",
                    "camera mode metadata -> canvas.dimensions",
                ],
                mapping_details=[
                    _mapping_detail(
                        "sony_xml.frame.window",
                        "see XML",
                        "contexts[0].canvases[0].framing_decisions[0].dimensions",
                        _dim_text(out_fd.get("dimensions")),
                    ),
                    _mapping_detail(
                        "sony_xml.frame.position",
                        "see XML",
                        "contexts[0].canvases[0].framing_decisions[0].anchor_point",
                        _point_text(out_fd.get("anchor_point")),
                    ),
                    _mapping_detail(
                        "sony_xml.imager_mode",
                        "see XML",
                        "contexts[0].canvases[0].dimensions",
                        _dim_text(out_canvas.get("dimensions")),
                    ),
                ],
                dropped_fields=[
                    "sony_xml.vendor_extension_nodes.*",
                    "sony_xml.unrecognized_metadata.*",
                ],
                warnings=["Some Sony-specific XML metadata may not map to canonical ASC FDL fields."],
            ),
        }
