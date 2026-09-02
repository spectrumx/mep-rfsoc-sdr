#!/usr/bin/env python3

import argparse
import fcntl
import importlib.resources
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from threading import RLock

import paho.mqtt.client as mqtt

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from sdr_overlay import SDROverlay
else:
    from .sdr_overlay import SDROverlay


# ---------------------------------------------------------------------------
# Service configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BITFILE_NAME = "sdr_bitstream.bit"

SERVICE_NAME = "rfsoc"
MQTT_BROKER = "192.168.20.1"
MQTT_PORT = 1883
MQTT_CMD_TOPIC = f"{SERVICE_NAME}/command"
MQTT_STATUS_TOPIC = f"{SERVICE_NAME}/status"
LOG_DIR = os.path.join(os.sep, "var", "log", "spectrumx")
LOCK_FILE = os.path.join(os.sep, "var", "lock", f"{SERVICE_NAME}.lock")

ADC_SAMPLE_FREQUENCY_MHZ = 1024
DAC_SAMPLE_FREQUENCY_MHZ = 1024
ADC_DECIMATION = 16
ADC_IF_MHZ = 1090

# SDROverlay() can return before the fabric/MMIO interface is safe to touch.
# A premature register access can fault below Python, so this must remain a
# fixed delay rather than a Python-level readiness probe.
OVERLAY_SETTLE_TIME_S = 5.0

ALL_CHANNELS = ("A", "B", "C", "D")

TX_CHANNEL_CHOICES = ("A", "B", "A,B", "None")
TX_WAVEFORM_SINE_COS = 1
TX_BASEBAND_NYQUIST_MHZ = 32.0
TX_MAX_AMPLITUDE_BINS = 8191
TX_DEFAULT_PHASE = 0
TX_DEFAULT_OFFSET = 0
TX_DEFAULT_OFFSET_FREQ_MHZ = 0.0
TX_FREQUENCY_REG_BITS = 32
TX_CHANNEL_CONFIG = {
    "A": {
        "dac_tile": 2,
        "dac_block": 0,
        "function_generators": ("function_gen_to_dac_A",),
    },
    "B": {
        "dac_tile": 0,
        "dac_block": 0,
        "function_generators": ("function_gen_to_dac_B",),
    },
}


# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

exit_flag = False


class Ctrl(Enum):
    CAPTURE = 0
    RESET = 1
    CAPTURE_NEXT_PPS = 3


class CommandError(ValueError):
    """An MQTT command was malformed or unsupported."""


@dataclass
class CaptureData:
    state: str = "starting"
    state_RX: str = "inactive"
    state_TX: str = "inactive"
    f_c_hz: float = 0.0
    f_if_hz: float = 0.0
    f_s: float = 0.0
    pps_count: int = 0
    pps_publish_interval_s: float = 0.0
    channels: tuple = field(default_factory=tuple)

    mqtt_client: object = None
    ol: object = None
    accept_commands: bool = False
    hardware_lock: RLock = field(default_factory=RLock, repr=False)

    # TX is safe-off until tx_start is requested explicitly. Configuration may
    # be staged while TX is stopped, but function generators stay disabled.
    tx_enabled: bool = False
    tx_channels: tuple = field(default_factory=tuple)
    tx_center_freq: object = None
    tx_offset_freq: float = TX_DEFAULT_OFFSET_FREQ_MHZ
    tx_offset_freq_by_channel: dict = field(
        default_factory=lambda: {
            channel: TX_DEFAULT_OFFSET_FREQ_MHZ for channel in TX_CHANNEL_CONFIG
        }
    )
    tx_amplitude_bins: int = 0
    tx_amplitude_configured: bool = False


data = CaptureData()


# ---------------------------------------------------------------------------
# Status and process control
# ---------------------------------------------------------------------------


def status_number(value):
    # These fields were historically numeric. Keep them numeric even before
    # hardware init so older status consumers can safely call float(...).
    return 0.0 if value is None else value


def update_state(data):
    if data.state in ("starting", "error", "offline"):
        return
    data.state = "active" if (
        data.state_RX == "active" or data.state_TX == "active"
    ) else "ready"


def status_payload(data):
    return {
        "state": data.state,
        "state_RX": data.state_RX,
        "state_TX": data.state_TX,
        "f_c_hz": status_number(data.f_c_hz),
        "f_if_hz": status_number(data.f_if_hz),
        "f_s": status_number(data.f_s),
        "pps_count": data.pps_count,
        "channels": data.channels,
        "tx_enabled": data.tx_enabled,
        "tx_channels": data.tx_channels,
        "tx_center_freq": data.tx_center_freq,
        "tx_offset_freq": data.tx_offset_freq,
        "tx_offset_freq_by_channel": data.tx_offset_freq_by_channel,
        "tx_amplitude_bins": data.tx_amplitude_bins,
        "tx_amplitude_configured": data.tx_amplitude_configured,
    }


def send_status(data):
    if data.mqtt_client is None:
        return None

    payload = json.dumps(status_payload(data), allow_nan=False)
    return data.mqtt_client.publish(MQTT_STATUS_TOPIC, payload, retain=True)


def publish_status(data, reason=""):
    try:
        return send_status(data)
    except Exception:
        if reason:
            logging.exception("Failed to publish status after %s", reason)
        else:
            logging.exception("Failed to publish status")
        return None


def signal_handler(sig, frame):
    global exit_flag
    logging.info("Exiting RF capture")
    exit_flag = True


# ---------------------------------------------------------------------------
# Bitfile and numeric helpers
# ---------------------------------------------------------------------------


def get_bitfile_path():
    try:
        bitfile_path = (
            importlib.resources.files("mep_rfsoc_sdr") / "bitstream" / BITFILE_NAME
        )
        if bitfile_path.exists():
            return str(bitfile_path)
    except Exception:
        logging.exception("Could not find bitfile in installed package")

    local_bitfile_path = os.path.join(SCRIPT_DIR, "..", "bitstream", BITFILE_NAME)
    if os.path.exists(local_bitfile_path):
        logging.info("Using local bitfile: %s", local_bitfile_path)
        return local_bitfile_path

    raise FileNotFoundError(
        f"Could not find bitfile {BITFILE_NAME} in package or local directory"
    )


def adc_sample_rate_hz():
    return int(ADC_SAMPLE_FREQUENCY_MHZ * 1_000_000 / ADC_DECIMATION)


def tx_amplitude_bins_to_q15(amplitude_bins):
    return int(round(amplitude_bins * 0x7FFF / TX_MAX_AMPLITUDE_BINS))


def encode_signed_frequency_hz(frequency_hz):
    min_hz = -(1 << (TX_FREQUENCY_REG_BITS - 1))
    max_hz = (1 << (TX_FREQUENCY_REG_BITS - 1)) - 1

    if not min_hz <= frequency_hz <= max_hz:
        raise ValueError(
            f"TX offset frequency must fit signed {TX_FREQUENCY_REG_BITS}-bit Hz "
            f"register ({min_hz}..{max_hz} Hz)"
        )

    return frequency_hz & ((1 << TX_FREQUENCY_REG_BITS) - 1)


def parse_capture_channels(value):
    if isinstance(value, str):
        channels = tuple(ch for ch in value.split(",") if ch)
    else:
        channels = tuple(value)

    if not channels:
        raise CommandError("at least one RX channel is required")

    invalid = sorted(set(channels) - set(ALL_CHANNELS))
    if invalid:
        raise CommandError(f"invalid RX channel(s): {', '.join(invalid)}")

    return channels


def parse_tx_channels(value):
    if value is None or value == "None":
        return ()

    channels = tuple(ch for ch in value.split(",") if ch)
    invalid = sorted(set(channels) - set(TX_CHANNEL_CONFIG))
    if invalid:
        raise CommandError(f"invalid TX channel(s): {', '.join(invalid)}")

    return channels


def parse_tx_offset_mhz(value):
    offset = TX_DEFAULT_OFFSET_FREQ_MHZ if value is None else float(value)
    if abs(offset) >= TX_BASEBAND_NYQUIST_MHZ:
        raise ValueError(
            f"TX offset magnitude must be less than "
            f"{TX_BASEBAND_NYQUIST_MHZ:.1f} MHz"
        )
    return offset


def parse_tx_amplitude_bins(value):
    amplitude = int(value)
    if not 0 <= amplitude <= TX_MAX_AMPLITUDE_BINS:
        raise ValueError(f"TX amplitude must be in DAC bins 0..{TX_MAX_AMPLITUDE_BINS}")
    return amplitude


# ---------------------------------------------------------------------------
# TX hardware control
# ---------------------------------------------------------------------------


def set_tx_dac_nco(overlay, f_c_mhz, f_s_mhz, tile, block):
    overlay.set_dac_nco(f_c_mhz, f_s_mhz, tile, block)
    logging.info(
        "TX DAC NCO set: tile=%d block=%d f_c=%.6f MHz f_s=%.6f MHz",
        tile,
        block,
        f_c_mhz,
        f_s_mhz,
    )


def get_tx_function_generator(channel, data, required):
    generator_names = TX_CHANNEL_CONFIG[channel]["function_generators"]

    for gen_name in generator_names:
        gen = getattr(data.ol, gen_name, None)
        if gen is not None:
            return gen_name, gen

    if not required:
        logging.info(
            "TX function generator IP for channel %s not present; nothing to disable",
            channel,
        )
        return None, None

    raise RuntimeError(
        f"Overlay does not expose a TX function generator for channel {channel} "
        f"({', '.join(generator_names)})"
    )


def set_tx_function_generator_amplitude(channel, tx_amplitude_q15, data):
    gen_name, gen = get_tx_function_generator(channel, data, required=False)
    if gen is None:
        return

    gen.register_map.AMPLITUDE = tx_amplitude_q15
    logging.info(
        "TX channel %s function generator %s amplitude set to Q15 0x%04X",
        channel,
        gen_name,
        tx_amplitude_q15,
    )


def configure_tx_function_generator(channel, tx_offset_mhz, tx_amplitude_q15, data):
    gen_name, gen = get_tx_function_generator(
        channel,
        data,
        required=tx_offset_mhz is not None,
    )
    if gen is None:
        return

    regs = gen.register_map

    if tx_offset_mhz is None:
        regs.AMPLITUDE = 0
        regs.WAVEFORM_TYPE = 0
        regs.FREQUENCY = 0
        regs.PHASE = TX_DEFAULT_PHASE
        regs.OFFSET = TX_DEFAULT_OFFSET
        regs.ENABLE = 0
        logging.info("TX channel %s function generator %s disabled", channel, gen_name)
        return

    # Program while disabled so an intermediate register value is not emitted.
    regs.ENABLE = 0

    tx_offset_mhz = float(tx_offset_mhz)
    tx_offset_hz = int(round(tx_offset_mhz * 1e6))
    tx_offset_reg = encode_signed_frequency_hz(tx_offset_hz)

    regs.WAVEFORM_TYPE = TX_WAVEFORM_SINE_COS
    regs.FREQUENCY = tx_offset_reg
    regs.AMPLITUDE = tx_amplitude_q15
    regs.PHASE = TX_DEFAULT_PHASE
    regs.OFFSET = TX_DEFAULT_OFFSET
    regs.ENABLE = 1

    logging.info(
        "TX channel %s function generator %s enabled at signed offset %.6f MHz "
        "(programmed %d Hz as 0x%08X, amplitude Q15 0x%04X)",
        channel,
        gen_name,
        tx_offset_mhz,
        tx_offset_hz,
        tx_offset_reg,
        tx_amplitude_q15,
    )


def disable_all_tx(data):
    for channel in TX_CHANNEL_CONFIG:
        configure_tx_function_generator(channel, None, None, data)
    data.tx_enabled = False
    data.state_TX = "inactive"
    update_state(data)


def apply_tx_center_freq(channel, data):
    if data.tx_center_freq is None:
        return

    cfg = TX_CHANNEL_CONFIG[channel]
    set_tx_dac_nco(
        data.ol,
        data.tx_center_freq,
        DAC_SAMPLE_FREQUENCY_MHZ,
        cfg["dac_tile"],
        cfg["dac_block"],
    )


def require_tx_ready_to_start(data):
    if not data.tx_channels:
        raise CommandError("tx_start requires at least one TX channel")

    if not data.tx_amplitude_configured:
        raise CommandError(
            f"tx_start requires tx_amplitude in DAC bins 0..{TX_MAX_AMPLITUDE_BINS}"
        )


def start_tx(data):
    require_tx_ready_to_start(data)
    tx_amp_q15 = tx_amplitude_bins_to_q15(data.tx_amplitude_bins)

    try:
        for channel in TX_CHANNEL_CONFIG:
            if channel not in data.tx_channels:
                configure_tx_function_generator(channel, None, None, data)

        for channel in data.tx_channels:
            apply_tx_center_freq(channel, data)
            configure_tx_function_generator(
                channel,
                data.tx_offset_freq_by_channel[channel],
                tx_amp_q15,
                data,
            )

    except Exception:
        data.tx_enabled = False
        data.state_TX = "inactive"
        try:
            disable_all_tx(data)
        except Exception:
            logging.exception("Failed to disable TX after tx_start failure")
        raise

    data.tx_enabled = True
    data.state_TX = "active"
    update_state(data)
    logging.info("TX started on channels: %s", data.tx_channels)


def stop_tx(data):
    disable_all_tx(data)
    logging.info("TX stopped")


def configure_initial_tx(args, data):
    disable_all_tx(data)

    tx_requested = any(
        value is not None
        for value in (
            args.tx_channel,
            args.tx_center_freq,
            args.tx_offset_freq,
            args.tx_amplitude,
        )
    ) or args.tx_start

    if not tx_requested:
        return

    if args.tx_amplitude is None:
        raise ValueError(
            "--tx-amplitude is required when TX configuration is provided. "
            f"Use DAC bins 0..{TX_MAX_AMPLITUDE_BINS}."
        )

    data.tx_channels = parse_tx_channels(args.tx_channel)
    data.tx_center_freq = args.tx_center_freq
    data.tx_offset_freq = parse_tx_offset_mhz(args.tx_offset_freq)
    data.tx_amplitude_bins = parse_tx_amplitude_bins(args.tx_amplitude)
    data.tx_amplitude_configured = True

    for channel in data.tx_channels:
        data.tx_offset_freq_by_channel[channel] = data.tx_offset_freq

    logging.info(
        "TX configured but stopped: channels=%s center=%s MHz offset=%.6f MHz "
        "amplitude=%d DAC bins",
        data.tx_channels,
        data.tx_center_freq,
        data.tx_offset_freq,
        data.tx_amplitude_bins,
    )


# ---------------------------------------------------------------------------
# RX metadata and capture control
# ---------------------------------------------------------------------------


def stream_for(channel, data):
    return getattr(data.ol, f"adc_to_udp_stream_{channel}")


def write_sample_rate_metadata(sample_rate_hz, data, channels=ALL_CHANNELS):
    sample_rate_hz = int(round(sample_rate_hz))
    sample_rate_raw = sample_rate_hz * ADC_DECIMATION

    logging.info("Setting sample rate metadata to: %d", sample_rate_raw)
    for channel in channels:
        stream_for(channel, data).register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate_raw

    data.f_s = sample_rate_hz


def write_frequency_metadata(f_c_hz, data, channels=ALL_CHANNELS):
    f_c_hz = float(f_c_hz)
    f_c_khz = int(round(f_c_hz / 1e3))

    logging.info("Setting frequency metadata to: %d kHz", f_c_khz)
    for channel in channels:
        stream_for(channel, data).register_map.FREQUENCY_IDX = f_c_khz

    data.f_c_hz = f_c_hz


def update_adc_nco(freq_mhz, data):
    freq_mhz = round(float(freq_mhz), 3)
    if freq_mhz < 0:
        raise ValueError("RX center frequency must be non-negative")
    freq_hz = freq_mhz * 1e6

    # Pass the physical RF center frequency. SDROverlay selects the RFDC NCO
    # sign from Nyquist-zone parity so the complex I/Q spectrum keeps the same
    # frequency orientation on both sides of a Nyquist-zone boundary.
    for tile, block in ((0, 0), (0, 1), (2, 0), (2, 1)):
        data.ol.set_adc_nco(freq_mhz, ADC_SAMPLE_FREQUENCY_MHZ, tile, block)

    # Stream metadata is written to every RX stream so later channel changes do
    # not expose stale frequency or sample-rate metadata.
    write_sample_rate_metadata(adc_sample_rate_hz(), data)
    write_frequency_metadata(freq_hz, data)

    # Set this last so status never claims a retune that failed partway through.
    data.f_if_hz = freq_hz
    logging.info("ADC mixer and metadata updated to %.3f MHz", freq_mhz)


def set_channel_ctrl(ctrl, data):
    for channel in data.channels:
        stream_for(channel, data).register_map.CTRL = ctrl.value

    data.state_RX = "active" if ctrl in (Ctrl.CAPTURE, Ctrl.CAPTURE_NEXT_PPS) else "inactive"
    update_state(data)


def hold_capture_in_reset(data):
    try:
        set_channel_ctrl(Ctrl.RESET, data)
    except Exception:
        logging.exception("Failed to reset capture after retune failure")

    # set_channel_ctrl() writes state_RX=inactive, so the service error state
    # must be set last.
    data.state = "error"


def capture_now(data):
    set_channel_ctrl(Ctrl.RESET, data)

    for channel in data.channels:
        stream = stream_for(channel, data)
        stream.register_map.SAMPLE_IDX_OFFSET_LSB = 0
        stream.register_map.SAMPLE_IDX_OFFSET_MSB = 0

    set_channel_ctrl(Ctrl.CAPTURE, data)


def capture_next_pps(data):
    set_channel_ctrl(Ctrl.RESET, data)
    data.pps_count = 0

    current_time = time.time()
    while (current_time - int(current_time)) > 0.5:
        time.sleep(0.1)
        current_time = time.time()

    time.sleep(0.1)
    current_time_s = int(current_time) + 1
    samples_since_epoch = current_time_s * int(round(data.f_s))
    lsb = samples_since_epoch & 0xFFFFFFFF
    msb = samples_since_epoch >> 32

    for channel in data.channels:
        stream = stream_for(channel, data)
        stream.register_map.SAMPLE_IDX_OFFSET_LSB = lsb
        stream.register_map.SAMPLE_IDX_OFFSET_MSB = msb

    set_channel_ctrl(Ctrl.CAPTURE_NEXT_PPS, data)


# ---------------------------------------------------------------------------
# Hardware readiness checks
# ---------------------------------------------------------------------------


def _resolve_pll_locked_value():
    try:
        import xrfdc

        for name in ("XRFDC_PLL_LOCKED", "PLL_LOCKED"):
            val = getattr(xrfdc, name, None)
            if val is not None:
                return val, f"xrfdc.{name}"
    except Exception:
        pass

    return 0x2, "hardcoded 0x2 (xrfdc constant not found)"


PLL_LOCKED, PLL_LOCKED_SOURCE = _resolve_pll_locked_value()


def verify_pll_locks(data, tiles=(0, 2), converter_type="adc", timeout_s=5.0):
    deadline = time.monotonic() + timeout_s
    logging.info(
        "Verifying %s PLL lock for tiles %s (locked value = %s, from %s)",
        converter_type.upper(),
        tuple(tiles),
        PLL_LOCKED,
        PLL_LOCKED_SOURCE,
    )

    while True:
        unlocked = []
        for tile in tiles:
            cfg = data.ol.get_pll_config(converter_type, tile)
            if cfg.get("pll_lock_status") != PLL_LOCKED:
                unlocked.append((tile, cfg))

        if not unlocked:
            for tile in tiles:
                logging.info("%s tile %d PLL locked", converter_type.upper(), tile)
            return

        if time.monotonic() >= deadline:
            tile, cfg = unlocked[0]
            raise RuntimeError(
                f"{converter_type.upper()} PLL lock check failed after {timeout_s}s "
                f"for tiles {tuple(t for t, _ in unlocked)}; "
                f"tile {tile} lock_status={cfg.get('pll_lock_status')!r} "
                f"(expected {PLL_LOCKED}), "
                f"ref_clk={cfg.get('ref_clk_freq_mhz')} MHz "
                f"sample_rate={cfg.get('sample_rate_mhz')} MHz"
            )

        time.sleep(0.25)


def smoke_test_stream_registers(data, channels=ALL_CHANNELS):
    for channel in channels:
        value = int(stream_for(channel, data).register_map.PPS_COUNTER)
        logging.info("Smoke test: stream %s PPS_COUNTER readable (=%d)", channel, value)


# ---------------------------------------------------------------------------
# MQTT command handling
# ---------------------------------------------------------------------------


def read_mqtt_message(msg):
    try:
        message = json.loads(msg.payload.decode())
    except UnicodeDecodeError as e:
        raise CommandError("MQTT payload is not valid UTF-8") from e
    except json.JSONDecodeError as e:
        raise CommandError(f"MQTT payload is not valid JSON: {e}") from e

    if not isinstance(message, dict):
        raise CommandError("MQTT payload must be a JSON object")

    command = message.get("task_name")
    if not command:
        raise CommandError("MQTT command missing task_name")

    return command, message.get("arguments", "")


def reject_before_init(msg, data):
    logging.warning(
        "Rejected MQTT command before hardware initialization complete: topic=%s payload=%r",
        msg.topic,
        msg.payload,
    )
    publish_status(data, "early command rejection")


def on_connect(client, userdata, flags, rc):
    if rc != 0:
        logging.error("Failed to connect to MQTT broker, return code %s", rc)
        return

    logging.info("Connected to MQTT broker")
    client.subscribe(MQTT_CMD_TOPIC)

    if data.accept_commands:
        publish_status(data, "MQTT reconnect")


def on_message(client, userdata, msg):
    if not data.accept_commands:
        reject_before_init(msg, data)
        return

    try:
        command, args = read_mqtt_message(msg)
        logging.debug("Received MQTT command=%s args=%r", command, args)

        with data.hardware_lock:
            handle_command(command, args, data)

    except CommandError as e:
        logging.warning("Invalid MQTT command: %s", e)

    except Exception:
        logging.exception("Error processing MQTT message")
        publish_status(data, "unexpected command failure")


def publish_current_status(data, reason):
    refresh_pps_count(data)
    publish_status(data, reason)


def get_request_name(args):
    if isinstance(args, str):
        return args

    # Backward compatibility: the old GUI sends ["tlm"].
    if isinstance(args, list) and len(args) == 1 and isinstance(args[0], str):
        return args[0]

    return None


def handle_command(command, args, data):
    if command == "reset":
        set_channel_ctrl(Ctrl.RESET, data)
        publish_status(data, "reset")

    elif command == "capture":
        capture_now(data)
        publish_status(data, "capture")

    elif command == "capture_next_pps":
        capture_next_pps(data)
        publish_status(data, "capture_next_pps")

    elif command == "set":
        handle_set(args, data)

    elif command == "get":
        handle_get(args, data)

    elif command == "status":
        publish_current_status(data, "status")

    elif command == "set_pps_publish_interval":
        set_pps_publish_interval(args, data)

    elif command == "tx_start":
        start_tx(data)
        publish_status(data, "tx_start")

    elif command == "tx_stop":
        stop_tx(data)
        publish_status(data, "tx_stop")

    else:
        logging.warning("Unknown command: %s", command)


def handle_set(args, data):
    if not isinstance(args, str):
        raise CommandError("set arguments must be a string")

    try:
        name, value = args.split(" ", 1)
    except ValueError as e:
        raise CommandError("set requires: <parameter> <value>") from e

    if name == "freq_metadata":
        write_frequency_metadata(value, data)
        publish_status(data, "set freq_metadata")

    elif name == "freq_IF":
        set_adc_if(value, data)

    elif name == "channel":
        set_rx_channels(value, data)

    elif name == "tx_center_freq":
        set_tx_center_freq(value, data)

    elif name == "tx_offset_freq":
        set_tx_offset_freq(value, data)

    elif name == "tx_amplitude":
        set_tx_amplitude(value, data)

    elif name == "tx_channel":
        set_tx_channel(value, data)

    else:
        logging.warning("Unknown set parameter: %s value %r", name, value)


def set_adc_if(value, data):
    try:
        update_adc_nco(value, data)
    except Exception:
        logging.exception("Runtime retune to %s failed", value)
        hold_capture_in_reset(data)
        publish_status(data, "failed freq_IF retune")
        return

    if data.state == "error":
        data.state = "ready"
    update_state(data)

    publish_status(data, "set freq_IF")


def set_rx_channels(value, data):
    data.channels = parse_capture_channels(value)
    logging.info("Set active RX channels to: %s", data.channels)

    set_channel_ctrl(Ctrl.RESET, data)
    publish_status(data, "set channel")


def set_tx_center_freq(value, data):
    data.tx_center_freq = float(value)

    if data.tx_enabled:
        for channel in data.tx_channels:
            apply_tx_center_freq(channel, data)

    logging.info("TX center frequency set to %.6f MHz", data.tx_center_freq)
    publish_status(data, "set tx_center_freq")


def set_tx_offset_freq(value, data):
    tx_offset = parse_tx_offset_mhz(value)
    data.tx_offset_freq = tx_offset

    # Preserve the existing per-channel status model while making newly selected
    # channels inherit the current global offset before TX is started.
    for channel in data.tx_channels:
        data.tx_offset_freq_by_channel[channel] = tx_offset

    if data.tx_enabled:
        tx_amp_q15 = tx_amplitude_bins_to_q15(data.tx_amplitude_bins)
        for channel in data.tx_channels:
            configure_tx_function_generator(
                channel,
                data.tx_offset_freq_by_channel[channel],
                tx_amp_q15,
                data,
            )

    logging.info("TX offset frequency set to %.6f MHz", tx_offset)
    publish_status(data, "set tx_offset_freq")


def set_tx_amplitude(value, data):
    data.tx_amplitude_bins = parse_tx_amplitude_bins(value)
    data.tx_amplitude_configured = True

    if data.tx_enabled:
        tx_amp_q15 = tx_amplitude_bins_to_q15(data.tx_amplitude_bins)
        for channel in data.tx_channels:
            configure_tx_function_generator(
                channel,
                data.tx_offset_freq_by_channel[channel],
                tx_amp_q15,
                data,
            )

    logging.info("TX amplitude set to %d DAC bins", data.tx_amplitude_bins)
    publish_status(data, "set tx_amplitude")


def set_tx_channel(value, data):
    if value not in TX_CHANNEL_CHOICES:
        raise CommandError(f"tx_channel must be one of {TX_CHANNEL_CHOICES}, got {value}")

    new_channels = parse_tx_channels(value)

    if not new_channels:
        stop_tx(data)
        data.tx_channels = ()
        data.tx_amplitude_bins = 0
        data.tx_amplitude_configured = False
        publish_status(data, "set tx_channel None")
        return

    for channel in new_channels:
        data.tx_offset_freq_by_channel[channel] = data.tx_offset_freq

    data.tx_channels = new_channels

    if data.tx_enabled:
        start_tx(data)

    logging.info("TX channels set to: %s", data.tx_channels)
    publish_status(data, "set tx_channel")


def handle_get(args, data):
    request = get_request_name(args)

    if request in ("tlm", "status"):
        publish_current_status(data, f"get {request}")

    elif isinstance(request, str) and request.startswith("pll_config"):
        publish_pll_config(request, data)

    else:
        logging.warning("Unknown get command: %r", args)


def publish_pll_config(args, data):
    parts = args.split()
    if len(parts) != 3:
        logging.warning("get pll_config requires: pll_config <adc|dac> <tile>")
        return

    _, converter_type, tile_text = parts

    try:
        tile = int(tile_text)
    except ValueError:
        logging.warning("pll_config tile must be an integer, got %r", tile_text)
        return

    try:
        result = data.ol.get_pll_config(converter_type, tile)
    except Exception:
        logging.exception("get pll_config failed")
        return

    data.mqtt_client.publish(
        f"{SERVICE_NAME}/pll_config",
        json.dumps(result, allow_nan=False),
        retain=False,
    )


def set_pps_publish_interval(args, data):
    try:
        data.pps_publish_interval_s = float(args)
    except (TypeError, ValueError):
        logging.warning("Invalid pps_publish_interval value: %r", args)
        return

    logging.info("PPS publish interval set to %ss", data.pps_publish_interval_s)
    publish_status(data, "set_pps_publish_interval")


# ---------------------------------------------------------------------------
# Startup, main loop, and shutdown
# ---------------------------------------------------------------------------


def setup_logging(args):
    os.makedirs(LOG_DIR, exist_ok=True)
    log_filename = f"rfsoc_capture_{time.strftime('%Y%m%d_%H%M%S')}.log"

    logging.basicConfig(
        level=args.log_level,
        format="%(asctime)s - %(levelname)s - %(message)s",
        filename=os.path.join(LOG_DIR, log_filename),
    )

    console = logging.StreamHandler()
    console.setLevel(args.log_level)
    logging.getLogger().addHandler(console)


def setup_mqtt_client():
    mqtt_client = mqtt.Client(client_id=SERVICE_NAME)
    mqtt_client.on_message = on_message
    mqtt_client.on_connect = on_connect
    mqtt_client.will_set(
        MQTT_STATUS_TOPIC,
        payload=json.dumps({"state": "offline"}),
        qos=0,
        retain=True,
    )
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
    mqtt_client.loop_start()
    return mqtt_client


def publish_starting(mqtt_client):
    mqtt_client.publish(
        MQTT_STATUS_TOPIC,
        payload=json.dumps(status_payload(data), allow_nan=False),
        qos=0,
        retain=True,
    )


def publish_startup_error(mqtt_client, error):
    data.state = "error"
    info = mqtt_client.publish(
        MQTT_STATUS_TOPIC,
        payload=json.dumps(
            {
                **status_payload(data),
                "phase": "startup",
                "message": str(error),
                "timestamp": time.time(),
            },
            allow_nan=False,
        ),
        qos=0,
        retain=True,
    )

    try:
        info.wait_for_publish(timeout=1.0)
    except Exception:
        logging.warning(
            "Could not publish retained error status; startup failure is recorded "
            "in the journal only."
        )


def initialize_hardware(args, data):
    logging.info("Initializing RFSoC 10G Overlay")
    bitfile_path = get_bitfile_path()
    logging.info("Opening overlay with bitfile: %s", bitfile_path)

    data.ol = SDROverlay(bitfile_name=bitfile_path, ignore_version=True)

    logging.info("Waiting %.1fs for overlay/fabric settle", OVERLAY_SETTLE_TIME_S)
    time.sleep(OVERLAY_SETTLE_TIME_S)

    data.ol.configure_clock("internal" if args.internal_clock else "external")

    configure_initial_tx(args, data)

    if args.tx_start:
        require_tx_ready_to_start(data)
        for channel in data.tx_channels:
            apply_tx_center_freq(channel, data)

    data.channels = ALL_CHANNELS
    set_channel_ctrl(Ctrl.RESET, data)
    update_adc_nco(args.freq, data)

    verify_pll_locks(data)

    if args.tx_start:
        dac_tiles = sorted({TX_CHANNEL_CONFIG[ch]["dac_tile"] for ch in data.tx_channels})
        verify_pll_locks(data, tiles=dac_tiles, converter_type="dac")

    smoke_test_stream_registers(data)

    if args.tx_start:
        start_tx(data)


def start_initial_capture(args, data):
    if args.reset:
        return

    if args.internal_clock:
        capture_now(data)
    else:
        capture_next_pps(data)


def read_pps_counter(data):
    return max(
        int(stream_for("A", data).register_map.PPS_COUNTER),
        int(stream_for("B", data).register_map.PPS_COUNTER),
        int(stream_for("C", data).register_map.PPS_COUNTER),
        int(stream_for("D", data).register_map.PPS_COUNTER),
    )


def refresh_pps_count(data):
    data.pps_count = read_pps_counter(data)
    return data.pps_count


def main_loop(data):
    pps_last_seen = None
    pps_last_publish = 0.0

    while not exit_flag:
        time.sleep(0.1)
        should_publish = False

        with data.hardware_lock:
            pps = refresh_pps_count(data)

            if pps_last_seen is not None and pps < pps_last_seen:
                logging.info(
                    "PPS counter reset or wrapped: previous=%s current=%s",
                    pps_last_seen,
                    pps,
                )
            pps_last_seen = pps

            now = time.monotonic()
            if (
                data.pps_publish_interval_s > 0
                and now - pps_last_publish >= data.pps_publish_interval_s
            ):
                should_publish = True
                pps_last_publish = now

        if should_publish:
            publish_status(data, "PPS interval")


def shutdown(mqtt_client, data):
    logging.info("Exiting and resetting channels")
    data.accept_commands = False

    with data.hardware_lock:
        if data.ol is not None:
            try:
                data.channels = ALL_CHANNELS
                set_channel_ctrl(Ctrl.RESET, data)
            except Exception:
                logging.exception("Cleanup channel reset failed")

            try:
                disable_all_tx(data)
            except Exception:
                logging.exception("Cleanup TX disable failed")
        data.state = "offline"

    try:
        info = mqtt_client.publish(
            MQTT_STATUS_TOPIC,
            payload=json.dumps(status_payload(data), allow_nan=False),
            qos=0,
            retain=True,
        )
        try:
            info.wait_for_publish(timeout=1.0)
        except Exception:
            pass
        mqtt_client.disconnect()
    except Exception:
        logging.exception("Failed to publish offline status on shutdown")
    finally:
        mqtt_client.loop_stop()


def run(args):
    global data

    setup_logging(args)
    logging.info(
        "Starting RF capture on ADC channels %s at %.3f MHz",
        args.channels,
        args.freq,
    )

    data.f_if_hz = args.freq * 1e6
    data.mqtt_client = setup_mqtt_client()
    publish_starting(data.mqtt_client)

    try:
        with data.hardware_lock:
            initialize_hardware(args, data)
            data.channels = parse_capture_channels(args.channels)
            start_initial_capture(args, data)
            data.state = "ready"
            update_state(data)
            data.accept_commands = True
            send_status(data)
    except Exception as e:
        logging.exception("Fatal RFSoC initialization failure; exiting for restart")
        try:
            publish_startup_error(data.mqtt_client, e)
            data.mqtt_client.disconnect()
            data.mqtt_client.loop_stop()
        except Exception:
            pass
        sys.exit(1)

    try:
        main_loop(data)
    except Exception:
        logging.exception("RF capture service failure")
        publish_status(data, "service failure")
        raise
    finally:
        shutdown(data.mqtt_client, data)


# ---------------------------------------------------------------------------
# CLI and instance lock
# ---------------------------------------------------------------------------


def build_parser():
    parser = argparse.ArgumentParser(description="Tune RFSoC and stream data over QSFP")
    parser.add_argument(
        "-f",
        "--freq",
        type=float,
        default=ADC_IF_MHZ,
        help="IF/NCO frequency in MHz",
    )
    parser.add_argument(
        "-c",
        "--channels",
        type=str,
        nargs="+",
        choices=ALL_CHANNELS,
        default=["A"],
        help="RX channels to capture",
    )
    parser.add_argument(
        "-r",
        "--reset",
        action="store_true",
        help="Start with ADC capture held in reset",
    )
    parser.add_argument(
        "-i",
        "--internal_clock",
        action="store_true",
        help="Use internal clock instead of external ref",
    )
    parser.add_argument(
        "--tx-channel",
        type=str,
        default=None,
        choices=TX_CHANNEL_CHOICES,
        help="TX DAC output channel: A, B, A,B, or None; default is safe-off",
    )
    parser.add_argument(
        "--tx-center-freq",
        type=float,
        default=None,
        help="Stage selected TX DAC RFDC mixer/NCO center frequency in MHz",
    )
    parser.add_argument(
        "--tx-offset-freq",
        type=float,
        default=None,
        help="Stage selected TX function-generator baseband offset frequency in MHz",
    )
    parser.add_argument(
        "--tx-amplitude",
        type=int,
        default=None,
        help=f"TX waveform peak amplitude in DAC bins, 0..{TX_MAX_AMPLITUDE_BINS}",
    )
    parser.add_argument(
        "--tx-start",
        action="store_true",
        help="Start TX after startup configuration is complete",
    )
    parser.add_argument(
        "--log-level",
        "-l",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
    )
    return parser


def acquire_instance_lock():
    try:
        lock_file = open(LOCK_FILE, "w")
    except PermissionError:
        print(f"Permission denied. Try running as root to write to {LOCK_FILE}")
        sys.exit(1)

    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_file.write(str(os.getpid()))
        lock_file.flush()
    except BlockingIOError:
        print("Another instance of this script is already running!")
        sys.exit(1)

    return lock_file


def release_instance_lock(lock_file):
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()
    try:
        os.remove(LOCK_FILE)
    except FileNotFoundError:
        pass


def main():
    for sig in (
        signal.SIGINT,
        signal.SIGTERM,
        signal.SIGHUP,
        signal.SIGQUIT,
        signal.SIGABRT,
    ):
        signal.signal(sig, signal_handler)

    args = build_parser().parse_args()
    lock_file = acquire_instance_lock()

    try:
        run(args)
    finally:
        release_instance_lock(lock_file)


if __name__ == "__main__":
    main()
