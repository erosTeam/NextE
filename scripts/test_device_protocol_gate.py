#!/usr/bin/env python3
import json
import subprocess
import tempfile
from pathlib import Path

from device_lease import CHECKED_PROTOCOL_RUNNER, direct_device_protocol_violation


HDC = "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
TARGET = "192.168.50.237:12345"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
RUN_DEVICE_PROTOCOL = Path(__file__).resolve().parent / "run-device-protocol"
MANIFEST = str(
    PROJECT_ROOT / "scripts" / "device_protocol_gate_fixture.json"
)


def assert_allowed(command: list[str]) -> None:
    reason = direct_device_protocol_violation(command, TARGET)
    assert reason is None, f"expected allowed command, got: {reason}"


def assert_denied(command: list[str]) -> None:
    reason = direct_device_protocol_violation(command, TARGET)
    assert reason is not None, "expected command to be denied"


assert_allowed([HDC, "tconn", TARGET])
assert_allowed([HDC, "-t", TARGET, "shell", "echo", "ok"])
assert_allowed([HDC, "-t", TARGET, "shell", "param", "get", "bootevent.boot.completed"])
assert_allowed([HDC, "-t", TARGET, "file", "recv", "/data/local/tmp/a", "/tmp/a"])
assert_allowed(
    [
        "python3",
        str(CHECKED_PROTOCOL_RUNNER),
        MANIFEST,
    ]
)

assert_denied([HDC, "-t", TARGET, "shell", "power-shell", "wakeup"])
assert_denied([HDC, "-t", TARGET, "shell", "power-shell", "timeout", "-o", "86400000"])
assert_denied([HDC, "-t", TARGET, "shell", "uitest", "uiInput", "click", "1", "1"])
assert_denied([HDC, "-t", TARGET, "shell", "uinput", "-T", "-c", "1", "1"])
assert_denied([HDC, "-t", TARGET, "shell", "snapshot_display", "-f", "/tmp/a.jpeg"])
assert_denied([HDC, "-t", TARGET, "shell", "uitest", "dumpLayout", "-p", "/tmp/a.json"])
assert_denied([HDC, "-t", TARGET, "install", "-r", "/tmp/app.hap"])
assert_denied([HDC, "-t", "192.168.50.103:12345", "shell", "echo", "ok"])
assert_denied([HDC, "shell", "echo", "ok"])
assert_denied([HDC, "-t", TARGET, "shell", "echo", "ok", ";", "power-shell", "wakeup"])
assert_denied(["/bin/zsh", "-lc", f"{HDC} -t {TARGET} shell power-shell wakeup"])
assert_denied(["python3", "/tmp/run_device_protocol.py", "/tmp/protocol.json"])
assert_denied(["python3", str(CHECKED_PROTOCOL_RUNNER), "/tmp/protocol.json"])
assert_denied(["python3", "scripts/drive_device_directly.py"])
assert_denied(["node", "scripts/drive_device_directly.mjs"])

manifest_directory = Path(MANIFEST).parent
with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=manifest_directory,
    prefix=".authority-mismatch-",
    suffix=".json",
    delete=False,
) as temporary_manifest:
    json.dump(
        {
            "target": TARGET,
            "authorizedTarget": "192.168.50.197:12345",
        },
        temporary_manifest,
    )
    mismatch_manifest = temporary_manifest.name

try:
    assert_denied(["python3", str(CHECKED_PROTOCOL_RUNNER), mismatch_manifest])
    wrapper_result = subprocess.run(
        [
            str(RUN_DEVICE_PROTOCOL),
            "--device",
            TARGET,
            "--lease",
            "must-not-be-read",
            mismatch_manifest,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert wrapper_result.returncode == 2, wrapper_result
    assert "manifest authorization mismatch" in wrapper_result.stderr, wrapper_result
finally:
    Path(mismatch_manifest).unlink(missing_ok=True)

# NextE keeps reference device protocols under docs/device-protocols/ (tracked).
# Run-specific manifests still belong in an ignored artifact root; that rule is
# enforced by the project guide, not by this gate test.

print("device protocol gate: pass")
