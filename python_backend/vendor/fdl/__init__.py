from .canvas import Canvas as Canvas
from .canvastemplate import CanvasTemplate as CanvasTemplate
from .canvastemplate import (
    Geometry,
    TransformationResult,
    calculate_scale_factor,
    get_anchor_from_path,
    get_dimensions_from_path,
)
from .clipid import ClipID as ClipID
from .common import (
    TypedCollection,
    find_by_attr,
    find_by_id,
    find_by_label,
)
from .config import DEFAULT_ROUNDING_STRATEGY, set_rounding
from .constants import (
    FDL_SCHEMA_MAJOR,
    FDL_SCHEMA_MINOR,
    FDL_SCHEMA_VERSION,
    PATH_HIERARCHY,
    FitMethod,
    GeometryPath,
    HAlign,
    RoundingEven,
    RoundingMode,
    VAlign,
)
from .context import Context as Context
from .errors import FDLError, FDLValidationError
from .fdl import FDL as FDL
from .fdlchecker import FDLValidator, validate_fdl
from .framingdecision import FramingDecision as FramingDecision
from .framingintent import FramingIntent as FramingIntent
from .handlers import read_from_file, read_from_string, validate, write_to_file, write_to_string
from .header import Header as Header
from .header import Version as Version
from .rounding import RoundStrategy as RoundStrategy
from .rounding import fdl_round
from .types import DimensionsFloat, DimensionsInt, PointFloat

# Backward compatibility alias
CanvasTemplateRound = RoundStrategy

__all__ = [
    "DEFAULT_ROUNDING_STRATEGY",
    "FDL",
    "FDL_SCHEMA_MAJOR",
    "FDL_SCHEMA_MINOR",
    "FDL_SCHEMA_VERSION",
    "PATH_HIERARCHY",
    "Canvas",
    "CanvasTemplate",
    "CanvasTemplateRound",
    "ClipID",
    "Context",
    "DimensionsFloat",
    "DimensionsInt",
    "FDLError",
    "FDLValidationError",
    "FDLValidator",
    "FitMethod",
    "FramingDecision",
    "FramingIntent",
    "Geometry",
    "GeometryPath",
    "HAlign",
    "Header",
    "PointFloat",
    "RoundStrategy",
    "RoundingEven",
    "RoundingMode",
    "TransformationResult",
    "TypedCollection",
    "VAlign",
    "Version",
    "calculate_scale_factor",
    "config",
    "fdl_round",
    "find_by_attr",
    "find_by_id",
    "find_by_label",
    "get_anchor_from_path",
    "get_dimensions_from_path",
    "read_from_file",
    "read_from_string",
    "rounding",
    "set_rounding",
    "validate",
    "validate_fdl",
    "write_to_file",
    "write_to_string",
]

__version__ = "0.1.0.dev0"

set_rounding(DEFAULT_ROUNDING_STRATEGY)
