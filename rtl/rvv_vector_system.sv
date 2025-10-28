`include "./rvv_defs.sv"

// Top level module for the RISC-V Vector Extension (RVV) system
// outlines how vector coprocessor subsystems may be integrated to offer rvv support
module rvv_vector_system(
    input  logic        clk,
    input  logic        rst,
    input  logic        alu_rst, // NEW: ALU-only reset
    input  logic [31:0] instr,
    input  logic [31:0] vl, // add vl as input
    output logic [511:0] vreg_out,
    output logic         ready
);
    // Decoder outputs
    valu_mode_t  valu_mode;
    vtype_t      vtype;
    valu_opcode_t opcode;
    logic [4:0]  vd, vs1, vs2, vs3, imm5;
    logic        vm, mem_load, mem_store;

    // Instantiate decoder
    rvv_vector_decoder decoder (
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .vl(vl),
        .valu_mode(valu_mode),
        .vtype(vtype),
        .opcode(opcode),
        .vd(vd),
        .vs1(vs1),
        .vs2(vs2),
        .vs3(vs3),
        .imm5(imm5),
        .vm(vm),
        .mem_load(mem_load),
        .mem_store(mem_store)
    );

    // Instantiate vector register file
    logic [511:0] vreg_rs1, vreg_rs2, vreg_rs3;
    logic         vregfile_we;
    logic [511:0] vregfile_wdata;

    rvv_vector_regfile #(.VLEN(512), .NUM_REGS(32)) vregfile (
        .clk(clk),
        .rst(rst),
        .rs1_addr(vs1),
        .rs2_addr(vs2),
        .rs3_addr(vs3),
        .rs1_data(vreg_rs1),
        .rs2_data(vreg_rs2),
        .rs3_data(vreg_rs3),
        .rd_addr(vd),
        .rd_data(vregfile_wdata),
        .rd_we(vregfile_we)
    );

    // Writeback logic: write result to register file if not store
    assign vregfile_we    = ready && !mem_store;
    assign vregfile_wdata = vreg_out;

    // Instantiate vector processor core
    rvv_vector_top #(.VLEN(512), .ELEN(64)) vector_core (
        .clk(clk),
        .rst(alu_rst && rst),
        .valu_mode(valu_mode),
        .vtype(vtype),
        .vl(vl),
        .opcode(opcode),
        .vs1(vreg_rs1),
        .vs2(vreg_rs2),
        .vs3(vreg_rs3),
        .rs1('0), // connect to scalar regfile soon
        .imm(imm5),
        .vmask('0), // connect from vector regfile to obtain correct vector mask as rs3 on most operations
        .vm(vm),
        .mem_load(mem_load),
        .mem_store(mem_store),
        .vreg_out(vreg_out),
        .ready(ready)
    );
endmodule
