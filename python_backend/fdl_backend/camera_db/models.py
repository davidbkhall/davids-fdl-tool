"""Camera and sensor data models."""

from dataclasses import dataclass, field


@dataclass
class SensorSpec:
    name: str
    photosite_width: int
    photosite_height: int
    physical_width_mm: float
    physical_height_mm: float
    pixel_pitch_um: float


@dataclass
class RecordingMode:
    id: str
    name: str
    active_width: int
    active_height: int
    active_area_width_mm: float
    active_area_height_mm: float
    max_fps: int
    codec_options: list[str] = field(default_factory=list)


@dataclass
class CameraSpec:
    id: str
    manufacturer: str
    model: str
    sensor: SensorSpec
    recording_modes: list[RecordingMode] = field(default_factory=list)
    common_deliverables: list[str] = field(default_factory=list)
