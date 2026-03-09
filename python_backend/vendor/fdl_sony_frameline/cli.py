"""Command-line interface for the FDL Sony Frameline converter.

Three subcommands:

* ``fdl-sony-frameline to-xml``  -- convert FDL to Sony frameline XML
* ``fdl-sony-frameline to-fdl``  -- convert Sony frameline XML to FDL
* ``fdl-sony-frameline list-cameras`` -- list supported cameras and modes
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

logger = logging.getLogger(__name__)


def _build_to_xml_parser(subparsers: argparse._SubParsersAction) -> None:
    """Build the ``to-xml`` subcommand."""
    parser = subparsers.add_parser("to-xml", help="Convert FDL to Sony frameline XML")
    parser.add_argument("fdl", type=Path, help="Path to the source FDL file")
    parser.add_argument("--camera", required=True, help="Camera model (e.g. 'VENICE 2 8K' or 'MPC-3628')")
    parser.add_argument("--imager-mode", required=True, dest="imager_mode", help="Imager mode (e.g. '6K 2.39:1')")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output XML file path")
    parser.add_argument(
        "--include-protection",
        action="store_true",
        default=False,
        dest="include_protection",
        help="Also generate a second XML file (L2) for the protection area",
    )
    parser.add_argument("--framing-color", default="White", dest="framing_color", help="Colour for framing frame line")
    parser.add_argument("--protection-color", default="Yellow", dest="protection_color", help="Colour for protection frame line")
    parser.add_argument("--context", default=None, help="Select context by label")
    parser.add_argument("--canvas", default=None, help="Select canvas by id")
    parser.set_defaults(func=_run_to_xml)


def _build_to_fdl_parser(subparsers: argparse._SubParsersAction) -> None:
    """Build the ``to-fdl`` subcommand."""
    parser = subparsers.add_parser("to-fdl", help="Convert Sony frameline XML to FDL")
    parser.add_argument("xml", type=Path, help="Path to the Sony frameline XML file")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output FDL file path")
    parser.add_argument("--context-label", default="Sony Frameline", dest="context_label", help="Label for the FDL context")
    parser.add_argument("--canvas-label", default=None, dest="canvas_label", help="Label for the FDL canvas")
    parser.set_defaults(func=_run_to_fdl)


def _build_list_cameras_parser(subparsers: argparse._SubParsersAction) -> None:
    """Build the ``list-cameras`` subcommand."""
    parser = subparsers.add_parser("list-cameras", help="List supported cameras and imager modes")
    parser.add_argument("--camera", default=None, help="Filter by camera model or model code")
    parser.set_defaults(func=_run_list_cameras)


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------


def _run_to_xml(args: argparse.Namespace) -> None:
    from fdl_sony_frameline.converter import convert_and_write

    result = convert_and_write(
        fdl_path=args.fdl,
        output_path=args.output,
        camera_type=args.camera,
        imager_mode=args.imager_mode,
        include_protection=args.include_protection,
        framing_color=args.framing_color,
        protection_color=args.protection_color,
        context_label=args.context,
        canvas_id=args.canvas,
    )
    out = Path(args.output)
    print(f"Converted {result.source_fdl_path}")
    print(f"  Camera: {result.camera_type} ({result.imager_mode})")
    print(f"  Frame line files: {result.frame_lines_generated}")
    if result.frame_lines_generated == 1:
        print(f"  Output: {out}")
    else:
        for i in range(result.frame_lines_generated):
            slot_path = out.parent / f"{out.stem}_L{i + 1}{out.suffix}"
            print(f"  L{i + 1}: {slot_path}")


def _run_to_fdl(args: argparse.Namespace) -> None:
    from fdl_sony_frameline.converter import convert_xml_to_fdl_file

    result = convert_xml_to_fdl_file(
        xml_path=args.xml,
        output_path=args.output,
        context_label=args.context_label,
        canvas_label=args.canvas_label,
    )
    print(f"Converted {result.source_xml_path} -> {args.output}")
    print(f"  Framing decisions: {result.framing_decisions_created}")


def _run_list_cameras(args: argparse.Namespace) -> None:
    from fdl_sony_frameline.cameras import get_camera, list_cameras

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
        print(f"\n{cam.camera_type} ({cam.model_code})")
        print(f"  {'Mode':<20s} {'Resolution':>14s}  {'Aspect':>8s}  Squeeze")
        print(f"  {'-' * 20}  {'-' * 14}  {'-' * 8}  {'-' * 20}")
        for mode in cam.sensor_modes:
            res = f"{mode.hres}x{mode.vres}"
            squeeze = ", ".join(f"{s}x" for s in mode.squeeze_factors)
            print(f"  {mode.name:<20s} {res:>14s}  {mode.aspect:>8.4f}  {squeeze}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="fdl-sony-frameline",
        description="Bidirectional converter between FDL and Sony VENICE frameline XML",
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
