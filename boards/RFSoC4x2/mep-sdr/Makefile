SHELL := /bin/bash

VIVADO ?= vivado
VIVADO_FLAGS ?= -mode batch -notrace -nojournal -nolog

PROJECT_NAME := mep-sdr
PROJECT_GLOBS := $(PROJECT_NAME).*
VIVADO_LOG_GLOBS := *.jou *.log *.str

.PHONY: clean project build help

help:
	@echo "Usage:"
	@echo "  make clean    Remove generated Vivado project files and logs"
	@echo "  make project  Clean and recreate the Vivado project"
	@echo "  make build    Clean, recreate the Vivado project, then run synthesis/implementation/bitstream Tcl"

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
