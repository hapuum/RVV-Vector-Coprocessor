`include "./rvv_defs.sv"
module rvv_vector_regfile #(
    parameter VLEN = 512,
    parameter NUM_REGS = 32
)(
    input  logic              clk,
    input  logic              rst,
    // Read ports
    input  logic [4:0]        rs1_addr,
    input  logic [4:0]        rs2_addr,
    input  logic [4:0]        rs3_addr,
    output logic [VLEN-1:0]   rs1_data,
    output logic [VLEN-1:0]   rs2_data,
    output logic [VLEN-1:0]   rs3_data,
    // Write port
    input  logic [4:0]        rd_addr,
    input  logic [VLEN-1:0]   rd_data,
    input  logic              rd_we
);
    logic [VLEN-1:0] regfile [NUM_REGS-1:0];

    // riscv reads from 3 different vector registers
    assign rs1_data = regfile[rs1_addr];
    assign rs2_data = regfile[rs2_addr];
    assign rs3_data = regfile[rs3_addr];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < NUM_REGS; i++)
                regfile[i] <= '0;
        end
        if (rd_we) begin // vector register does not care if we write to v0
            //$display("Writing to regfile[%0d] = %h", rd_addr, rd_data);
            regfile[rd_addr] <= rd_data;
        end
    end
endmodule
