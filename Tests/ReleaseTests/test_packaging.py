"""Exercise the distribution boundary with a small, genuinely signed app bundle."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cove-package-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "Cove.app"
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        shutil.copyfile("/usr/bin/true", contents / "MacOS/Cove")
        (contents / "MacOS/Cove").chmod(0o755)
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleIdentifier": "io.github.huyanxius.cove.packaging-test",
                "CFBundleExecutable": "Cove", "CFBundleName": "Cove",
                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0",
            }, stream)
        for name in ("LICENSE", "SwiftTerm-LICENSE"):
            (contents / "Resources" / name).write_text("MIT test fixture\n")
        terminal = contents / "Resources/SwiftTerm_SwiftTerm.bundle"
        terminal.mkdir()
        (terminal / "Shaders.metal").write_text("// test shader resource\n")
        subprocess.run(["codesign", "--force", "--sign", "-", str(self.app)], check=True, capture_output=True)
        self.output = self.root / "distribution"

    def package(self):
        return subprocess.run(["bash", str(ROOT / "scripts/package-release.sh"), str(self.app), str(self.output)],
                              capture_output=True, text=True)

    def test_packages_signed_bundle_and_checksums(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archives = list(self.output.glob("Cove-macOS-*.zip"))
        self.assertEqual(len(archives), 1)
        with zipfile.ZipFile(archives[0]) as archive:
            self.assertIn("Cove.app/Contents/MacOS/Cove", archive.namelist())
            self.assertIn("Cove.app/Contents/Resources/SwiftTerm-LICENSE", archive.namelist())
            self.assertIn("Cove.app/Contents/Resources/SwiftTerm_SwiftTerm.bundle/Shaders.metal", archive.namelist())
        self.assertEqual(len(list(self.output.glob("*.dmg"))), 1)
        subprocess.run(["shasum", "-a", "256", "-c", "SHA256SUMS.txt"], cwd=self.output, check=True, capture_output=True)

    def test_rejects_tampered_bundle_before_packaging(self):
        (self.app / "Contents/Resources/LICENSE").write_text("tampered after signing")
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())

    def test_rejects_missing_terminal_resources(self):
        shutil.rmtree(self.app / "Contents/Resources/SwiftTerm_SwiftTerm.bundle")
        subprocess.run(["codesign", "--force", "--sign", "-", str(self.app)], check=True, capture_output=True)
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())

    def test_preserves_existing_release_assets(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_text("existing release")
        result = self.package()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), "existing release")
        self.assertEqual(list(self.output.iterdir()), [marker])


if __name__ == "__main__":
    unittest.main()
