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

fpga_ram = VU.add_library("fpga_ram")
fpga_ram.add_source_files(ROOT / "fpga_internal_ram/ram_configuration_pkg.vhd")
fpga_ram.add_source_files(ROOT / "fpga_internal_ram/dual_port_ram.vhd")
fpga_ram.add_source_files(ROOT / "fpga_internal_ram/arch_sim_dual_port_ram.vhd")
fpga_ram.add_source_files(ROOT / "testbench/dual_port_ram/tb_dual_port_ram.vhd")

fpga_ram.add_source_files(ROOT / "multi_port_ram/multi_port_ram_pkg.vhd")
fpga_ram.add_source_files(ROOT / "multi_port_ram/ram_read_x2_write_x1.vhd")
fpga_ram.add_source_files(ROOT / "multi_port_ram/arch_sim_read_x2_write_x1.vhd")
fpga_ram.add_source_files(ROOT / "testbench/multi_port_ram/read_x2_write_x1_tb.vhd")
fpga_ram.add_source_files(ROOT / "multi_port_ram/multi_port_ram_entity.vhd")
fpga_ram.add_source_files(ROOT / "multi_port_ram/arch_sim_multi_port_ram.vhd")


lib.add_source_files(ROOT / "sorting_algorithms/sorting_simulation" / "*.vhd")

lib.add_source_files(ROOT / "fpga_memory_interface_tests/dual_port_ram_interface_tb.vhd")
lib.add_source_files(ROOT / "fpga_memory_interface_tests/ram_read_tb.vhd")
lib.add_source_files(ROOT / "fpga_memory_interface_tests/ram_write_tb.vhd")


generic_fpga_ram = VU.add_library("generic_fpga_ram")
generic_fpga_ram.add_source_files(ROOT / "fpga_internal_ram/dual_port_ram_generic_pkg.vhd")
generic_fpga_ram.add_source_files(ROOT / "fpga_internal_ram/arch_sim_generic_dual_port_ram.vhd")

generic_fpga_ram.add_source_files(ROOT / "testbench/sample_buffer/sample_trigger_generic_pkg.vhd")

generic_fpga_ram.add_source_files(ROOT / "testbench/dual_port_ram/generic_dual_port_ram_tb.vhd")
generic_fpga_ram.add_source_files(ROOT / "testbench/sample_buffer/sample_buffer_tb.vhd")
generic_fpga_ram.add_source_files(ROOT / "testbench/sample_buffer/buffer_pointers_tb.vhd")
generic_fpga_ram.add_source_files(ROOT / "testbench/sample_buffer/controlled_sample_tb.vhd")

generic_fpga_ram.add_source_files(ROOT / "testbench/hyperram/hyperram_command_frames_tb.vhd")

generic_fpga_ram.add_source_files(ROOT / "testbench/hyperram/hyperram_interface_pkg.vhd")
generic_fpga_ram.add_source_files(ROOT / "testbench/hyperram/hyperram_io_tb.vhd")

generic_fpga_ram.add_source_files(ROOT / "multi_port_ram/generic_multi_port_ram_pkg.vhd")
generic_fpga_ram.add_source_files(ROOT / "testbench/multi_port_ram/generic_multi_port_ram_tb.vhd")

generic_fpga_ram.add_source_files(ROOT / "testbench/multi_port_ram/multi_write_ram_tb.vhd")

ram_wo_generic_packages = VU.add_library("ram_wo_generic_packages")
ram_wo_generic_packages.add_source_files(ROOT / "testbench/dual_port_ram/dp_ram_w_configurable_recrods.vhd")
ram_wo_generic_packages.add_source_files(ROOT / "testbench/dual_port_ram/tb_configurable_dp_ram.vhd")
ram_wo_generic_packages.add_source_files(ROOT / "testbench/dual_port_ram/mpram_w_configurable_records.vhd")
ram_wo_generic_packages.add_source_files(ROOT / "testbench/dual_port_ram/configurable_multi_port_ram_tb.vhd")

# VU.set_sim_option("nvc.sim_flags", ["-w"])

VU.main()
