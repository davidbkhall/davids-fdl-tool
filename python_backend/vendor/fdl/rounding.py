from __future__ import annotations

import math
from typing import TYPE_CHECKING, Annotated

from pydantic import BaseModel, Field, model_serializer

from fdl.constants import RoundingEven, RoundingMode

if TYPE_CHECKING:
    from fdl.common import Dimensions, Point


def fdl_round(value: float, even: str, mode: str) -> int:
    """Round a single float value according to FDL rounding rules.

    Handles negative values and rounding to whole or even numbers.

    Parameters
    ----------
    value : float
        The value to round.
    even : str
        Either "whole" or "even" to control rounding to whole or even numbers.
    mode : str
        Either "up", "down", or "round" to control rounding direction.

    Returns
    -------
    int
        The rounded value.
    """
    sign = 1
    if value < 0:
        sign = -1
        value = abs(value)

    if mode == RoundingMode.UP:
        v = math.ceil(value)
    elif mode == RoundingMode.DOWN:
        v = math.floor(value)
    else:  # round to nearest
        v = round(value)

    if even == RoundingEven.EVEN:
        if mode == RoundingMode.UP:
            v = v if v % 2 == 0 else v + 1
        elif mode == RoundingMode.DOWN:
            v = v if v % 2 == 0 else v - 1
        else:
            if v % 2 != 0:
                up = v + 1
                down = v - 1
                v = up if abs(up - value) <= abs(down - value) else down

    return sign * v


class RoundStrategy(BaseModel):
    even: Annotated[RoundingEven | None, Field(default=RoundingEven.EVEN)]
    mode: Annotated[RoundingMode | None, Field(default=RoundingMode.UP)]

    def round_dimensions(self, dimensions: Dimensions) -> Dimensions:  # type: ignore[type-var]
        """Round the provided dimensions based on the rules defined in this object.

        Uses fdl_round internally for consistent rounding behavior.
        """
        even = self.even or RoundingEven.EVEN
        mode = self.mode or RoundingMode.UP
        new_dim = dimensions.__class__()
        new_dim.width = fdl_round(dimensions.width, even, mode)
        new_dim.height = fdl_round(dimensions.height, even, mode)
        return new_dim

    def round_point(self, point: Point) -> Point:  # type: ignore[type-var]
        """Round the provided point based on the rules defined in this object.

        Uses fdl_round internally for consistent rounding behavior.
        """
        even = self.even or RoundingEven.EVEN
        mode = self.mode or RoundingMode.UP
        new_point = point.__class__()
        new_point.x = fdl_round(point.x, even, mode)
        new_point.y = fdl_round(point.y, even, mode)
        return new_point

    @model_serializer()
    def check_values(self) -> dict[str, str]:
        if self.even is None or self.even not in RoundingEven:
            raise ValueError(f'"{self.even}" is not a valid option for even. Please use one of: {list(RoundingEven)}')

        if self.mode is None or self.mode not in RoundingMode:
            raise ValueError(f'"{self.mode}" is not a valid option for mode. Please use one of: {list(RoundingMode)}')

        return {"even": self.even, "mode": self.mode}

    def __eq__(self, other):
        return self.even == other.even and self.mode == other.mode

    def __bool__(self):
        # Returns True when strategy has values (should be serialized)
        # Returns False when both are None (can be excluded)
        return self.even is not None or self.mode is not None
