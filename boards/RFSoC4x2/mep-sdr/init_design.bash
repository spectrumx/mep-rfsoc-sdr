#!/bin/bash

# Function to clean up project files
cleanup_project() {
    if [ -d "mep-sdr" ]; then
        echo "Removing existing mep-sdr directory"
        rm -rf mep-sdr/
    fi
    
    # Remove Vivado log files
    if ls *.jou *.log 1> /dev/null 2>&1; then
        echo "Removing Vivado log files"
        rm *.jou *.log
    fi
    
    echo "Project cleanup completed"
}

# Parse command line arguments
if [ "$1" = "--clean" ] || [ "$1" = "-c" ]; then
    echo "Clean mode: Removing project files only"
    cleanup_project
    exit 0
fi

# Show usage if help is requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean, -c    Remove existing project files without creating new project"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Default behavior: Remove existing project files (with confirmation) and create new project"
    exit 0
fi

# Default behavior: Check if mep-sdr directory already exists
if [ -d "mep-sdr" ]; then
    echo "WARNING: This will delete all existing project files in the mep-sdr directory."
    echo ""
    read -p "Do you want to continue? [Y/n]: " -n 1 -r
    echo ""
    
    # Default to Y if user just presses Enter
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        cleanup_project
    else
        exit 1
    fi
fi

# Run Vivado to create the project
echo "Creating Vivado project"
vivado -mode batch -source init_design.tcl -notrace -nojournal -nolog