# memory_library

Library for FPGA memory drivers for synthesis on fpga

## hyperram

hyperram/hyperram_axi.vhd : a HyperRAM (W959D8NFYA, x8, two dies) controller behind an AXI3
port with a shared read/write address channel, with the phase of the read clock calibrated
at power up. Tested on hardware: a Titanium Ti60 at 200 MHz as the DDR memory of a Sapphire
SoC. hyperram/hyperram_pkg.vhd has the command/address frames and the pin records, and
testbench/hyperram has a model of the memory and the controller's testbench.
