# memory_library

Library for FPGA memory drivers for synthesis on fpga

## rams

vhdl2008/ : the dual port ram (dp_ram_w_configurable_records.vhd, entity dual_port_ram,
package dual_port_ram_pkg) and the multi port ram (mpram_w_configurable_records.vhd, entity
multi_port_ram, package multi_port_ram_pkg). The records' fields are unconstrained: each
instance sets its data and address widths from create_ref_subtypes, no generic packages. The
arch_rtl_* files are the synthesis architectures of the dual port ram (one to choose),
arch_sim_* the simulation one. Their testbenches are in testbench/dual_port_ram and
testbench/multi_port_ram.

vhdl2008/sdp_ram_w_configurable_records.vhd : the simple dual port ram (entity
simple_dual_port_ram), one port that only writes and one that only reads, with the same records
and procedures. Synthesis maps it to the block RAMs' simple dual port mode, twice as wide as the
true dual port mode dual_port_ram gets (Efinix Titanium: 512 x 20 against 1024 x 10), so a ram
written on one port and read on the other takes about half the blocks. multi_port_ram is built
of them (a copy per read port, each written by the write port). Its testbench is in
testbench/simple_dual_port_ram.

## hyperram

hyperram/hyperram_core.vhd : a HyperRAM (W959D8NFYA, x8, two dies) controller with a native
interface of 16 bit words: a command (write or read, a word address, 1..512 words within 1 KB),
the write words asked for one a clock (the client's registered answer), the read words given back
one a clock, a timed out read padded; its pins, timing, read capture and the calibration of the
read clock's phase at power up are all here. hyperram/hyperram_axi.vhd puts an AXI3 port (a
shared read/write address channel) in front of it: its queue, write and read buffers, burst
splitting and in order responses. Tested on hardware: a Titanium Ti60 at 200 MHz as the DDR
memory of a Sapphire SoC. hyperram/hyperram_pkg.vhd has the command/address frames and the pin
records; testbench/hyperram has a model of the memory and both testbenches (hyperram_core_tb
through the native interface, hyperram_axi_tb through AXI).

## sample buffer

sample_buffer/sample_trigger_generic_pkg.vhd : the trigger and the write and read addresses
of a ring buffer of samples in a dual port ram, as in fpga_communication's signal_scope.

## legacy

legacy/ : the earlier rams, for the designs that still use them; new designs use vhdl2008/.

    fpga_ram/                   rams built by procedures on a record signal, 1024 integers
    fpga_internal_ram/dual_port_ram.vhd, multi_port_ram/ (but generic_multi_port_ram_pkg.vhd)
                                entities, one size for all from ram_configuration_pkg
    fpga_internal_ram/dual_port_ram_generic_pkg.vhd, multi_port_ram/generic_multi_port_ram_pkg.vhd
                                entities sized by generic packages
    testbench/hyperram/         the first HyperRAM command frame and io tests
    sorting_algorithms/, fpga_memory_interface_tests/, ghdl_compile_memory_library.bat

The generations reuse names (dual_port_ram, multi_port_ram, multi_port_ram_pkg,
ram_configuration_pkg), so vunit_run_memory_library.py compiles them into separate libraries.

## tests

    python3 vunit_run_memory_library.py
