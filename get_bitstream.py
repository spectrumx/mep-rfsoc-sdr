import os
import pathlib
import shutil
import urllib.request

from hatchling.builders.hooks.plugin.interface import BuildHookInterface
from hatchling.metadata.core import ProjectMetadata
from hatchling.plugin.manager import PluginManager

MODULE_NAME = "mep_rfsoc_sdr"
DIST_BITSTREAM_DIR = pathlib.Path(__file__).absolute().parent / "dist" / "bitstream"


def download_file(url, destination):
    """Download a file from URL to destination"""
    print(f"Downloading {url} to {destination}")
    urllib.request.urlretrieve(url, destination)
    print(f"Successfully downloaded {os.path.basename(destination)}")


class BitstreamHook(BuildHookInterface):
    def clean(self, versions) -> None:
        for dirpath, _dirnames, filenames in DIST_BITSTREAM_DIR.walk():
            for name in filenames:
                if name.endswith(".bit") or name.endswith(".hwh"):
                    (dirpath / name).unlink()
        try:
            DIST_BITSTREAM_DIR.rmdir()
        except OSError:
            pass

    def initialize(self, version, build_data) -> None:
        metadata = ProjectMetadata(
            pathlib.Path(__file__).absolute().parent, PluginManager()
        )
        tagged_version_str = metadata.version.split("+")[0]
        DIST_BITSTREAM_DIR.mkdir(exist_ok=True, parents=True)

        src_bitstream_dir = (
            pathlib.Path(__file__).absolute().parent / "src" / "bitstream"
        )
        src_bitstream_file = src_bitstream_dir / "sdr_bitstream.bit"
        src_hwh_file = src_bitstream_dir / "sdr_bitstream.hwh"

        if src_bitstream_file.exists():
            shutil.copy2(src_bitstream_file, DIST_BITSTREAM_DIR)
        else:
            bit_url = f"https://github.com/spectrumx/mep-rfsoc-sdr/releases/download/v{tagged_version_str}/sdr_bitstream.bit"
            print(
                "Required bitstream file not found locally. "
                f"Attempting to download {bit_url}"
            )
            download_file(bit_url, DIST_BITSTREAM_DIR / "sdr_bitstream.bit")

        if src_hwh_file.exists():
            shutil.copy2(src_hwh_file, DIST_BITSTREAM_DIR)
        else:
            hwh_url = f"https://github.com/spectrumx/mep-rfsoc-sdr/releases/download/v{tagged_version_str}/sdr_bitstream.hwh"
            print(
                f"Required HWH file not found locally. Attempting to download {hwh_url}"
            )
            download_file(hwh_url, DIST_BITSTREAM_DIR / "sdr_bitstream.hwh")

        build_data["force_include"][str(DIST_BITSTREAM_DIR)] = "src/bitstream"

    def finalize(self, version, build_data, artifact_path) -> None:
        pass
