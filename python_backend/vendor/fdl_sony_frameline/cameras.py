"""Sony VENICE camera sensor database.

Registry of VENICE 2 camera models and their imager modes with
resolutions and anamorphic squeeze factors.

Camera model identifiers follow Sony's internal naming:
- MPC-3628: VENICE 2 with 8.6K sensor
- MPC-3626: VENICE 2 with 6K sensor
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ImagerMode:
    """A single imager/recording mode for a Sony VENICE camera."""

    name: str
    hres: int
    vres: int
    squeeze_factors: tuple[float, ...] = (1.0,)

    @property
    def aspect(self) -> float:
        return round(self.hres / self.vres, 5)


@dataclass(frozen=True)
class CameraModel:
    """A Sony VENICE camera model with its available imager modes."""

    camera_type: str
    model_code: str
    sensor_modes: tuple[ImagerMode, ...] = field(default_factory=tuple)

    def get_mode(self, name: str) -> ImagerMode:
        """Look up an imager mode by name (case-insensitive)."""
        key = name.lower()
        for mode in self.sensor_modes:
            if mode.name.lower() == key:
                return mode
        available = [m.name for m in self.sensor_modes]
        raise KeyError(f"Imager mode {name!r} not found for {self.camera_type}. Available: {available}")

    @property
    def default_mode(self) -> ImagerMode:
        """Return the first (typically Open Gate) imager mode."""
        return self.sensor_modes[0]


# ---------------------------------------------------------------------------
# VENICE 2 8K (MPC-3628) — 8.6K full-frame sensor
# ---------------------------------------------------------------------------

VENICE_2_8K = CameraModel(
    camera_type="VENICE 2 8K",
    model_code="MPC-3628",
    sensor_modes=(
        # Full Frame
        ImagerMode("8.6K 3:2", 8640, 5760, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("8.6K 17:9", 8640, 4556, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("8.2K 17:9", 8192, 4320, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("8.2K 2.39:1", 8192, 3432),
        ImagerMode("8.1K 16:9", 8100, 4556, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("7.6K 16:9", 7680, 4320, squeeze_factors=(1.0, 1.3, 2.0)),
        # Super 35
        ImagerMode("5.8K 6:5", 5792, 4854, squeeze_factors=(2.0,)),
        ImagerMode("5.8K 4:3", 5792, 4276, squeeze_factors=(2.0,)),
        ImagerMode("5.8K 17:9", 5792, 3056),
        ImagerMode("5.5K 2.39:1", 5480, 2296),
        ImagerMode("5.4K 16:9", 5434, 3056),
    ),
)

# ---------------------------------------------------------------------------
# VENICE 2 6K (MPC-3626) — 6K full-frame sensor
# ---------------------------------------------------------------------------

VENICE_2_6K = CameraModel(
    camera_type="VENICE 2 6K",
    model_code="MPC-3626",
    sensor_modes=(
        # Full Frame
        ImagerMode("6K 3:2", 6048, 4032, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("6K 2.39:1", 6048, 2534, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("6K 17:9", 6054, 3192, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("6K 1.85:1", 6054, 3272, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("5.7K 16:9", 5674, 3192, squeeze_factors=(1.0, 1.3, 2.0)),
        ImagerMode("3.8K 16:9", 3840, 2160),
        # Super 35
        ImagerMode("4K 2.39:1", 4096, 1716),
        ImagerMode("4K 17:9", 4096, 2160),
        ImagerMode("4K 4:3", 4096, 3432, squeeze_factors=(2.0,)),
        ImagerMode("4K 6:5", 4096, 3432, squeeze_factors=(2.0,)),
    ),
)

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

CAMERA_REGISTRY: dict[str, CameraModel] = {
    cam.camera_type: cam for cam in (VENICE_2_8K, VENICE_2_6K)
}

MODEL_CODE_REGISTRY: dict[str, CameraModel] = {
    cam.model_code: cam for cam in (VENICE_2_8K, VENICE_2_6K)
}


def get_camera(camera_type: str) -> CameraModel:
    """Look up a camera model by type string or model code (case-insensitive)."""
    key = camera_type.strip()
    for name, cam in CAMERA_REGISTRY.items():
        if name.lower() == key.lower():
            return cam
    for code, cam in MODEL_CODE_REGISTRY.items():
        if code.lower() == key.lower():
            return cam
    available = list(CAMERA_REGISTRY.keys()) + list(MODEL_CODE_REGISTRY.keys())
    raise KeyError(f"Camera {camera_type!r} not found. Available: {available}")


def get_camera_by_model_code(model_code: str) -> CameraModel:
    """Look up a camera model by its Sony model code (e.g. MPC-3628)."""
    key = model_code.strip().upper()
    if key in MODEL_CODE_REGISTRY:
        return MODEL_CODE_REGISTRY[key]
    available = list(MODEL_CODE_REGISTRY.keys())
    raise KeyError(f"Model code {model_code!r} not found. Available: {available}")


def list_cameras() -> list[CameraModel]:
    """Return all registered camera models."""
    return list(CAMERA_REGISTRY.values())
