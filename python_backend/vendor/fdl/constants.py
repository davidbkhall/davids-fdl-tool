from __future__ import annotations

from enum import Enum

# ---------------------------------------------------------------------------
# FDL Schema
# ---------------------------------------------------------------------------

FDL_SCHEMA_MAJOR = 2
FDL_SCHEMA_MINOR = 0
FDL_SCHEMA_VERSION = {"major": FDL_SCHEMA_MAJOR, "minor": FDL_SCHEMA_MINOR}

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class _StrEnum(str, Enum):
    """str Enum base that formats as the value, not ``ClassName.MEMBER``."""

    __str__ = str.__str__


class GeometryPath(_StrEnum):
    CANVAS_DIMENSIONS = "canvas.dimensions"
    CANVAS_EFFECTIVE_DIMENSIONS = "canvas.effective_dimensions"
    FRAMING_PROTECTION_DIMENSIONS = "framing_decision.protection_dimensions"
    FRAMING_DIMENSIONS = "framing_decision.dimensions"


PATH_HIERARCHY = list(GeometryPath)


class RoundingMode(_StrEnum):
    UP = "up"
    DOWN = "down"
    ROUND = "round"


class RoundingEven(_StrEnum):
    EVEN = "even"
    WHOLE = "whole"


class FitMethod(_StrEnum):
    WIDTH = "width"
    HEIGHT = "height"
    FIT_ALL = "fit_all"
    FILL = "fill"


class HAlign(_StrEnum):
    LEFT = "left"
    CENTER = "center"
    RIGHT = "right"


class VAlign(_StrEnum):
    TOP = "top"
    CENTER = "center"
    BOTTOM = "bottom"


# ---------------------------------------------------------------------------
# Floating-point comparison
# ---------------------------------------------------------------------------

FP_REL_TOL = 1e-9
FP_ABS_TOL = 1e-6

# ---------------------------------------------------------------------------
# Numeric thresholds
# ---------------------------------------------------------------------------

OVERFLOW_THRESHOLD = 0.01
ALIGN_FACTOR_LEFT_OR_TOP = 0.0
ALIGN_FACTOR_CENTER = 0.5
ALIGN_FACTOR_RIGHT_OR_BOTTOM = 1.0

# ---------------------------------------------------------------------------
# Default labels
# ---------------------------------------------------------------------------

DEFAULT_FDL_CREATOR = "PyFDL"
DEFAULT_TEMPLATE_LABEL = "VFX Pull - Custom"
DEFAULT_FRAMING_INTENT_LABEL = "Default Framing Intent"
