import xrfclk
import xrfdc
from pynq import Overlay


class SDROverlay(Overlay):
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
