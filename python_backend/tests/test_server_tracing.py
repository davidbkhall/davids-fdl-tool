from __future__ import annotations

import json

from fdl_backend import server


def test_request_id_from_params_extracts_string() -> None:
    assert server._request_id_from_params({"request_id": "req-123"}) == "req-123"


def test_request_id_from_params_handles_missing() -> None:
    assert server._request_id_from_params({}) == ""
    assert server._request_id_from_params(None) == ""


def test_trace_event_writes_json_payload(monkeypatch) -> None:
    captured: list[str] = []

    class _Err:
        def write(self, value: str) -> None:
            captured.append(value)

        def flush(self) -> None:
            pass

    monkeypatch.setattr(server.sys, "stderr", _Err())
    server._trace_event("rpc_request_received", request_id="req-abc", method="chart.generate_svg")

    assert captured
    line = captured[0]
    assert line.startswith("[trace] ")
    payload = json.loads(line[len("[trace] ") :].strip())
    assert payload["event"] == "rpc_request_received"
    assert payload["request_id"] == "req-abc"
    assert payload["method"] == "chart.generate_svg"
    assert isinstance(payload["ts_ms"], int)
