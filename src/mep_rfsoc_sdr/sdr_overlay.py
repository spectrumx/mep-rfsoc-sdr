import xrfclk
import xrfdc
from pynq import Overlay


class SDROverlay(Overlay):
    SUPPORTED_ADC_DECIMATION_FACTORS = (
        1,
        2,
        3,
        4,
        5,
        6,
        8,
        10,
        12,
        16,
        20,
        24,
        40,
    )

    def __init__(self, bitfile_name, **kwargs):
        super().__init__(bitfile_name, **kwargs)
        # SDR Overlay initialization

    def configure_clock(self, clock_source="internal"):
        if clock_source == "internal":
            xrfclk.set_ref_clks(lmk_freq=245.76, lmx_freq=491.52)
        else:
            xrfclk.set_ref_clks(lmk_freq=122.88, lmx_freq=491.52)

    def set_adc_nco(self, f_c_mhz, f_s_mhz, tile, block):
        """Set the ADC NCO frequency"""
        # Convert to floats
        f_c_mhz = float(f_c_mhz)
        f_s_mhz = float(f_s_mhz)
        pll_freq = 491.52  # MHz — assumed static LMX freq

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
        adc_tile.DynamicPLLConfig(1, pll_freq, f_s_mhz)
        adc_tile.blocks[block].NyquistZone = 1
        adc_tile.blocks[block].MixerSettings = mixer
        adc_tile.blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)
        adc_tile.SetupFIFO(True)

    def set_adc_decimation(self, decimation, tile, block):
        """Set the ADC decimation factor for one RFDC ADC block.

        This does not change RFDC fabric clocks or downstream metadata.
        Callers must use a factor compatible with the loaded bitstream.
        """
        decimation_value = self._adc_decimation_factor_value(decimation)
        self.rfdc.adc_tiles[tile].blocks[block].DecimationFactor = decimation_value

    def set_dac_nco(self, f_c_mhz, f_s_mhz, tile, block):
        """Set the DAC NCO frequency"""
        f_c_mhz = float(f_c_mhz)
        f_s_mhz = float(f_s_mhz)
        pll_freq = 491.52  # MHz — assumed static LMX freq

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
        dac_tile.DynamicPLLConfig(1, pll_freq, f_s_mhz)
        dac_tile.blocks[block].NyquistZone = self._nyquist_zone(f_c_mhz, f_s_mhz)
        dac_tile.blocks[block].MixerSettings = mixer
        dac_tile.blocks[block].UpdateEvent(xrfdc.EVENT_MIXER)

    @staticmethod
    def _nyquist_zone(f_c_mhz, f_s_mhz):
        half_sample_rate = f_s_mhz / 2.0
        if half_sample_rate <= 0:
            raise ValueError("Sample rate must be greater than 0 MHz")
        return 2 if abs(f_c_mhz) > half_sample_rate else 1

    @classmethod
    def _adc_decimation_factor_value(cls, factor):
        try:
            factor = int(factor)
        except (TypeError, ValueError):
            raise ValueError(
                f"RFDC decimation factor must be one of {cls.SUPPORTED_ADC_DECIMATION_FACTORS}"
            )

        if factor not in cls.SUPPORTED_ADC_DECIMATION_FACTORS:
            raise ValueError(
                f"RFDC decimation factor must be one of {cls.SUPPORTED_ADC_DECIMATION_FACTORS}"
            )

        return getattr(xrfdc, f"INTERP_DECIM_{factor}X", factor)
