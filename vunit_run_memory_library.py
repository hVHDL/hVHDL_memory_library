#!/usr/bin/env python3

from pathlib import Path
from vunit import VUnit

# ROOT
ROOT = Path(__file__).resolve().parent
VU = VUnit.from_argv()

lib = VU.add_library("default")
lib.add_source_files(ROOT / "hyperram" / "*.vhd")
lib.add_source_files(ROOT / "hyperram/hyperram_simulation" / "*.vhd")
# mathlib.add_source_files(ROOT / "multiplier" / "simulation" / "tb_multiplier.vhd") 

VU.main()
