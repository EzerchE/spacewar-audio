"""Build the explicit policy-only KernelSU module package with fixed ZIP metadata."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parent
ASSET_NAME = "spacewar-audio-v1.3.0.zip"
FILES = (
    "README.md",
    "compatibility.sh",
    "configs/audio_policy_configuration_a2dp_offload_disabled.xml",
    "customize.sh",
    "module.prop",
    "post-fs-data.sh",
    "service.sh",
    "system.prop",
)


def build(output_dir=None):
    output = Path(output_dir) if output_dir is not None else ROOT / "dist"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ASSET_NAME
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name in FILES:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if name.endswith(".sh") else 0o644
            info.external_attr = (0o100000 | mode) << 16
            bundle.writestr(info, (ROOT / name).read_bytes(), compresslevel=9)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = output / (ASSET_NAME + ".sha256")
    checksum.write_text(f"{digest}  {ASSET_NAME}\n", encoding="ascii", newline="\n")
    return archive, checksum, digest


if __name__ == "__main__":
    archive, checksum, digest = build()
    print(f"{digest}  {archive.name}")
    print(checksum)
