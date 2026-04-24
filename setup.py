import os
import shutil
import urllib.request
from distutils.dir_util import copy_tree
from setuptools import setup, find_packages

module_name = "mep_rfsoc_sdr"
version = "0.0.2"
board = os.environ.get('BOARD', 'RFSoC4x2')  # Default to RFSoC4x2
repo_board_dir = f'boards/{board}/{module_name.replace("_", "-")}'

# Create long description from README.md
try:
    with open("README.md", encoding='utf-8') as fh:
        readme_lines = fh.readlines()
    long_description = (''.join(readme_lines))
except FileNotFoundError:
    long_description = "MEP RFSoC SDR package for SpectrumX project"

# Create __init__.py in project root to make it a package
open('__init__.py', 'w').close()

def download_file(url, destination):
    """Download a file from URL to destination"""
    try:
        print(f"Downloading {url} to {destination}")
        urllib.request.urlretrieve(url, destination)
        print(f"Successfully downloaded {os.path.basename(destination)}")
        return True
    except Exception as e:
        print(f"Failed to download {url}: {e}")
        return False

# Prepare data files list - files will be installed directly from their source locations
data_files = []

# Create src/bitstream directory and copy bitstream files there
src_bitstream_dir = os.path.join('src', 'bitstream')
os.makedirs(src_bitstream_dir, exist_ok=True)

# Check if bitstream files exist and copy them to src/bitstream
bitstream_dir = os.path.join(repo_board_dir, 'bitstream')
os.makedirs(bitstream_dir, exist_ok=True)  # Ensure directory exists

bit_files = [f for f in os.listdir(bitstream_dir) if f.endswith('.bit')] if os.path.exists(bitstream_dir) else []
hwh_files = [f for f in os.listdir(bitstream_dir) if f.endswith('.hwh')] if os.path.exists(bitstream_dir) else []

# Download missing files if needed
if not bit_files or not hwh_files:
    print("Required bitstream files not found locally. Attempting to download...")
    
    # Download URLs
    bit_url = f"https://github.com/spectrumx/mep-rfsoc-sdr/releases/download/v{version}/sdr_bitstream.bit"
    hwh_url = f"https://github.com/spectrumx/mep-rfsoc-sdr/releases/download/v{version}/sdr_bitstream.hwh"
    
    bit_dest = os.path.join(bitstream_dir, "sdr_bitstream.bit")
    hwh_dest = os.path.join(bitstream_dir, "sdr_bitstream.hwh")
    
    # Download missing files
    if not bit_files:
        if not download_file(bit_url, bit_dest):
            print("Failed to download bitstream file")
    if not hwh_files:
        if not download_file(hwh_url, hwh_dest):
            print("Failed to download HWH file")
    
    # Refresh file lists after download
    bit_files = [f for f in os.listdir(bitstream_dir) if f.endswith('.bit')]
    hwh_files = [f for f in os.listdir(bitstream_dir) if f.endswith('.hwh')]

# Copy bitstream files to src/bitstream directory
if bit_files and hwh_files:
    for file in os.listdir(bitstream_dir):
        src_file = os.path.join(bitstream_dir, file)
        dst_file = os.path.join(src_bitstream_dir, file)
        shutil.copy2(src_file, dst_file)
    print(f"Copied {len(bit_files)} .bit files and {len(hwh_files)} .hwh files to {src_bitstream_dir}")
else:
    print("  Error: Required bitstream files (.bit and .hwh) could not be found or downloaded.")
    print("  Please manually download from:")
    print("  https://github.com/spectrumx/mep-rfsoc-sdr/releases")
    print(f"  and place in {bitstream_dir}")

# Add python source files to data_files
python_dir = os.path.join('src', 'python')
if os.path.exists(python_dir):
    for root, dirs, files in os.walk(python_dir):
        for file in files:
            data_files.append(os.path.join(root, file))
    print("Python source files added to package")
else:
    print("Warning: Python source directory not found")

# Add bash scripts to data_files
bash_dir = os.path.join('src', 'bash')
if os.path.exists(bash_dir):
    for root, dirs, files in os.walk(bash_dir):
        for file in files:
            data_files.append(os.path.join(root, file))
    print("Bash scripts added to package")
else:
    print("Warning: Bash scripts directory not found")

# Add Jupyter notebooks to data_files
notebooks_dir = os.path.join('src', 'notebooks')
if os.path.exists(notebooks_dir):
    for root, dirs, files in os.walk(notebooks_dir):
        for file in files:
            data_files.append(os.path.join(root, file))
    print("Jupyter notebooks added to package")
else:
    print("Warning: Jupyter notebooks directory not found")

# Add bitstream files to data_files
if os.path.exists(src_bitstream_dir):
    for root, dirs, files in os.walk(src_bitstream_dir):
        for file in files:
            data_files.append(os.path.join(root, file))
    print("Bitstream files added to package")

setup(
    name=module_name,
    version=version,
    description="MEP RFSoC SDR package for SpectrumX project",
    long_description=long_description,
    long_description_content_type='text/markdown',
    author='SpectrumX Development Team',
    author_email="spectrumx@spectrumx.org",
    url='https://github.com/spectrumx/mep-rfsoc-sdr.git',
    license='BSD 3-Clause License',
    packages=find_packages(),
    package_data={
        "": data_files,
    },
    include_package_data=True,
    python_requires=">=3.6.0",
    install_requires=[
        "pynq>=2.7",
    ]
)
