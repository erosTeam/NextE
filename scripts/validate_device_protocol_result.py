#!/usr/bin/env python3
"""Reject successful HDC exits whose device operation actually failed."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REPORT = re.compile(
    r"Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+)"
)


def fail(message: str) -> None:
    raise SystemExit(f"device protocol result rejected: {message}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_device_protocol_result.py <manifest.json>")
    manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    metadata_path = Path(manifest["artifactDir"]) / "run-metadata.json"
    if not metadata_path.is_file():
        fail(f"missing metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("status") != "completed":
        fail(f"runner status is {metadata.get('status')!r}")

    for command in metadata.get("commands", []):
        name = str(command.get("name", "unnamed"))
        argv = command.get("argv", [])
        stdout = str(command.get("stdout", ""))
        stderr = str(command.get("stderr", ""))
        combined = stdout + "\n" + stderr

        is_aa_test = any(
            argv[index:index + 3] == ["shell", "aa", "test"]
            for index in range(max(0, len(argv) - 2))
        )
        if is_aa_test:
            match = REPORT.search(stdout)
            if match is None:
                fail(f"{name} did not publish a Hypium result summary")
            run, failure, error, passed = (int(value) for value in match.groups())
            if run <= 0 or failure != 0 or error != 0 or passed != run:
                fail(
                    f"{name} Hypium summary was run={run}, failure={failure}, "
                    f"error={error}, pass={passed}"
                )

        recv_index = next(
            (index for index in range(len(argv) - 1)
             if argv[index:index + 2] == ["file", "recv"]),
            None,
        )
        if recv_index is not None and recv_index + 3 < len(argv):
            if "[Fail]" in combined or "Error opening file:" in combined:
                fail(f"{name} reported an HDC receive failure")
            destination = Path(argv[recv_index + 3])
            if not destination.is_file() or destination.stat().st_size == 0:
                fail(f"{name} did not produce a non-empty local artifact: {destination}")

    print("device protocol result: pass")


if __name__ == "__main__":
    main()
