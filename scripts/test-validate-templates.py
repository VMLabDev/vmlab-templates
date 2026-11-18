"""Check host-dependent validation diagnostics without host configuration."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "validate_templates", Path(__file__).with_name("validate-templates.py")
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ValidationTests(unittest.TestCase):
    def validate_output(self, output, returncode=1):
        result = subprocess.CompletedProcess([], returncode, "", output)
        with patch.object(validator.subprocess, "run", return_value=result):
            return validator.validate(Path("examples/macos-tahoe"), set())

    def test_missing_smc_key_is_explained(self):
        excused, unexplained = self.validate_output(
            "  × " + validator.MISSING_APPLE_SMC_OSK
        )
        self.assertEqual(len(excused), 1)
        self.assertIn("host Apple SMC OSK", excused[0])
        self.assertEqual(unexplained, [])

    def test_wrapped_missing_smc_key_is_explained(self):
        output = (
            "  × apple_smc = true requires host.apple_smc_osk in\n"
            "  │ ~/.config/vmlab/\n"
            "  │ config.wcl; obtain it from your own Apple hardware.\n"
            "  │ See docs/manual/pages/reference/host-config.wcl (Apple SMC OSK)\n"
        )
        excused, unexplained = self.validate_output(output)
        self.assertEqual(len(excused), 1)
        self.assertEqual(unexplained, [])

    def test_missing_key_does_not_hide_other_errors(self):
        excused, unexplained = self.validate_output(
            "  × " + validator.MISSING_APPLE_SMC_OSK + "\n  × unknown field typo\n"
        )
        self.assertEqual(len(excused), 1)
        self.assertEqual(unexplained, ["unknown field typo"])

    def test_other_smc_errors_fail(self):
        for message in (
            "host.apple_smc_osk must be exactly 64 printable ASCII characters",
            validator.MISSING_APPLE_SMC_OSK + " unexpected suffix",
        ):
            with self.subTest(message=message):
                excused, unexplained = self.validate_output("  × " + message)
                self.assertEqual(excused, [])
                self.assertEqual(unexplained, [message])

    def test_unrecognised_failure_fails(self):
        self.assertEqual(self.validate_output("unexpected failure"),
                         ([], ["unexpected failure"]))

    def test_missing_vulkan_render_node_is_explained(self):
        diagnostic = (
            "vmlab-hv renders `vulkan` on a host GPU's render node, and this host has none — "
            'declare `gpu "<name>" { address = ... }` in ~/.config/vmlab/config.wcl, '
            'or use hypervisor = "qemu"'
        )
        for template in ('template "steamos"', 'template "windows-10" variant "win3d"'):
            with self.subTest(template=template):
                excused, unexplained = self.validate_output(
                    f"  × {template}: {diagnostic}\n  × unknown field typo\n"
                )
                self.assertEqual(excused, [f"{template} (no host Vulkan render node; skipped)"])
                self.assertEqual(unexplained, ["unknown field typo"])

    def test_success_needs_no_skip(self):
        self.assertEqual(self.validate_output("", returncode=0), ([], []))


if __name__ == "__main__":
    unittest.main()
