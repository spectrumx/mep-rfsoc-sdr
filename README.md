# SpectrumX MEP RFSoC 4x2 SDR
This repository contains a PYNQ overlay which provides SDR functionality for the [RFSoC 4x2 Development Board](https://www.rfsoc-pynq.io) for the SpectrumX Mobile Experiment Platform (MEP) project. SpectrumX is a nexus for innovation in spectrum research, education, and national-level partnerships. More information can be found on the SpectrumX [website](https://www.spectrumx.org/).

The SDR overlay provides flexible software-controlled transmit and receive capability for the RFSoC 4x2 board. Data is transferred to and from the board to a PC over a 10Gbps SFP+ connection, using the QSFP28 connector and a Quad to Single SFP adapter.

## Required Equipment

- RFSoC 4x2 Development Board
- Intel 10GbE x520 SFP NIC (Or compatible alternative)
- QSFP to SFP+ Adapter
- SFP+ Direct Attach Cable (Or equivalent)
- PC with 10GbE capable NIC installed

## RFSoC 4x2 Installation Guide

Clone this repository on the RFSoC 4x2. **Important**: This repository uses Git submodules for external dependencies, so you must initialize them:

```bash
git clone --recursive https://github.com/spectrumx/mep-rfsoc-sdr.git
cd mep-rfsoc-sdr
```

Then install the package:
```bash
pip3 install . -v
```

The bitstream and hardware description files are not included in the repo by default and must be copied from the release page at: https://github.com/spectrumx/mep-rfsoc-sdr/releases

## Receiving Data

The SDR image streams captured RF data over a UDP connection. I/Q data is sent in interleaved packets with a header providing timing and frequency information. This data stream can be received and parsed by utilties in the [mep-examples](https://github.com/spectrumx/mep-examples) repository. 

## Vivado build guide

The build scripts expect Vivado 2024.1 and a license for the XXV_Ethernet core. Source the Vivado environment script, the path will depend on the installation:

```bash
source /opt/Xilinx/Vivado/2024.1/settings64.sh
```

Initialize the Vivado project:

```bash
cd boards/RFSoC4x2/mep-sdr
init_design.bash
```

That will create the Vivado project and instantiate the block design. To build the project open the design in Vivado:

```bash
vivado mep-sdr/mep-sdr.xdc
```

In Vivado go to Tools->Run Tcl Script and select build_design.tcl. This script will synthesize, place, and route the design. 