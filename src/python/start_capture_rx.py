#!/usr/bin/env python3

import argparse
import fcntl
import json
import logging
import os
import signal
import sys
import time
from enum import Enum

import paho.mqtt.client as mqtt
import pkg_resources
from sdr_overlay import SDROverlay

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BITFILE_NAME = "sdr_bitstream.bit"

service_name = "rfsoc"
MQTT_BROKER = "192.168.20.1"
MQTT_PORT = 1883
MQTT_CMD_TOPIC = service_name + "/command"
MQTT_TLM_TOPIC = "rfcapture/telemetry"
LOG_DIR = os.path.join(os.sep, "var", "log", "spectrumx")
LOCK_FILE = os.path.join(os.sep, "var", "lock", service_name + ".lock")

ADC_SAMPLE_FREQUENCY = 1024  # MSps
ADC_DECIMATION = 16
ADC_IF = 1090  # MHz
ALL_CHANNELS = ["A", "B", "C", "D"]

GREEN = "\033[92m"
BLUE = "\033[94m"
RED = "\033[91m"
RESET = "\033[0m"

exit_flag = False


class Ctrl(Enum):
    CAPTURE = 0
    RESET = 1
    CAPTURE_NEXT_PPS = 3


class CaptureData:
    def __init__(self):
        self.state = "inactive"
        self.f_c_hz = float("nan")
        self.f_if_hz = float("nan")
        self.f_s = float("nan")
        self.channels = []
        self.mqtt_client = None
        self.ol = None


data = CaptureData()


def send_status(data):
    """
    Publish the current state and tuned frequency to the MQTT status topic.
    """
    status_topic = f"{service_name}/status"
    status_payload = {
        "state": data.state,
        "f_c_hz": data.f_c_hz,
        "f_if_hz": data.f_if_hz,
        "f_s": data.f_s,
        "pps_count": getattr(data, "pps_count", 0),
        "channels": data.channels,
    }
    if data.mqtt_client:
        data.mqtt_client.publish(status_topic, json.dumps(status_payload), retain=True)


def signal_handler(sig, frame):
    global exit_flag
    logging.info("Exiting RF capture")
    exit_flag = True


def get_bitfile_path():
    """Get the bitfile path using pkg_resources"""
    try:
        # Try to get the bitfile from the installed package
        bitfile_path = pkg_resources.resource_filename(
            "mep_rfsoc_sdr", f"src/bitstream/{BITFILE_NAME}"
        )
        if os.path.exists(bitfile_path):
            return bitfile_path
    except Exception as e:
        logging.warning(f"Could not find bitfile in package: {e}")

    # Fallback to local path for development
    local_bitfile_path = os.path.join(SCRIPT_DIR, "..", "bitstream", BITFILE_NAME)
    if os.path.exists(local_bitfile_path):
        logging.info(f"Using local bitfile: {local_bitfile_path}")
        return local_bitfile_path

    raise FileNotFoundError(
        f"Could not find bitfile {BITFILE_NAME} in package or local directory"
    )


def on_message(client, userdata, msg):
    global data
    try:
        message = json.loads(msg.payload.decode())
        logging.debug(f"Received MQTT: {message}")
        command = message.get("task_name", None)
        if command is None:
            logging.warning("Invalid command format")
            return

        args = message.get("arguments", "")

        if command == "reset":
            set_channel_ctrl(Ctrl.RESET, data)
            send_status(data)
        elif command == "capture":
            capture_now(data)
            send_status(data)
        elif command == "capture_next_pps":
            capture_next_pps(data)
            send_status(data)
        elif command == "set":
            set_param, set_value = args.split(" ")
            if set_param == "freq_metadata":
                set_freq_metadata(set_value, data)
                send_status(data)
            elif set_param == "freq_IF":
                update_adc_nco(set_value, data)
                send_status(data)
            elif set_param == "channel":
                data.channels = [ch for ch in set_value.split(",")]
                logging.info(f"Set active channels to: {data.channels}")
                set_channel_ctrl(Ctrl.RESET, data)
                send_status(data)
            else:
                logging.warning(f"Unknown set parameter: {set_param} value {set_value}")
        elif command == "get":
            if args and args[0] == "tlm":
                send_status(data)
    except Exception as e:
        logging.error(f"Error processing MQTT message: {e}")


def update_adc_nco(freq_mhz, data):
    freq_mhz = float(freq_mhz)  # <=== THIS LINE FIXES IT
    # metadata only supports tuning with kHz precision, so round to kHz for actual tune
    freq_mhz = round(freq_mhz, 3)
    freq_hz = freq_mhz * 1e6
    data.f_if_hz = freq_hz

    try:
        for tile, block in [(0, 0), (0, 1), (2, 0), (2, 1)]:
            data.ol.set_adc_nco(-freq_mhz, ADC_SAMPLE_FREQUENCY, tile, block)

        set_sample_rate((ADC_SAMPLE_FREQUENCY * 1e6) / ADC_DECIMATION, data)
        set_freq_metadata(freq_hz, data)
        logging.info(f"ADC mixer and metadata updated to {freq_mhz:.2f} MHz")
    except Exception as e:
        logging.error(f"Failed to update full ADC mixer configuration: {e}")


def set_sample_rate(sample_rate, data):
    data.f_s = sample_rate
    sample_rate_raw = sample_rate * ADC_DECIMATION
    logging.info(f"Setting sample rate metadata to: {sample_rate_raw}")
    for ch in data.channels:
        getattr(
            data.ol, f"adc_to_udp_stream_{ch}"
        ).register_map.SAMPLE_RATE_NUMERATOR_LSB = sample_rate_raw


def set_freq_metadata(f_c_hz, data):
    data.f_c_hz = float(f_c_hz)
    f_c_khz = int(round(data.f_c_hz / 1e3))
    logging.info(f"Setting frequency metadata to: {f_c_khz} kHz")
    for ch in data.channels:
        getattr(data.ol, f"adc_to_udp_stream_{ch}").register_map.FREQUENCY_IDX = f_c_khz


def set_channel_ctrl(ctrl, data):
    for ch in data.channels:
        getattr(data.ol, f"adc_to_udp_stream_{ch}").register_map.CTRL = ctrl.value
    data.state = (
        "active" if ctrl in [Ctrl.CAPTURE, Ctrl.CAPTURE_NEXT_PPS] else "inactive"
    )


def capture_now(data):
    set_channel_ctrl(Ctrl.RESET, data)
    for ch in data.channels:
        stream = getattr(data.ol, f"adc_to_udp_stream_{ch}")
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
    samples_since_epoch = int(current_time_s * data.f_s)
    lsb = samples_since_epoch & 0xFFFFFFFF
    msb = samples_since_epoch >> 32
    for ch in data.channels:
        stream = getattr(data.ol, f"adc_to_udp_stream_{ch}")
        stream.register_map.SAMPLE_IDX_OFFSET_LSB = lsb
        stream.register_map.SAMPLE_IDX_OFFSET_MSB = msb
    set_channel_ctrl(Ctrl.CAPTURE_NEXT_PPS, data)


def main(args):
    """
    Main function for the RX capture script

    Args:
        args (argparse.Namespace): Command-line arguments.

    """
    global exit_flag, data
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

    logging.info(
        f"Starting RF capture on ADC Channel {BLUE}{args.channels}{RESET} at {BLUE}{args.freq:.3f} MHz{RESET}"
    )
    data.f_if_hz = args.freq * 1e6
    data.pps_count = 0

    # Setup MQTT client
    mqtt_client = mqtt.Client(client_id=service_name)
    mqtt_client.on_message = on_message
    mqtt_client.will_set(
        service_name + "/status",
        payload=json.dumps({"state": "offline"}),
        qos=0,
        retain=True,
    )
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
    mqtt_client.subscribe(MQTT_CMD_TOPIC)
    mqtt_client.loop_start()
    data.mqtt_client = mqtt_client

    mqtt_client.publish(
        service_name + "/status",
        payload=json.dumps({"state": "online"}),
        qos=0,
        retain=True,
    )

    # Initialize RFSoC Overlay
    logging.info("Initializing RFSoC 10G Overlay")
    bitfile_path = get_bitfile_path()
    print(f"Opening Overlay with bitfile: {bitfile_path}")
    data.ol = SDROverlay(bitfile_name=bitfile_path, ignore_version=True)

    # Wait for overlay to initialize
    time.sleep(5)

    # Set active channels
    data.channels = ALL_CHANNELS
    set_channel_ctrl(Ctrl.RESET, data)
    data.channels = args.channels

    # Configure clock
    data.ol.configure_clock("internal" if args.internal_clock else "external")

    # Apply initial ADC config
    update_adc_nco(args.freq, data)

    # Start Capture
    if not args.reset:
        if args.internal_clock:
            capture_now(data)
        else:
            capture_next_pps(data)

    pps_count_last = 0
    try:
        while not exit_flag:
            time.sleep(0.1)
            pps = max(
                int(data.ol.adc_to_udp_stream_A.register_map.PPS_COUNTER),
                int(data.ol.adc_to_udp_stream_B.register_map.PPS_COUNTER),
                int(data.ol.adc_to_udp_stream_C.register_map.PPS_COUNTER),
                int(data.ol.adc_to_udp_stream_D.register_map.PPS_COUNTER),
            )
            if pps > pps_count_last:
                data.pps_count = pps
                pps_count_last = pps
    finally:
        mqtt_client.loop_stop()

    logging.info("Exiting and resetting channels.")
    data.channels = ALL_CHANNELS
    set_channel_ctrl(Ctrl.RESET, data)


if __name__ == "__main__":
    for sig in [
        signal.SIGINT,
        signal.SIGTERM,
        signal.SIGHUP,
        signal.SIGQUIT,
        signal.SIGABRT,
    ]:
        signal.signal(sig, signal_handler)

    parser = argparse.ArgumentParser(description="Tune RFSoC and stream data over QSFP")
    parser.add_argument(
        "-f", "--freq", type=float, default=ADC_IF, help="IF/NCO frequency in MHz"
    )
    parser.add_argument(
        "-c",
        "--channels",
        type=str,
        nargs="*",
        choices=ALL_CHANNELS,
        default=["A"],
        help="Channels to capture",
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
        "--log-level",
        "-l",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
    )
    args = parser.parse_args()

    try:
        f = open(LOCK_FILE, "w")
    except PermissionError:
        print(f"Permission denied. Try running as root to write to {LOCK_FILE}")
        sys.exit(1)

    try:
        # 2. Try to acquire an EXCLUSIVE lock (LOCK_EX) without blocking (LOCK_NB)
        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        # 3. Best Practice: Write the process PID into the file for debugging
        f.write(str(os.getpid()))
        f.flush()
    except BlockingIOError:
        print("Another instance of this script is already running!")
        sys.exit(1)

    main(args)

    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    f.close()
    os.remove(LOCK_FILE)
