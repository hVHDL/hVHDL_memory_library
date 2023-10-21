echo off

SET source=%1

rem ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/ram_configuration/ram_configuration_16x1024_pkg.vhd
rem ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/ram_read_port_pkg.vhd
rem ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/ram_write_port_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/fpga_dual_port_ram_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_internal_ram/ram_configuration_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_internal_ram/ram_read_base_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_internal_ram/dual_port_ram.vhd
