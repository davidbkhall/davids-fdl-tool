"""Camera database sync from external sources."""

import json
from typing import Any


def sync_from_url(params: dict) -> dict:
    """Sync camera database from an external API.

    Params:
        source_url: str — URL to fetch camera data from
    """
    # Placeholder for future implementation
    return {"status": "not_implemented", "message": "Camera DB sync is not yet implemented"}


def load_bundled(db_path: str) -> dict:
    """Load the bundled camera database JSON."""
    with open(db_path) as f:
        return json.load(f)
