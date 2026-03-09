"""FDL ARRI Frameline Converter.

Bidirectional converter between ASC FDL framing decisions and ARRI
frameline XML files (FLT v2.2) used by ALEXA 35, ALEXA 265, Mini LF,
and ALEXA 65 cameras.
"""

__version__ = "1.0.0"

from fdl_arri_frameline.cameras import (
    CAMERA_REGISTRY,
    CameraModel,
    SensorMode,
    get_camera,
    list_cameras,
)
from fdl_arri_frameline.converter import (
    ConversionResult,
    FDLConversionResult,
    arri_frameline_to_fdl,
    convert_and_write,
    convert_xml_to_fdl_file,
    fdl_to_arri_frameline,
)
from fdl_arri_frameline.models import (
    ArriFrameline,
    CameraInfo,
    CenterMarker,
    FramelineBox,
    Surround,
    from_xml_string,
    read_xml,
    to_xml_string,
    write_xml,
)

__all__ = [
    "CAMERA_REGISTRY",
    "ArriFrameline",
    "CameraInfo",
    "CameraModel",
    "CenterMarker",
    "ConversionResult",
    "FDLConversionResult",
    "FramelineBox",
    "SensorMode",
    "Surround",
    "__version__",
    "arri_frameline_to_fdl",
    "convert_and_write",
    "convert_xml_to_fdl_file",
    "fdl_to_arri_frameline",
    "from_xml_string",
    "get_camera",
    "list_cameras",
    "read_xml",
    "to_xml_string",
    "write_xml",
]
