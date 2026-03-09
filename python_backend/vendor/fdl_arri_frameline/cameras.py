"""ARRI camera sensor database.

Registry of camera models and their sensor modes with resolutions,
aspect ratios, and supported anamorphic squeeze factors.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class SensorMode:
    """A single sensor/recording mode for an ARRI camera."""

    name: str
    hres: int
    vres: int
    squeeze_factors: tuple[float, ...] = (1.0,)

    @property
    def aspect(self) -> float:
        return round(self.hres / self.vres, 5)


@dataclass(frozen=True)
class CameraModel:
    """An ARRI camera model with its available sensor modes."""

    camera_type: str
    sensor_modes: tuple[SensorMode, ...] = field(default_factory=tuple)
    xml_version: str = "2.2"

    def get_mode(self, name: str) -> SensorMode:
        """Look up a sensor mode by name (case-insensitive)."""
        key = name.lower()
        for mode in self.sensor_modes:
            if mode.name.lower() == key:
                return mode
        available = [m.name for m in self.sensor_modes]
        raise KeyError(f"Sensor mode {name!r} not found for {self.camera_type}. Available: {available}")

    @property
    def default_mode(self) -> SensorMode:
        """Return the first (typically Open Gate) sensor mode."""
        return self.sensor_modes[0]


# ---------------------------------------------------------------------------
# ALEXA 35 / ALEXA 35 Xtreme
# ---------------------------------------------------------------------------

ALEXA_35 = CameraModel(
    camera_type="ALEXA 35",
    sensor_modes=(
        SensorMode("4.6K 3:2 Open Gate", 4608, 3164),
        SensorMode("4.6K 16:9", 4608, 2592, squeeze_factors=(1.0, 1.3, 1.5, 1.8, 2.0)),
        SensorMode("4K 16:9", 4096, 2304),
        SensorMode("4K 2:1", 4096, 2048),
        SensorMode("3.8K 16:9", 3840, 2160),
        SensorMode("3.3K 6:5", 3328, 2790, squeeze_factors=(1.0, 1.3, 2.0)),
        SensorMode("3K 1:1", 3072, 3072, squeeze_factors=(1.0, 2.0)),
        SensorMode("2.7K 8:9", 2700, 3036, squeeze_factors=(2.0,)),
        SensorMode("2K 16:9 S16", 2048, 1152),
    ),
)

# ---------------------------------------------------------------------------
# ALEXA 265
# ---------------------------------------------------------------------------

ALEXA_265 = CameraModel(
    camera_type="ALEXA 265",
    sensor_modes=(
        SensorMode("6.5K Open Gate", 6560, 3100),
        SensorMode("6.5K 16:9", 6560, 3690),
        SensorMode("4K 16:9", 4096, 2304),
        SensorMode("3.8K 16:9", 3840, 2160),
    ),
)

# ---------------------------------------------------------------------------
# ALEXA Mini LF
# ---------------------------------------------------------------------------

ALEXA_MINI_LF = CameraModel(
    camera_type="ALEXA Mini LF",
    xml_version="",
    sensor_modes=(
        SensorMode("LF Open Gate", 4448, 3096),
        SensorMode("LF 2.39:1", 4448, 1856, squeeze_factors=(1.0, 1.3, 2.0)),
        SensorMode("LF 16:9 4.3K", 3840, 2160),
        SensorMode("LF 16:9 3.8K", 3840, 2160),
        SensorMode("LF 1:1", 2880, 2880, squeeze_factors=(1.0, 2.0)),
        SensorMode("S35 3:2", 3424, 2202),
        SensorMode("S35 16:9 3.2K", 3200, 1800),
        SensorMode("S35 4:3", 2880, 2160, squeeze_factors=(1.0, 2.0)),
        SensorMode("S35 16:9 2.8K", 2880, 1620),
    ),
)

# ---------------------------------------------------------------------------
# ALEXA LF
# ---------------------------------------------------------------------------

ALEXA_LF = CameraModel(
    camera_type="ALEXA LF",
    xml_version="",
    sensor_modes=(
        SensorMode("LF Open Gate", 4448, 3096),
        SensorMode("LF 16:9", 3840, 2160),
        SensorMode("LF 2.39:1", 4448, 1856, squeeze_factors=(1.0, 1.3, 2.0)),
    ),
)

# ---------------------------------------------------------------------------
# ALEXA 65
# ---------------------------------------------------------------------------

ALEXA_65 = CameraModel(
    camera_type="ALEXA 65",
    xml_version="",
    sensor_modes=(
        SensorMode("Open Gate", 6560, 3100),
        SensorMode("16:9", 5120, 2880),
        SensorMode("3:2", 4320, 2880),
        SensorMode("LF Open Gate", 4448, 3096),
        SensorMode("UHD", 3840, 2160),
    ),
)

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

CAMERA_REGISTRY: dict[str, CameraModel] = {cam.camera_type: cam for cam in (ALEXA_35, ALEXA_265, ALEXA_MINI_LF, ALEXA_LF, ALEXA_65)}


def get_camera(camera_type: str) -> CameraModel:
    """Look up a camera model by type string (case-insensitive)."""
    key = camera_type.strip()
    for name, cam in CAMERA_REGISTRY.items():
        if name.lower() == key.lower():
            return cam
    available = list(CAMERA_REGISTRY.keys())
    raise KeyError(f"Camera {camera_type!r} not found. Available: {available}")


def list_cameras() -> list[CameraModel]:
    """Return all registered camera models."""
    return list(CAMERA_REGISTRY.values())
