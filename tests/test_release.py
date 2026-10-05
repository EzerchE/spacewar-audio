import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
POLICY = "configs/audio_policy_configuration_a2dp_offload_disabled.xml"
ORIGINAL = "c17b85f06f23432ec412dbaed6211bfc57476276fe8c15f453f3350f26b6e537"
PATCHED = "ad2cb00ca2db53716f2ba301702c9148dc95a42bfb9196400b47220cbd47551c"
PROPERTIES = "d5fe477f10e40e176e46251eda9fb308bbffd3182c4c031a75c2f29daad1f90e"


def shell_binary():
    git = shutil.which("git")
    if git:
        candidate = Path(git).parent.parent / "bin/bash.exe"
        if candidate.is_file():
            return str(candidate)
    candidate = shutil.which("bash")
    if candidate:
        return candidate
    raise unittest.SkipTest("Git Bash or Bash is required for shell checks")


def run_shell(script, syntax=False):
    args = [shell_binary(), "--noprofile", "--norc", "--posix", "-n" if syntax else "-s"]
    return subprocess.run(args, input=script, text=True, capture_output=True, timeout=10)


class ReleaseTests(unittest.TestCase):
    def test_shell_syntax(self):
        for source in ROOT.glob("*.sh"):
            with self.subTest(source=source.name):
                result = run_shell(source.read_text(), syntax=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_validated_payload(self):
        payload = (ROOT / POLICY).read_bytes()
        ET.fromstring(payload)
        self.assertEqual(hashlib.sha256(payload).hexdigest(), PATCHED)
        self.assertNotIn(b'a2dp_in_audio_policy_configuration.xml', payload)
        self.assertIn(b'Copyright', payload)
        self.assertEqual(hashlib.sha256((ROOT / "system.prop").read_bytes()).hexdigest(), PROPERTIES)

    def test_release_metadata(self):
        metadata = dict(line.split("=", 1) for line in (ROOT / "module.prop").read_text().splitlines())
        self.assertEqual(metadata["id"], "spacewar-audio")
        self.assertEqual(metadata["version"], "1.3.0")
        self.assertEqual(metadata["versionCode"], "130")
        self.assertEqual((ROOT / "service.sh").read_text().splitlines()[-1], "exit 0")
        for obsolete in ["guardian.sh", "config.conf", "defaults.conf", "configs/audio"]:
            self.assertFalse((ROOT / obsolete).exists(), obsolete)
        self.assertFalse(list(ROOT.glob("*.zip")))

    def test_deterministic_allowlist_package(self):
        spec = importlib.util.spec_from_file_location("module_build", ROOT / "build.py")
        build_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build_module)
        with tempfile.TemporaryDirectory() as temporary:
            first, checksum, digest = build_module.build(Path(temporary) / "first")
            second, _, second_digest = build_module.build(Path(temporary) / "second")
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(digest, second_digest)
            self.assertEqual(checksum.read_text(), f"{digest}  {first.name}\n")
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist(), list(build_module.FILES))
                self.assertEqual(len(archive.namelist()), 8)
                for member in archive.infolist():
                    self.assertEqual(member.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertEqual(archive.read(member), (ROOT / member.filename).read_bytes())
                    expected_mode = 0o755 if member.filename.endswith(".sh") else 0o644
                    self.assertEqual((member.external_attr >> 16) & 0o777, expected_mode)

    def test_post_fs_compatibility_and_mount_guards(self):
        cases = [
            ("original", "", 0, "chmod\nchcon\nmount\n"),
            ("lowercase_device", "DEVICE=spacewar", 0, "chmod\nchcon\nmount\n"),
            ("already_patched", "TARGET_SHA=$PATCHED", 0, ""),
            ("other_device", "DEVICE=other", 0, ""),
            ("other_model", "MODEL=other", 0, ""),
            ("other_release", "RELEASE=15", 0, ""),
            ("other_sdk", "SDK=35", 0, ""),
            ("unknown_target", "TARGET_SHA=unknown", 0, ""),
            ("unknown_payload", "PAYLOAD_SHA=unknown", 0, ""),
            ("missing_target", 'rm "$T/vendor/policy.xml"', 0, ""),
            ("missing_payload", 'rm "$T/module/configs/audio_policy_configuration_a2dp_offload_disabled.xml"', 0, ""),
            ("input_present", 'touch "$T/vendor/input.xml"', 0, ""),
            ("input_directory_present", 'mkdir "$T/vendor/input.xml"', 0, ""),
            ("checksum_failure", "SHA_FAIL=1", 0, ""),
            ("permission_failure", "FAIL_STEP=chmod", 1, ""),
            ("label_failure", "FAIL_STEP=chcon", 1, "chmod\n"),
            ("mount_failure", "FAIL_STEP=mount", 1, "chmod\nchcon\n"),
        ]
        compatibility = (ROOT / "compatibility.sh").read_text()
        compatibility = compatibility.replace("/vendor/etc/audio_policy_configuration_a2dp_offload_disabled.xml", '"$T/vendor/policy.xml"')
        compatibility = compatibility.replace("/vendor/etc/a2dp_in_audio_policy_configuration.xml", '"$T/vendor/input.xml"')
        post_fs = (ROOT / "post-fs-data.sh").read_text().replace("MODDIR=${0%/*}", 'MODDIR="$T/module"')
        for name, setup, expected_exit, expected_actions in cases:
            with self.subTest(case=name):
                fixture = f"""T=$(mktemp -d) || exit 90
mkdir -p "$T/module/configs" "$T/vendor"
touch "$T/module/configs/audio_policy_configuration_a2dp_offload_disabled.xml" "$T/vendor/policy.xml" "$T/actions"
cat > "$T/module/compatibility.sh" <<'FIXTURE_GUARD'
{compatibility}FIXTURE_GUARD
ORIGINAL={ORIGINAL}
PATCHED={PATCHED}
TARGET_SHA=$ORIGINAL
PAYLOAD_SHA=$PATCHED
DEVICE=Spacewar; MODEL=A063; RELEASE=16; SDK=36; SHA_FAIL=0; FAIL_STEP=
getprop() {{
 case "$1" in
  ro.product.device) printf '%s\\n' "$DEVICE" ;;
  ro.product.model) printf '%s\\n' "$MODEL" ;;
  ro.build.version.release) printf '%s\\n' "$RELEASE" ;;
  ro.build.version.sdk) printf '%s\\n' "$SDK" ;;
 esac
}}
sha256sum() {{
 [ "$SHA_FAIL" = 0 ] || return 1
 case "$1" in
  "$T/vendor/policy.xml") printf '%s  %s\\n' "$TARGET_SHA" "$1" ;;
  *) printf '%s  %s\\n' "$PAYLOAD_SHA" "$1" ;;
 esac
}}
chmod() {{ [ "$FAIL_STEP" != chmod ] || return 1; printf 'chmod\\n' >> "$T/actions"; }}
chcon() {{ [ "$FAIL_STEP" != chcon ] || return 1; printf 'chcon\\n' >> "$T/actions"; }}
mount() {{ [ "$FAIL_STEP" != mount ] || return 1; printf 'mount\\n' >> "$T/actions"; }}
{setup}
(
{post_fs})
result=$?
printf 'RESULT=%s\\n' "$result"
cat "$T/actions"
rm -rf "$T"
"""
                result = run_shell(fixture)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, f"RESULT={expected_exit}\n{expected_actions}", result.stderr)

    def test_installer_rejects_unsupported_baseline(self):
        source = (ROOT / "customize.sh").read_text().replace('. "$MODPATH/compatibility.sh" || abort "Compatibility check unavailable."', "")
        for supported in (True, False):
            with self.subTest(supported=supported):
                script = f"""MODPATH=/unused
compatible_policy() {{ return {0 if supported else 1}; }}
abort() {{ printf '%s\\n' "$1"; exit 1; }}
ui_print() {{ printf '%s\\n' "$1"; }}
{source}"""
                result = run_shell(script)
                self.assertEqual(result.returncode, 0 if supported else 1)
                self.assertIn("supported policy baseline confirmed" if supported else "Unsupported baseline", result.stdout)


if __name__ == "__main__":
    unittest.main()
