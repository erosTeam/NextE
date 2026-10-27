#!/usr/bin/env python3
"""Exercise the gate with SDK-shaped logs, including the cached-build failure path."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import check_api_compatibility_warnings as gate


class ApiCompatibilityGateTest(unittest.TestCase):
    def test_new_warnings_and_incomplete_builds_fail(self):
        warning = (
            f"ArkTS:WARN File: {gate.ROOT}/shared/example.ets:9:3\n"
            " The 'systemMaterial' API is supported since SDK version 26.0.0. "
            "However, the current compatible SDK version is 6.1.0(23).\n"
        )
        completion = "Finished :entry:default@CompileArkTS...\nBUILD SUCCESSFUL\n"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline = root / "baseline.json"
            log = root / "build.log"
            baseline.write_text(json.dumps({"schema": 1, "warnings": [{
                "file": "shared/example.ets", "api": "systemMaterial", "since": "26.0.0",
                "compatible": "6.1.0(23)", "count": 1,
            }]}))
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                log.write_text(warning + completion)
                self.assertEqual(gate.check(log, baseline), 0)
                log.write_text(warning + warning + completion)
                self.assertEqual(gate.check(log, baseline), 1)
                log.write_text(warning + "UP-TO-DATE :entry:default@CompileArkTS...\nBUILD SUCCESSFUL\n")
                self.assertEqual(gate.check(log, baseline), 2)
                log.write_text(completion)
                self.assertEqual(gate.check(log, baseline), 2)
                baseline.write_text(json.dumps({"schema": 1, "warnings": []}))
                self.assertEqual(gate.check(log, baseline), 0)
                log.write_text(warning + completion)
                self.assertEqual(gate.check(log, baseline), 1)
                log.write_text("The unexpected API is supported since SDK version ???\n" + completion)
                self.assertEqual(gate.check(log, baseline), 2)


if __name__ == "__main__":
    unittest.main()
