import os
import pathlib
import shutil
import urllib.request

from hatchling.builders.hooks.plugin.interface import BuildHookInterface
from hatchling.metadata.core import ProjectMetadata
from hatchling.plugin.manager import PluginManager

MODULE_NAME = "mep_rfsoc_sdr"
RELEASE_BASE_URL = "https://github.com/spectrumx/mep-rfsoc-sdr/releases"
UNKNOWN_VERSION_VALUES = {"", "none", "standard", "unknown", "0.0.0"}


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


def stage_bitstream_asset(asset_name, version, dist_bitstream_dir, src_file):
    dist_file = dist_bitstream_dir / asset_name
    if src_file.exists():
        shutil.copy2(src_file, dist_file)
        return
    if dist_file.exists():
        return

    print(f"Required {asset_name} file not found locally. Attempting to download...")
    download_release_asset(asset_name, version, dist_file)


def force_include_destination(target_name):
    if target_name == "wheel":
        return f"{MODULE_NAME}/bitstream"
    return "src/bitstream"


class BitstreamHook(BuildHookInterface):
    def clean(self, _versions) -> None:
        build_path = pathlib.Path(self.directory)
        if build_path.exists():
            for childpath in build_path.iterdir():
                if childpath.is_dir() and childpath.name.startswith("bitstream"):
                    for bitpath in childpath.iterdir():
                        if bitpath.name.endswith(".bit") or bitpath.name.endswith(
                            ".hwh"
                        ):
                            bitpath.unlink()
                    try:
                        childpath.rmdir()
                    except OSError:
                        pass

    def initialize(self, _version, build_data) -> None:
        # NOTE: _version passed to this function is not a version number!
        #       Use tagged_version_str generated from metadata instead
        metadata = ProjectMetadata(
            pathlib.Path(__file__).absolute().parent, PluginManager()
        )
        tagged_version_str = metadata.version.split("+")[0]

        dist_bitstream_dir = (
            pathlib.Path(self.directory) / f"bitstream-v{tagged_version_str}"
        )
        dist_bitstream_dir.mkdir(exist_ok=True, parents=True)

        src_bitstream_dir = pathlib.Path("src") / "bitstream"
        src_bitstream_file = src_bitstream_dir / "sdr_bitstream.bit"
        src_hwh_file = src_bitstream_dir / "sdr_bitstream.hwh"

        stage_bitstream_asset(
            "sdr_bitstream.bit",
            tagged_version_str,
            dist_bitstream_dir,
            src_bitstream_file,
        )
        stage_bitstream_asset(
            "sdr_bitstream.hwh", tagged_version_str, dist_bitstream_dir, src_hwh_file
        )

        build_data["force_include"][str(dist_bitstream_dir)] = (
            force_include_destination(self.target_name)
        )

    def finalize(self, _version, build_data, artifact_path) -> None:
        pass
