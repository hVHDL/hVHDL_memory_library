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

fpga_internal_ram = VU.add_library("fpga_ram")
fpga_internal_ram.add_source_files(ROOT / "fpga_internal_ram/ram_configuration_pkg.vhd")
fpga_internal_ram.add_source_files(ROOT / "fpga_internal_ram/ram_read_base_pkg.vhd")
fpga_internal_ram.add_source_files(ROOT / "fpga_internal_ram/dual_port_ram.vhd")
fpga_internal_ram.add_source_files(ROOT / "fpga_internal_ram/arch_sim_dual_port_ram.vhd")
fpga_internal_ram.add_source_files(ROOT / "testbench/dual_port_ram/tb_dual_port_ram.vhd")

fpga_internal_ram.add_source_files(ROOT / "multi_port_ram/multi_port_ram_pkg.vhd")
fpga_internal_ram.add_source_files(ROOT / "multi_port_ram/ram_read_x2_write_x1.vhd")
fpga_internal_ram.add_source_files(ROOT / "multi_port_ram/arch_sim_read_x2_write_x1.vhd")
fpga_internal_ram.add_source_files(ROOT / "testbench/multi_port_ram/read_x2_write_x1_tb.vhd")


lib.add_source_files(ROOT / "sorting_algorithms/sorting_simulation" / "*.vhd")

lib.add_source_files(ROOT / "fpga_memory_interface_tests/dual_port_ram_interface_tb.vhd")
lib.add_source_files(ROOT / "fpga_memory_interface_tests/ram_read_tb.vhd")
lib.add_source_files(ROOT / "fpga_memory_interface_tests/ram_write_tb.vhd")

lib.add_source_files(ROOT / "testbench/hyperram/hyperram_command_frames_tb.vhd")
VU.main()
