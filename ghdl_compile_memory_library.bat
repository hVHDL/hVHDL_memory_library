echo off

echo %project_root%
FOR /F "tokens=* USEBACKQ" %%F IN (`git rev-parse --show-toplevel`) DO (
SET project_root=%%F
)
SET source=%project_root%/..

ghdl -a --ieee=synopsys --std=08 %source%/hVHDL_memory_library/fpga_ram/ram_read_port_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/hVHDL_memory_library/fpga_ram/ram_write_port_pkg.vhd
ghdl -a --ieee=synopsys --std=08 %source%/hVHDL_memory_library//fpga_ram/fpga_dual_port_ram_pkg.vhd
