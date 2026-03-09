"""Command-line interface for the FDL ARRI Frameline converter.

Three subcommands:

* ``fdl-arri-frameline to-xml``  -- convert FDL to ARRI frameline XML
* ``fdl-arri-frameline to-fdl``  -- convert ARRI frameline XML to FDL
* ``fdl-arri-frameline list-cameras`` -- list supported cameras and modes
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

logger = logging.getLogger(__name__)


def _build_to_xml_parser(subparsers: argparse._SubParsersAction) -> None:
    """Build the ``to-xml`` subcommand."""
    parser = subparsers.add_parser("to-xml", help="Convert FDL to ARRI frameline XML")
    parser.add_argument("fdl", type=Path, help="Path to the source FDL file")
    parser.add_argument("--camera", required=True, help="Camera model (e.g. 'ALEXA 35')")
    parser.add_argument("--sensor-mode", required=True, dest="sensor_mode", help="Sensor mode (e.g. '4.6K 3:2 Open Gate')")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output XML file path")
    parser.add_argument("--no-protection", action="store_true", default=False, dest="no_protection", help="Exclude protection rect")
    parser.add_argument(
        "--include-effective",
        action="store_true",
        default=False,
        dest="include_effective",
        help="Include effective dimensions rect",
    )
    parser.add_argument("--line-width", type=int, default=4, dest="line_width", help="Line width in pixels for frameline borders")
    parser.add_argument("--context", default=None, help="Select context by label")
    parser.add_argument("--canvas", default=None, help="Select canvas by id")
    parser.set_defaults(func=_run_to_xml)


def _build_to_fdl_parser(subparsers: argparse._SubParsersAction) -> None:
    """Build the ``to-fdl`` subcommand."""
    parser = subparsers.add_parser("to-fdl", help="Convert ARRI frameline XML to FDL")
    parser.add_argument("xml", type=Path, help="Path to the ARRI frameline XML file")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output FDL file path")
    parser.add_argument("--context-label", default="ARRI Frameline", dest="context_label", help="Label for the FDL context")
    parser.add_argument("--canvas-label", default=None, dest="canvas_label", help="Label for the FDL canvas")
    parser.add_argument("--hres", type=int, default=None, help="Explicit horizontal resolution (overrides XML metadata)")
    parser.add_argument("--vres", type=int, default=None, help="Explicit vertical resolution (overrides XML metadata)")
    parser.set_defaults(func=_run_to_fdl)


def _build_list_cameras_parser(subparsers: argparse._SubParsersAction) -> None:
    """Build the ``list-cameras`` subcommand."""
    parser = subparsers.add_parser("list-cameras", help="List supported cameras and sensor modes")
    parser.add_argument("--camera", default=None, help="Filter by camera model")
    parser.set_defaults(func=_run_list_cameras)


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------


def _run_to_xml(args: argparse.Namespace) -> None:
    from fdl_arri_frameline.converter import convert_and_write

    result = convert_and_write(
        fdl_path=args.fdl,
        output_path=args.output,
        camera_type=args.camera,
        sensor_mode=args.sensor_mode,
        include_protection=not args.no_protection,
        include_effective=args.include_effective,
        line_width=args.line_width,
        context_label=args.context,
        canvas_id=args.canvas,
    )
    print(f"Converted {result.source_fdl_path} -> {args.output}")
    print(f"  Camera: {result.camera_type} / {result.sensor_mode}")
    print(f"  Boxes:  {result.boxes_generated}")


def _run_to_fdl(args: argparse.Namespace) -> None:
    from fdl_arri_frameline.converter import convert_xml_to_fdl_file

    result = convert_xml_to_fdl_file(
        xml_path=args.xml,
        output_path=args.output,
        context_label=args.context_label,
        canvas_label=args.canvas_label,
        hres=args.hres,
        vres=args.vres,
    )
    print(f"Converted {result.source_xml_path} -> {args.output}")
    print(f"  Framing decisions: {result.framing_decisions_created}")


def _run_list_cameras(args: argparse.Namespace) -> None:
    from fdl_arri_frameline.cameras import get_camera, list_cameras

    if args.camera:
        try:
            cam = get_camera(args.camera)
        except KeyError as exc:
            print(str(exc), file=sys.stderr)
            sys.exit(1)
        cameras = [cam]
    else:
        cameras = list_cameras()

    for cam in cameras:
        print(f"\n{cam.camera_type}")
        print(f"  {'Mode':<30s} {'Resolution':>14s}  {'Aspect':>8s}  Squeeze")
        print(f"  {'-' * 30}  {'-' * 14}  {'-' * 8}  {'-' * 20}")
        for mode in cam.sensor_modes:
            res = f"{mode.hres}x{mode.vres}"
            squeeze = ", ".join(f"{s}x" for s in mode.squeeze_factors)
            print(f"  {mode.name:<30s} {res:>14s}  {mode.aspect:>8.4f}  {squeeze}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="fdl-arri-frameline",
        description="Bidirectional converter between FDL and ARRI frameline XML",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")

    subparsers = parser.add_subparsers(dest="command")
    _build_to_xml_parser(subparsers)
    _build_to_fdl_parser(subparsers)
    _build_list_cameras_parser(subparsers)

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.DEBUG, format="%(name)s %(levelname)s: %(message)s")
    else:
        logging.basicConfig(level=logging.WARNING)

    if not args.command:
        parser.print_help()
        sys.exit(1)

    try:
        args.func(args)
    except Exception as exc:
        logger.debug("Error details:", exc_info=True)
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
