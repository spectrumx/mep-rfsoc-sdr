import os
import shutil
from distutils.dir_util import copy_tree
from setuptools import setup, find_packages

module_name = "mep_rfsoc_sdr"
board = os.environ.get('BOARD', 'RFSoC4x2')  # Default to RFSoC4x2
repo_board_dir = f'boards/{board}/{module_name.replace("_", "-")}'

# Create long description from README.md
try:
    with open("README.md", encoding='utf-8') as fh:
        readme_lines = fh.readlines()
    long_description = (''.join(readme_lines))
except FileNotFoundError:
    long_description = "MEP RFSoC SDR package for SpectrumX project"

# Create the main package directory at project root
os.makedirs(f'{module_name}/mep_rfsoc_sdr', exist_ok=True)
open(f'{module_name}/mep_rfsoc_sdr/__init__.py', 'w').close()

# Copy bitstream to python package (if available)
data_files = []
src_dir = os.path.join(repo_board_dir, 'bitstream')
dst_dir = os.path.join(module_name, 'bitstream')

# Check if bitstream files exist
bit_files = []
hwh_files = []
if os.path.exists(src_dir):
    bit_files = [f for f in os.listdir(src_dir) if f.endswith('.bit')]
    hwh_files = [f for f in os.listdir(src_dir) if f.endswith('.hwh')]

if bit_files and hwh_files:
    copy_tree(src_dir, dst_dir)
    data_files.extend(
        [os.path.join("..", dst_dir, f) for f in os.listdir(dst_dir)])
    print(f"Bitstream copied from {src_dir} to {dst_dir}")
    print(f"Found {len(bit_files)} .bit files and {len(hwh_files)} .hwh files")
else:
    print("  Warning: Required bitstream files (.bit and .hwh) not found.")
    print("  Please download the latest release from:")
    print("  https://github.com/spectrumx/mep-rfsoc-sdr/releases")
    print(f"  and extract to {src_dir}")
    # Create empty directories to avoid errors
    os.makedirs(src_dir, exist_ok=True)  # Create source directory structure
    os.makedirs(dst_dir, exist_ok=True)  # Create destination directory

# Copy python source files
src_dir = os.path.join('src', 'python')
dst_dir = os.path.join(module_name, 'python')

if os.path.exists(src_dir):
    copy_tree(src_dir, dst_dir)
    data_files.extend(
        [os.path.join("..", dst_dir, f) for f in os.listdir(dst_dir)])
    print("Python source files copied successfully")
else:
    print("Warning: Python source directory not found")
    os.makedirs(dst_dir, exist_ok=True)

# Copy bash scripts
src_dir = os.path.join('src', 'bash')
dst_dir = os.path.join(module_name, 'bash')

if os.path.exists(src_dir):
    copy_tree(src_dir, dst_dir)
    data_files.extend(
        [os.path.join("..", dst_dir, f) for f in os.listdir(dst_dir)])
    print("Bash scripts copied successfully")
else:
    print("Warning: Bash scripts directory not found")
    os.makedirs(dst_dir, exist_ok=True)

# Copy Jupyter notebooks
src_dir = os.path.join('src', 'notebooks')
dst_dir = os.path.join(module_name, 'notebooks')

if os.path.exists(src_dir):
    copy_tree(src_dir, dst_dir)
    data_files.extend(
        [os.path.join("..", dst_dir, f) for f in os.listdir(dst_dir)])
    print("Jupyter notebooks copied successfully")
else:
    print("Warning: Jupyter notebooks directory not found")
    os.makedirs(dst_dir, exist_ok=True)

setup(
    name=module_name,
    version='0.0.1',
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
    python_requires=">=3.6.0",
    install_requires=[
        "pynq>=2.7",
    ]
)
