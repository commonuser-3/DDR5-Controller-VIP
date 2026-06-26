# DDR5 Memory Module

This folder contains the DDR5 DRAM memory-module RTL and integration notes.

Target configuration:

- DDR standard/profile: DDR5-6400
- Data rate: 6400 MT/s
- DRAM CK frequency: 3200 MHz
- Controller/DFI clock: 800 MHz
- DFI ratio: 1:4
- DIMM channel organization: two independent 32-bit channels
- Burst length: BL16

Files:

- `ddr5.sv` - working CA-decoding DDR5 DRAM model with two 32-bit channels.
- `ddr5_6400_parameters.sv` - DDR5-6400 / 3200 MHz CK timing and geometry parameters.
- `ddr5_mem_if.sv` - DDR5 pin-level memory interface used by `ddr5.sv`.
- `DDR5_DRAM_INTEGRATION_NOTES.md` - integration notes, diagrams, assumptions, and known controller follow-ups.
