import os
import pathlib
import shutil
import urllib.request

from hatchling.builders.hooks.plugin.interface import BuildHookInterface

MODULE_NAME = "mep_rfsoc_sdr"
RELEASE_BASE_URL = "https://github.com/spectrumx/mep-rfsoc-sdr/releases"
DIST_BITSTREAM_DIR = pathlib.Path(__file__).absolute().parent / "dist" / "bitstream"
UNKNOWN_VERSION_VALUES = {"", "none", "standard", "unknown"}


def download_file(url, destination):
    """Download a file from URL to destination"""
    print(f"Downloading {url} to {destination}")
    urllib.request.urlretrieve(url, destination)
    print(f"Successfully downloaded {os.path.basename(destination)}")


def version_is_known(version):
    return str(version).strip().lower() not in UNKNOWN_VERSION_VALUES


def release_asset_url(asset_name, version=None):
    if version_is_known(version):
        return f"{RELEASE_BASE_URL}/download/v{version}/{asset_name}"
    return f"{RELEASE_BASE_URL}/latest/download/{asset_name}"


def download_release_asset(asset_name, version, destination):
    if version_is_known(version):
        try:
            download_file(release_asset_url(asset_name, version), destination)
            return
        except Exception as exc:
            print(
                f"Could not download {asset_name} for version {version}: {exc}. "
                "Falling back to the latest GitHub release."
            )

    download_file(release_asset_url(asset_name), destination)


def stage_bitstream_asset(asset_name, version, src_file):
    dist_file = DIST_BITSTREAM_DIR / asset_name
    if src_file.exists():
        shutil.copy2(src_file, dist_file)
        return
    if dist_file.exists():
        return

    print(f"Required {asset_name} file not found locally. Attempting to download...")
    download_release_asset(asset_name, version, dist_file)


def force_include_destination(target_name):
    if target_name == "wheel":
        return "mep_rfsoc_sdr/bitstream"
    return "src/bitstream"


class BitstreamHook(BuildHookInterface):
    def clean(self, versions) -> None:
        if DIST_BITSTREAM_DIR.exists():
            for childpath in DIST_BITSTREAM_DIR.iterdir():
                if childpath.name.endswith(".bit") or childpath.name.endswith(".hwh"):
                    childpath.unlink()
            try:
                DIST_BITSTREAM_DIR.rmdir()
            except OSError:
                pass

    def initialize(self, version, build_data) -> None:
        DIST_BITSTREAM_DIR.mkdir(exist_ok=True, parents=True)

        src_bitstream_dir = (
            pathlib.Path(__file__).absolute().parent / "src" / "bitstream"
        )
        src_bitstream_file = src_bitstream_dir / "sdr_bitstream.bit"
        src_hwh_file = src_bitstream_dir / "sdr_bitstream.hwh"

        stage_bitstream_asset("sdr_bitstream.bit", version, src_bitstream_file)
        stage_bitstream_asset("sdr_bitstream.hwh", version, src_hwh_file)

        build_data["force_include"][str(DIST_BITSTREAM_DIR)] = (
            force_include_destination(self.target_name)
        )

    def finalize(self, version, build_data, artifact_path) -> None:
        pass
