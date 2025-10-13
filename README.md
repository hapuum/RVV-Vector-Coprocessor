RISC-V Vector Coprocessor 

This Coprocessor is a RTL verified proof of concept for a "pluggable vector coprocessor", as a project for EE 470 Computer Architecture II course.
Meets integer subset of RVV1.0 requirements with max 512 bit vectors. 
To configure this RTL with your own processor:
- vector decoder is to be inserted in the decoder pipeline of regular pipelined processor, with its vector specific outputs connected to rvv_vector_top.
- rvv_vector_top contains the top-level coprocessor module, including vector ALUs and vector load/store units and vector writeback/scalar writeback unit that needs to be connected to the existing regfile of the host processor.
- rvv_vector_regfile processes the singals from load/store units and contains the specialized memory module for this project, supporting 512bit load/stores.
- rvv_vector_system.sv contains a example of how one system may be configured.

With ideal vector load/stores and computation setup (such as matrix multiply, vector addition) this can mean up to (512/32 = 16)x speedup per cycle compared to original RISC-V Pipelined Processor.
As a project not verified through synthesis and purely at RTL level for proof of concept, analysis on synthesis and cycle timing is currently not offered.
On Simulation, this has roughly 5.3x speedup in terms of cycle count, but in synthesis the timing constraints will be tighter and will slow down a bit.

