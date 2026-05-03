# start_capture_rx.py MQTT Interface Control Document (ICD)

## Overview

`start_capture_rx.py` exposes an MQTT-based command interface for runtime control of the RFSoC RX capture pipeline. The service name is `rfsoc`.

## Connection Parameters

| Parameter | Value |
|---|---|
| Broker | `192.168.20.1` |
| Port | `1883` |
| Client ID | `rfsoc` |
| QoS | `0` |
| Keepalive | `60 s` |

## Topics

| Direction | Topic | Description |
|---|---|---|
| Subscribe | `rfsoc/command` | Incoming JSON commands |
| Publish | `rfsoc/status` | Retained status telemetry |

## Command Message Format

Commands are published to `rfsoc/command` as JSON objects with two fields:

| Field | Type | Description |
|---|---|---|
| `task_name` | string | Command identifier (required) |
| `arguments` | string | Space-delimited arguments (command-dependent) |

## Commands

| task_name | arguments | Description |
|---|---|---|
| `reset` | — | Reset all active channels, stopping capture and setting state to `inactive`. |
| `capture` | — | Immediately start capture on all active channels with sample index reset to zero. |
| `capture_next_pps` | — | Arm capture to start on the next PPS edge. Sample index is set to `floor((epoch_s + 1) * f_s)`. |
| `set` | `freq_metadata <freq_hz>` | Update the frequency metadata register (`FREQUENCY_IDX`) on all active channels to `round(freq_hz / 1e3)` kHz. Does not reconfigure the ADC NCO. |
| `set` | `freq_IF <freq_mhz>` | Retune the ADC NCO on all four tile/block pairs to `-freq_mhz`, update sample rate metadata, and update frequency metadata. Frequency is rounded to kHz precision. |
| `set` | `channel <ch_list>` | Set active channels to a comma-separated list (e.g., `A,B,C,D`). Resets all channels after updating the channel set. |
| `set` | `tx_center_freq <mhz>` | Set the TX DAC RFDC mixer/NCO center frequency on all TX channels. |
| `set` | `tx_offset_freq <mhz>` | Set the TX function-generator baseband offset frequency. Magnitude must be less than 32 MHz. |
| `set` | `tx_amplitude <bins>` | Set the TX waveform peak amplitude in DAC bins (0..8191). |
| `set` | `tx_channel <ch_list>` | Set TX DAC channel(s): `A`, `B`, or `A,B`. Affects subsequent `tx_center_freq`, `tx_offset_freq`, and `tx_amplitude` commands. |
| `get` | `tlm` | Request the current status telemetry to be published to `rfsoc/status`. |

## Status Telemetry

The `rfsoc/status` topic carries a retained JSON payload:

| Field | Type | Description |
|---|---|---|
| `state` | string | `active`, `inactive`, or `offline` (on disconnect/Will). |
| `f_c_hz` | number | Current center frequency in Hz (from metadata). |
| `f_if_hz` | number | Current IF/NCO frequency in Hz. |
| `f_s` | number | Current output sample rate in Hz. |
| `pps_count` | integer | Monotonically increasing PPS counter (max across all channels). |
| `channels` | string[] | List of currently active channel identifiers (e.g., `["A", "B"]`). |
| `tx_channels` | string[] | Currently active TX channel identifiers (e.g., `["A"]`). |
| `tx_center_freq` | number \| null | TX DAC NCO center frequency in MHz, or `null` if not set. |
| `tx_offset_freq` | number | TX function-generator baseband offset frequency in MHz. |
| `tx_amplitude_bins` | integer | TX waveform peak amplitude in DAC bins (0..8191). |

## Will Message

On unexpected disconnect, the MQTT Will publishes to `rfsoc/status`:
```json
{"state": "offline"}
```

## Notes

- The `capture_next_pps` command waits for the fractional second to drop below 0.5 before arming, then sleeps an additional 100 ms. The sample index offset is computed from `epoch_s + 1`.
- The `set freq_IF` command rounds the requested frequency to 3 decimal places (kHz precision) before applying.
- Unknown `set` parameters log a warning and are ignored.
- Commands missing `task_name` log a warning and are ignored.
