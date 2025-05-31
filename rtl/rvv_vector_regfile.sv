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

    // Read logic (combinational)
    assign rs1_data = regfile[rs1_addr];
    assign rs2_data = regfile[rs2_addr];
    assign rs3_data = regfile[rs3_addr];

    // Write logic (sequential)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < NUM_REGS; i++)
                regfile[i] <= '0;
            // regfile[1] <= 512'h0001_0002_0003_0004_0005_0006_0007_0008_0009_000A_000B_000C_000D_000E_000F_0010; // preloaded value for demonstration
        end
        if (rd_we) begin // vector register does not care if we write to v0
            $display("Writing to regfile[%0d] = %h", rd_addr, rd_data);
            regfile[rd_addr] <= rd_data;
        end
    end
endmodule
