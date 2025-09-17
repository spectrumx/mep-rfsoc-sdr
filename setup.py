import os
import shutil
from distutils.dir_util import copy_tree
from pynqutils.setup_utils import build_py, find_version, extend_package, get_platform
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

if __name__ == "__main__":
    # Create the main package directory at project root
    os.makedirs(f'{module_name}/mep_rfsoc_sdr', exist_ok=True)
    open(f'{module_name}/mep_rfsoc_sdr/__init__.py', 'w').close()

    # Copy bitstream to python package (if available)
    data_files = []
    src_dir = os.path.join(repo_board_dir, 'bitstream')
    dst_dir = os.path.join(module_name, 'bitstream')
    
    if os.path.exists(src_dir):
        copy_tree(src_dir, dst_dir)
        data_files.extend(
            [os.path.join("..", dst_dir, f) for f in os.listdir(dst_dir)])
        print(f"Bitstream copied from {src_dir}")
    else:
        print("Warning: Bitstream directory not found.")
        print("Please download the latest release from:")
        print("https://github.com/spectrumx/mep-rfsoc-sdr/releases")
        print(f"and extract to {src_dir}")
        # Create empty directory to avoid errors
        os.makedirs(dst_dir, exist_ok=True)

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
        version=find_version('{}/__init__.py'.format(module_name)),
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
            "pynqutils",
            "pynq>=2.7",
            "numpy",
            "matplotlib",
            "ipython"
        ],
        cmdclass={"build_py": build_py}
    )
