import uuid

from pydantic import BaseModel, Field

from fdl.constants import DEFAULT_FDL_CREATOR, FDL_SCHEMA_MAJOR, FDL_SCHEMA_MINOR


class Version(BaseModel):
    major: int = FDL_SCHEMA_MAJOR
    minor: int = FDL_SCHEMA_MINOR


class Header(BaseModel):
    uuid: str = Field(default_factory=lambda: str(uuid.uuid4()))
    version: Version = Field(default_factory=Version)
    fdl_creator: str = Field(default=DEFAULT_FDL_CREATOR)
    default_framing_intent: str | None = None
