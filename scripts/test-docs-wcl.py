"""Check docs CLI selection without installing tools or using the network."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class DocsWclTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / "scripts").mkdir()
        shutil.copyfile(Path(__file__).with_name("docs-wcl.sh"), self.repo / "scripts/docs-wcl.sh")
        self.rev = "ed84924565334008ae0656be78e29338328c8419"
        (self.repo / ".wcl-rev").write_text(self.rev + "\n")
        self.root = self.repo / ".scratch/tools/wcl" / self.rev
        self.bin = self.repo / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"]}

    def run_cli(self, *args):
        return subprocess.run(
            ["bash", str(self.repo / "scripts/docs-wcl.sh"), *args],
            cwd="/tmp",
            env=self.env,
            capture_output=True,
            text=True,
        )

    def executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def test_missing_pin_does_not_use_host_wcl(self):
        self.executable(self.bin / "wcl", "exit 99\n")
        result = self.run_cli("--version")
        self.assertEqual(result.returncode, 1)
        self.assertIn("just docs-tool-install", result.stderr)

    def test_passes_arguments_to_pinned_binary(self):
        self.executable(self.root / "bin/wcl", "printf '%s\\n' \"$@\"\nexit 17\n")
        result = self.run_cli("wdoc", "build", "path with spaces.wcl")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout.splitlines(), ["wdoc", "build", "path with spaces.wcl"])

    def test_install_uses_pin_and_isolated_root(self):
        self.executable(self.bin / "cargo", "printf '%s\\n' \"$@\"\n")
        result = self.run_cli("--install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "install", "--git", "https://github.com/wiltaylor/wcl.git",
            "--rev", self.rev, "--locked", "--root", str(self.root), "wcl",
        ])


if __name__ == "__main__":
    unittest.main()
