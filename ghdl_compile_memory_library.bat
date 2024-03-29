echo off

if "%1"=="" (
    set source=./
) else (
    set source=%1
)

rem ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/ram_configuration/ram_configuration_16x1024_pkg.vhd
rem ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/ram_read_port_pkg.vhd
rem ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/ram_write_port_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/fpga_dual_port_ram_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_internal_ram/ram_configuration_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/fpga_internal_ram/dual_port_ram.vhd

ghdl -a --ieee=synopsys --std=08 %source%/multi_port_ram/multi_port_ram_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/multi_port_ram/ram_read_x2_write_x1.vhd
ghdl -a --ieee=synopsys --std=08 %source%/multi_port_ram/ram_read_x4_write_x1.vhd
