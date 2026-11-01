"""Exercise release preparation against disposable xcconfigs, never the checkout."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/set-version.sh"


class VersionScriptTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "Version.xcconfig"
        self.config.write_text(
            "// Shared by the app and widget.\n"
            "MARKETING_VERSION = 1.6.2\n"
            "CURRENT_PROJECT_VERSION = 452\n"
        )

    def run_script(self, *arguments):
        return subprocess.run(
            [str(SCRIPT), *arguments],
            cwd=ROOT,
            env={**os.environ, "VERSION_FILE": str(self.config)},
            capture_output=True,
            text=True,
        )

    def test_aligns_with_store_version_and_keeps_builds_increasing(self):
        result = self.run_script("1.1.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MARKETING_VERSION = 1.1.0\n", self.config.read_text())
        self.assertIn("CURRENT_PROJECT_VERSION = 453\n", self.config.read_text())
        result = self.run_script("1.1.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MARKETING_VERSION = 1.1.0\n", self.config.read_text())
        self.assertIn("CURRENT_PROJECT_VERSION = 454\n", self.config.read_text())

    def test_accepts_an_explicit_higher_build(self):
        result = self.run_script("1.1.0", "500")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CURRENT_PROJECT_VERSION = 500\n", self.config.read_text())

    def test_check_does_not_change_metadata(self):
        before = self.config.read_bytes()
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1.6.2 (452)", result.stdout)
        self.assertEqual(self.config.read_bytes(), before)

    def test_rejects_invalid_versions_and_builds_without_writing(self):
        before = self.config.read_bytes()
        cases = [
            (), ("1.1",), ("1.01.0",), ("1.1.0-beta",),
            ("1.1.0", "452"), ("1.1.0", "451"), ("1.1.0", "0"),
            ("1.1.0", "0453"), ("1.1.0", "not-a-build"),
            ("1.1.0", "453", "extra"),
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.run_script(*arguments).returncode, 0)
                self.assertEqual(self.config.read_bytes(), before)

    def test_rejects_malformed_metadata_without_writing(self):
        for content in [
            "MARKETING_VERSION = 1.1.0\n",
            "MARKETING_VERSION = 1.1.0\nCURRENT_PROJECT_VERSION = invalid\n",
            "MARKETING_VERSION = 1.1.0\nMARKETING_VERSION = 1.2.0\n"
            "CURRENT_PROJECT_VERSION = 452\n",
        ]:
            with self.subTest(content=content):
                self.config.write_text(content)
                self.assertNotEqual(self.run_script("1.1.0").returncode, 0)
                self.assertEqual(self.config.read_text(), content)


if __name__ == "__main__":
    unittest.main()
