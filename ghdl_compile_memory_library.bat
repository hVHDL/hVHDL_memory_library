echo off

echo %project_root%
FOR /F "tokens=* USEBACKQ" %%F IN (`git rev-parse --show-toplevel`) DO (
SET project_root=%%F
)
SET source=%project_root%/../memory_library

ghdl -a --ieee=synopsys --std=08 %source%/fpga_ram/fpga_dual_port_ram_pkg.vhd
