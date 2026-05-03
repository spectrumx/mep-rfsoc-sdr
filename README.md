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

Then build and install the package:
```bash
sudo `which python` -m pip install --upgrade pip build
sudo `which python` -m build
sudo `which python` -m pip install . -v
```

The bitstream and hardware description files are not included in the repo by default. The build hook fetches the official files from the release page at: https://github.com/spectrumx/mep-rfsoc-sdr/releases into `dist/bitstream` and includes those files in the installed package. To override the official files, manually place `sdr_bitstream.bit` and `sdr_bitstream.hwh` in `src/bitstream`, then rerun the build and install commands above. The build hook will copy those user-provided files into `dist/bitstream` and include them in the installed package.

## Receiving Data

The SDR image streams captured RF data over a UDP connection. I/Q data is sent in interleaved packets with a header providing timing and frequency information. Telemetry and commands are optionally sent over MQTT. This data stream can be received and parsed by utilties in the [mep-examples](https://github.com/spectrumx/mep-examples) repository. 

To launch the UDP streaming script on the RFSoC 4x2, run:

```bash
sudo -E `which python` -m mep_rfsoc_sdr.start_capture_rx
```

The script configures the RFSoC overlay, tunes the ADC NCO, starts UDP streaming, and optionally enables a DAC transmit tone from the function-generator IP. If MQTT control is not available, command line flags can be used to set the default configuration:

Command line options:

| Option | Default | Description |
| --- | --- | --- |
| `-f`, `--freq` | `1090` | ADC IF/NCO frequency in MHz. |
| `-c`, `--channels` | `A` | ADC capture channels to stream. Valid channels are `A`, `B`, `C`, and `D`. |
| `-r`, `--reset` | disabled | Load and configure the overlay, but leave ADC capture held in reset. |
| `-i`, `--internal_clock` | external ref | Use the internal clock configuration instead of an external reference. |
| `--tx-channel` | `A` | DAC output channel for the TX tone: `A`, `B`, `A,B`, or `None`. |
| `--tx-center-freq` | unset | RFDC DAC mixer/NCO center frequency in MHz for selected TX channel(s). |
| `--tx-offset-freq` | unset | Function-generator baseband offset frequency in MHz. If TX is otherwise requested, defaults to `0`. Must be less than `32 MHz` in magnitude. |
| `--tx-amplitude` | `8191` | TX waveform peak amplitude in signed 14-bit DAC bins, `0..8191`. |
| `-l`, `--log-level` | `INFO` | Python logging level. |

## Vivado build guide

The build scripts expect Vivado 2024.1 and a license for the XXV_Ethernet core. Source the Vivado environment script, the path will depend on the installation:

```bash
source /opt/Xilinx/Vivado/2024.1/settings64.sh
```

Initialize and build the Vivado project:

```bash
cd boards/RFSoC4x2/mep-sdr
init_design.bash --build
```
To only initialize the project, run init_design.bash without the build flag. This will create the Vivado project and instantiate the block design. The block design can then be manually opened in Vivado.

```bash
vivado mep-sdr.xdc
```
