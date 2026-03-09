from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING

import jsonschema

from fdl import FDL, FDLValidationError
from fdl.fdlchecker import FDLValidator

if TYPE_CHECKING:
    from fdl.plugins.registry import PluginRegistry

_SCHEMA_BASE = Path(__file__).absolute().parent.parent / "schema"


class FDLHandler:
    def __init__(self):
        """
        The default built-in FDL handler. Takes care of reading and writing FDL files
        """
        self.name = "fdl"
        self.suffixes = [".fdl"]

    @staticmethod
    def _load_schema(fdl_dict: dict) -> dict:
        """Load the JSON schema matching the FDL document's version.

        Extracts ``version.major`` and ``version.minor`` from the dict
        and resolves the schema directory, preferring the latest patch
        version if available.
        """
        version = fdl_dict.get("version", {})
        major = version.get("major", 2)
        minor = version.get("minor", 0)

        prefix = f"v{major}.{minor}"
        patch_dirs = sorted(_SCHEMA_BASE.glob(f"{prefix}.*"))
        schema_dir = patch_dirs[-1] if patch_dirs else _SCHEMA_BASE / prefix

        schema_path = schema_dir / "ascfdl.schema.json"
        with schema_path.open("r") as f:
            schema: dict = json.load(f)
            return schema

    def validate_schema(self, fdl_dict: dict) -> tuple[int, list[str]]:
        """Validate an FDL dict against the JSON schema.

        This is the format-specific validation step. Other handlers
        (e.g. a future YAML handler) would override this method with
        their own schema validation.

        Args:
            fdl_dict: serialized FDL document

        Returns:
            Tuple of (error_count, error_messages)
        """
        errors = 0
        error_msgs: list[str] = []

        schema = self._load_schema(fdl_dict)
        validator_cls = jsonschema.validators.validator_for(schema)
        validator = validator_cls(schema=schema, format_checker=validator_cls.FORMAT_CHECKER)
        for error in validator.iter_errors(fdl_dict):
            error_msgs.append(str(error))
            errors += 1

        return errors, error_msgs

    def validate(self, fdl: FDL) -> None:
        """Run full validation: format-specific schema then semantic checks.

        Args:
            fdl: the FDL object to validate

        Raises:
            FDLValidationError: if any schema or semantic errors are found
        """
        fdl_dict = fdl.model_dump(by_alias=True, exclude_none=True)

        # Format-specific schema validation
        error_count, error_msgs = self.validate_schema(fdl_dict)
        if error_count > 0:
            msg = "Schema validation failed!\n" + "\n".join(error_msgs)
            raise FDLValidationError(msg)

        # Universal semantic validation
        error_count, error_msgs = FDLValidator.validate(fdl_dict)
        if error_count > 0:
            msg = "Validation failed!\n" + "\n".join(error_msgs)
            raise FDLValidationError(msg)

    def read_from_file(self, path: Path, validate: bool = True) -> FDL:
        """Read an FDL from a file.

        Args:
            path: to fdl file
            validate: run schema and semantic validation

        Raises:
            FDLValidationError: if validation fails

        Returns:
            FDL:
        """
        with path.open("r") as fp:
            raw = fp.read()
            return self.read_from_string(raw, validate=validate)

    def read_from_string(self, s: str, validate: bool = True) -> FDL:
        """Read an FDL from a string.

        Args:
            s: string representation of an FDL
            validate: run schema and semantic validation

        Raises:
            FDLValidationError: if validation fails

        Returns:
            FDL:
        """
        fdl = FDL.model_validate_json(s)

        if validate:
            self.validate(fdl)

        return fdl

    def write_to_file(self, fdl: FDL, path: Path, validate: bool = True, indent: int | None = 2):
        """Dump an FDL to a file.

        Args:
            fdl: object to serialize
            path: path to store fdl file
            validate: run schema and semantic validation
            indent: amount of spaces

        Raises:
            FDLValidationError: if validation fails
        """
        with path.open("w") as fp:
            fp.write(self.write_to_string(fdl, validate=validate, indent=indent))

    def write_to_string(self, fdl: FDL, validate: bool = True, indent: int | None = 2) -> str:
        """Dump an FDL to string.

        Args:
            fdl: object to serialize
            validate: run schema and semantic validation
            indent: amount of spaces

        Raises:
            FDLValidationError: if validation fails

        Returns:
            string representation of the resulting json
        """
        if validate:
            self.validate(fdl)

        return fdl.model_dump_json(indent=indent, exclude_none=True)


def register_plugin(registry: PluginRegistry):
    """
    Mandatory function to register handler in the registry. Called by the PluginRegistry itself.

    Args:
        registry: The PluginRegistry passes itself to this function
    """
    registry.add_handler(FDLHandler())
