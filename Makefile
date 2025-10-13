TOP		   = rvv_vector_top
RTL        = rtl/rvv_defs.sv rtl/agu.sv rtl/rvv_vector_regfile.sv rtl/rvv_vector_decoder.sv rtl/rvv_vector_top.sv rtl/rvv_vector_system.sv
TB         = testbench/tb_rvv_vector_top.sv
EXE        = sim_$(TOP)
CFLAGS     = -O2
VERILATOR_FLAGS = -Wall --cc --trace --exe --build -Wno-UNUSED -Wno-WIDTH -Wno-DECLFILENAME -Wno-VARHIDDEN --Wno-fatal

# --- Targets ---
all: $(EXE)

$(EXE): $(RTL) $(TB) sim_main.cpp
	verilator $(VERILATOR_FLAGS) \
        +incdir+rtl \
        -CFLAGS "$(CFLAGS) -I/usr/share/verilator/include -I/usr/share/verilator/include/vltstd" \
        --top-module $(TOP) \
        $(RTL) $(TB) sim_main.cpp -o $(EXE)

# Add a target for rvv_vector_system simulation
sim_rvv_vector_system: rtl/rvv_defs.sv rtl/agu.sv rtl/rvv_vector_regfile.sv rtl/rvv_vector_decoder.sv rtl/rvv_vector_top.sv rtl/rvv_vector_system.sv sim_main.cpp
	verilator $(VERILATOR_FLAGS) \
        +incdir+rtl \
        -CFLAGS "$(CFLAGS) -I/usr/share/verilator/include -I/usr/share/verilator/include/vltstd" \
        --top-module rvv_vector_system \
        rtl/rvv_defs.sv rtl/agu.sv rtl/rvv_vector_regfile.sv rtl/rvv_vector_decoder.sv rtl/rvv_vector_top.sv rtl/rvv_vector_system.sv sim_main.cpp -o sim_rvv_vector_system

iverilog:
	iverilog -g2012 -Irtl -o tb_rvv_vector_top.vvp rtl/rvv_defs.sv rtl/agu.sv rtl/rvv_vector_regfile.sv rtl/rvv_vector_decoder.sv rtl/rvv_vector_top.sv testbench/tb_rvv_vector_top.sv

run: iverilog
	vvp tb_rvv_vector_top.vvp

.PHONY: sim
sim: sim_rvv_vector_system
	./obj_dir/sim_rvv_vector_system

clean:
	rm -rf obj_dir sim_rvv_vector_top sim_rvv_vector_system $(VCD)