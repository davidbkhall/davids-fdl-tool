from typing import Annotated

from pydantic import BaseModel, Field

from fdl.types import DimensionsInt


class FramingIntent(BaseModel):
    label: str | None = None
    id: Annotated[str, Field(min_length=1, max_length=32)]
    aspect_ratio: DimensionsInt
    protection: Annotated[float, Field(default=0)]

    def __eq__(self, other: object) -> bool:
        if isinstance(other, FramingIntent):
            return self.id == other.id
        if isinstance(other, str):
            return self.id == other
        return NotImplemented

    def __hash__(self):
        return hash((self.id,))

    def __str__(self) -> str:
        return self.__repr__()
