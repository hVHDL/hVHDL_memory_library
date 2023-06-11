#!/usr/bin/env python3

from pathlib import Path
from vunit import VUnit

# ROOT
ROOT = Path(__file__).resolve().parent
VU = VUnit.from_argv()

lib = VU.add_library("memory")
lib.add_source_files(ROOT / "fpga_ram/ram_configuration/ram_configuration_16x1024_pkg.vhd")
lib.add_source_files(ROOT / "fpga_ram" / "*.vhd")
lib.add_source_files(ROOT / "fpga_ram/fpga_ram_simulation" / "*.vhd")

lib.add_source_files(ROOT / "hyperram" / "*.vhd")
lib.add_source_files(ROOT / "hyperram/hyperram_simulation" / "*.vhd")

lib.add_source_files(ROOT / "sorting_algorithms/sorting_simulation" / "*.vhd")

lib.add_source_files(ROOT / "fpga_memory_interface_tests" / "*.vhd")

lib.add_source_files(ROOT / "testbench/hyperram/hyperam_tb.vhd")

VU.main()
