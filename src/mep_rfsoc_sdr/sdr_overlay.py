import xrfclk
import xrfdc
from pynq import Overlay


class SDROverlay(Overlay):
    # LMX synthesizer output feeding every converter tile clock input (MHz).
    # This is the tile PLL reference; it must match the reference the
    # bitstream's RFDC IP was built for. Changing it is not a software-only
    # change and requires rebuilding the bitstream.
    LMX_FREQ_MHZ = 491.52

    def __init__(self, bitfile_name, **kwargs):
        super().__init__(bitfile_name, **kwargs)
        # SDR Overlay initialization

    def configure_clock(self, clock_source="internal"):
        """
        Program the board clock chain that feeds the converter tiles.

        The chain is two chips in series:
            LMK -> LMK04828 jitter cleaner; produces a clean reference for the LMX.
            LMX -> LMX2594 RF synthesizer; multiplies that reference up to
                   LMX_FREQ_MHZ and drives it into every converter tile clock input.

        clock_source loads a LMK04828 register file which configures PLL1's input
        source. The critical register is 0x147 bit 4 (CLKin_SEL0_TYPE): 0 makes
        the pin a hardware input so the board can select the external SMA clock;
        1 makes it an output, fixing the onboard VCXO path.
        """
        if clock_source == "internal":
            # Selected key registers in LMK04828_245.76.txt:
            #   0x147 bit4 (CLKin_SEL0_TYPE) = 1  output pin, fixes onboard VCXO path
            #   0x154 (CLKin2 R divider LSB)  = 0x7D (125)
            #   0x159 bits[2:0] (PLL1 CP gain)= 0x07
            #   0x15A bit4 (PLL1 CP gain)     = 1
            xrfclk.set_ref_clks(lmk_freq=245.76, lmx_freq=self.LMX_FREQ_MHZ)
        elif clock_source == "external":
            # Selected key registers in LMK04828_122.88.txt:
            #   0x147 bit4 (CLKin_SEL0_TYPE) = 0  input pin, board selects external SMA clock
            #   0x154 (CLKin2 R divider LSB)  = 0x0C (12)
            #   0x159 bits[2:0] (PLL1 CP gain)= 0x00
            #   0x15A bit4 (PLL1 CP gain)     = 0
            xrfclk.set_ref_clks(lmk_freq=122.88, lmx_freq=self.LMX_FREQ_MHZ)
        else:
            raise ValueError(f"Unknown clock_source: {clock_source!r}. Expected 'internal' or 'external'.")

    def set_adc_nco(self, f_c_mhz, f_s_mhz, tile, block):
        """Set the ADC NCO frequency"""
        # Convert to floats
        f_c_mhz = float(f_c_mhz)
        f_s_mhz = float(f_s_mhz)
        pll_freq = self.LMX_FREQ_MHZ  # LMX output = tile PLL reference

        mixer = {
            "CoarseMixFreq": xrfdc.COARSE_MIX_BYPASS,
            "EventSource": xrfdc.EVNT_SRC_TILE,
            "FineMixerScale": xrfdc.MIXER_SCALE_1P0,
            "Freq": f_c_mhz,
            "MixerMode": xrfdc.MIXER_MODE_R2C,
            "MixerType": xrfdc.MIXER_TYPE_FINE,
            "PhaseOffset": 0.0,
        }

        adc_tile = self.rfdc.adc_tiles[tile]
        # DynamicPLLConfig Source arg (XRFDC_INTERNAL_PLL_CLK = 0x1): use the
        # on-chip PLL to multiply pll_freq up to f_s. The alternative,
        # XRFDC_EXTERNAL_CLK = 0x0, bypasses the PLL and uses the incoming
        # clock directly as the sample clock.
        adc_tile.DynamicPLLConfig(1, pll_freq, f_s_mhz)
        adc_tile.blocks[block].NyquistZone = self._nyquist_zone(f_c_mhz, f_s_mhz)
        adc_tile.blocks[block].MixerSettings = mixer
        adc_tile.blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        adc_tile.SetupFIFO(True)

    def set_dac_nco(self, f_c_mhz, f_s_mhz, tile, block):
        """Set the DAC NCO frequency"""
        f_c_mhz = float(f_c_mhz)
        f_s_mhz = float(f_s_mhz)
        pll_freq = self.LMX_FREQ_MHZ  # LMX output = tile PLL reference

        mixer = {
            "CoarseMixFreq": xrfdc.COARSE_MIX_BYPASS,
            "EventSource": xrfdc.EVNT_SRC_TILE,
            "FineMixerScale": xrfdc.MIXER_SCALE_1P0,
            "Freq": f_c_mhz,
            "MixerMode": xrfdc.MIXER_MODE_C2R,
            "MixerType": xrfdc.MIXER_TYPE_FINE,
            "PhaseOffset": 0.0,
        }

        dac_tile = self.rfdc.dac_tiles[tile]
        # DynamicPLLConfig Source arg (XRFDC_INTERNAL_PLL_CLK = 0x1): use the
        # on-chip PLL to multiply pll_freq up to f_s. The alternative,
        # XRFDC_EXTERNAL_CLK = 0x0, bypasses the PLL and uses the incoming
        # clock directly as the sample clock.
        dac_tile.DynamicPLLConfig(1, pll_freq, f_s_mhz)
        dac_tile.blocks[block].NyquistZone = self._nyquist_zone(f_c_mhz, f_s_mhz)
        dac_tile.blocks[block].MixerSettings = mixer
        dac_tile.blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        dac_tile.SetupFIFO(True)

    def get_pll_config(self, converter_type, tile):
        """
        Read back the PLL configuration and lock status for a tile.

        Wraps the xrfdc PLLConfig property (populated from XRFdc_GetPLLConfig)
        and the raw PLLLockStatus property (from XRFdc_GetPLLLockStatus:
        XRFDC_PLL_UNLOCKED = 0x1, XRFDC_PLL_LOCKED = 0x2). The raw value is
        returned as-is so the caller compares against the driver's own
        constant rather than relying on a literal here.

        converter_type: "adc" or "dac"
        tile: tile index

        Returns a dict with the reference clock, sample rate, divider values
        the driver chose, the raw lock status, and the sample rate
        reconstructed from the dividers as a consistency check.
        """
        converter_type = converter_type.lower()
        if converter_type == "adc":
            tile_obj = self.rfdc.adc_tiles[tile]
        elif converter_type == "dac":
            tile_obj = self.rfdc.dac_tiles[tile]
        else:
            raise ValueError("converter_type must be 'adc' or 'dac'")

        pll = tile_obj.PLLConfig

        config = {
            "converter_type": converter_type,
            "tile": tile,
            "enabled": pll.get("Enabled"),
            "ref_clk_freq_mhz": pll.get("RefClkFreq"),
            "sample_rate_mhz": pll.get("SampleRate"),
            "ref_clk_divider": pll.get("RefClkDivider"),
            "feedback_divider": pll.get("FeedbackDivider"),
            "output_divider": pll.get("OutputDivider"),
            "pll_lock_status": tile_obj.PLLLockStatus,
        }

        out_div = config["output_divider"]
        if out_div:
            config["calculated_sample_rate_mhz"] = (
                config["ref_clk_freq_mhz"] * config["feedback_divider"] / out_div
            )

        return config

    @staticmethod
    def _nyquist_zone(f_c_mhz, f_s_mhz):
        """
        Return the RFSoC NyquistZone setting for a given carrier.

        f_c_mhz: carrier / NCO center frequency in MHz
        f_s_mhz: ADC sample rate in MHz

        The hardware wants PARITY, not the literal zone:
            odd physical zones (1, 3, 5, ...) -> 1
            even physical zones (2, 4, 6, ...) -> 2
        because only the spectral inversion (which flips on even zones)
        affects calibration and NCO tuning direction.
        """
        half = f_s_mhz / 2.0
        if half <= 0:
            raise ValueError("Sample rate must be greater than 0 MHz")
        physical_zone = int(abs(f_c_mhz) // half) + 1   # 1, 2, 3, 4, ...
        return 1 if (physical_zone % 2 == 1) else 2      # odd -> 1, even -> 2
