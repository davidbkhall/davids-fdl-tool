"""FDL Sony Frameline Converter.

Bidirectional converter between ASC FDL framing decisions and Sony
VENICE 2 frameline XML files used by VENICE 2 8K (MPC-3628) and
VENICE 2 6K (MPC-3626) cameras.
"""

__version__ = "0.1.0"

from fdl_sony_frameline.cameras import (
    CAMERA_REGISTRY,
    MODEL_CODE_REGISTRY,
    CameraModel,
    ImagerMode,
    get_camera,
    get_camera_by_model_code,
    list_cameras,
)
from fdl_sony_frameline.converter import (
    ConversionResult,
    FDLConversionResult,
    convert_and_write,
    convert_xml_to_fdl_file,
    fdl_to_sony_frameline,
    sony_frameline_to_fdl,
)
from fdl_sony_frameline.models import (
    CameraSettings,
    CornerPoint,
    FrameLineRect,
    SonyFrameline,
    frameline_rect_from_insets,
    from_xml_string,
    read_xml,
    to_xml_string,
    write_xml,
)

__all__ = [
    "CAMERA_REGISTRY",
    "MODEL_CODE_REGISTRY",
    "CameraModel",
    "CameraSettings",
    "ConversionResult",
    "CornerPoint",
    "FDLConversionResult",
    "FrameLineRect",
    "ImagerMode",
    "SonyFrameline",
    "__version__",
    "convert_and_write",
    "convert_xml_to_fdl_file",
    "fdl_to_sony_frameline",
    "frameline_rect_from_insets",
    "from_xml_string",
    "get_camera",
    "get_camera_by_model_code",
    "list_cameras",
    "read_xml",
    "sony_frameline_to_fdl",
    "to_xml_string",
    "write_xml",
]
