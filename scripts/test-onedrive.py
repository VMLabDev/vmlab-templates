"""Focused checks for the standalone Windows OneDrive provisions."""

import unittest
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
MODERN = ("windows-10", "windows-11", "windows-11-arm64")
LEGACY = ("windows-8.1", "windows-8.1-x86")
NS = {"u": "urn:schemas-microsoft-com:unattend"}


class OneDriveProvisionTests(unittest.TestCase):
    def test_modern_payloads_are_identical(self):
        payloads = [(ROOT / name / "unattend/remove-onedrive.ps1").read_bytes()
                    for name in MODERN]
        self.assertTrue(all(payload == payloads[0] for payload in payloads))

    def test_removal_precedes_generalize(self):
        for name in MODERN:
            with self.subTest(template=name):
                script = (ROOT / name / "scripts/install.ws").read_text()
                end = ("sysprep(lab, vm)" if name.endswith("arm64")
                       else "stage_sysprep(lab, vm)?")
                self.assertLess(script.index("remove_onedrive(lab, vm)?"),
                                script.index(end))
                self.assertIn('stage_script(lab, vm, "remove-onedrive.ps1")?', script)
                self.assertIn('r.exit_code != 0 || !r.stdout.contains("ONEDRIVE_REMOVED=OK")',
                              script)
                self.assertIn('r.exit_code == 3010 && r.stdout.contains("ONEDRIVE_REMOVED=REBOOT")',
                              script)
                self.assertIn('vm.wait_rebooted(before, 900)?', script)
                self.assertIn('script, "-CleanupOnly"', script)

    def test_modern_uninstall_and_default_hive(self):
        script = (ROOT / "windows-11/unattend/remove-onedrive.ps1").read_text()
        for required in ("SysWOW64\\OneDriveSetup.exe", "System32\\OneDriveSetup.exe",
                         "'/uninstall'", "'/uninstall /allusers'", "'NTUSER.DAT'",
                         "'OneDriveSetup'", "'DisableFileSyncNGSC'",
                         "'load', $root, $hive", "'unload', $root"):
            with self.subTest(required=required):
                self.assertIn(required, script)
        self.assertIn("finally {", script)
        self.assertNotIn("Invoke-Reg @(", script)
        self.assertNotIn("Test-RegEntry @(", script)

    def test_legacy_payloads_are_identical(self):
        self.assertEqual(
            (ROOT / LEGACY[0] / "unattend/disable-onedrive.ps1").read_bytes(),
            (ROOT / LEGACY[1] / "unattend/disable-onedrive.ps1").read_bytes())

    def test_user_uninstall_uses_interactive_token_and_checks_result(self):
        script = (ROOT / "windows-11/unattend/remove-onedrive.ps1").read_text()
        self.assertIn("-LogonType Interactive -RunLevel Highest", script)
        self.assertIn("$info.LastTaskResult -notin @(0, 3010)", script)
        self.assertIn("Unregister-ScheduledTask -TaskName $name -Confirm:$false", script)
        self.assertIn("CurrentVersion\\RunOnce", script)

    def test_legacy_policy_guards_sysprep(self):
        for name in LEGACY:
            with self.subTest(template=name):
                tree = ElementTree.parse(ROOT / name / "unattend/autounattend.xml")
                commands = tree.findall(".//u:FirstLogonCommands/u:SynchronousCommand", NS)
                last = max(commands, key=lambda c: int(c.findtext("u:Order", namespaces=NS)))
                command = last.findtext("u:CommandLine", namespaces=NS)
                self.assertIn("if exist %d:\\disable-onedrive.ps1", command)
                self.assertIn("-File %d:\\disable-onedrive.ps1 &&", command)
                self.assertIn("sysprep.exe /generalize", command)
                script = (ROOT / name / "unattend/disable-onedrive.ps1").read_text()
                self.assertIn("'DisableFileSync', 'DisableFileSyncNGSC'", script)
                self.assertIn("Windows\\SkyDrive", script)


if __name__ == "__main__":
    unittest.main()
