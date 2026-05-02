SHELL := /bin/bash

VIVADO ?= vivado
VIVADO_FLAGS ?= -mode batch -notrace -nojournal -nolog

PROJECT_NAME := mep-sdr
PROJECT_GLOBS := $(PROJECT_NAME).*
VIVADO_LOG_GLOBS := *.jou *.log *.str
RELEASE_DIR := ../../../src/bitstream
BITSTREAM := $(PROJECT_NAME).runs/impl_1/block_design_wrapper.bit
HWH := $(PROJECT_NAME).gen/sources_1/bd/block_design/hw_handoff/block_design.hwh

.PHONY: clean project build release help

help:
	@echo "Usage:"
	@echo "  make clean    Remove generated Vivado project files and logs"
	@echo "  make project  Clean and recreate the Vivado project"
	@echo "  make build    Clean, recreate the Vivado project, then run synthesis/implementation/bitstream Tcl"
	@echo "  make release  Copy generated bitstream and handoff files into src/bitstream"

clean:
	@echo "Removing generated Vivado project files"
	@rm -rf $(PROJECT_GLOBS)
	@echo "Removing Vivado log files"
	@rm -f $(VIVADO_LOG_GLOBS)
	@echo "Project cleanup completed"

project: clean
	@echo "Creating Vivado project"
	@$(VIVADO) $(VIVADO_FLAGS) -source init_design.tcl
	@echo "Project initialization completed successfully. You can now open the project with: vivado $(PROJECT_NAME).xpr"

build: project
	@echo "Starting build process (synthesis, implementation, and bitstream generation)"
	@$(VIVADO) $(VIVADO_FLAGS) -source build_design.tcl
	@echo "Build process completed successfully"

release: $(BITSTREAM) $(HWH)
	@echo "Copying generated bitstream and handoff files to $(RELEASE_DIR)"
	@mkdir -p $(RELEASE_DIR)
	@cp $(BITSTREAM) $(RELEASE_DIR)/sdr_bitstream.bit
	@cp $(HWH) $(RELEASE_DIR)/sdr_bitstream.hwh
	@echo "Release files updated:"
	@echo "  $(RELEASE_DIR)/sdr_bitstream.bit"
	@echo "  $(RELEASE_DIR)/sdr_bitstream.hwh"
