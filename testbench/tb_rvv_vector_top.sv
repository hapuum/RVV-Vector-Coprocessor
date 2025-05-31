module tb_rvv_vector_top;
    // Clock and reset
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    // DUT signals
    logic [31:0]       vl;
    logic [31:0]       instr;
    logic              alu_rst;
    logic [511:0]      vreg_out;
    logic              ready;

    // Instantiate DUT (rvv_vector_system)
    rvv_vector_system dut (
        .clk(clk),
        .rst(rst),
        .alu_rst(1'b1),
        .instr(instr),
        .vl(vl),
        .vreg_out(vreg_out),
        .ready(ready)
    );

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_rvv_vector_top);

        rst = 1; #20; rst = 0; #20;

        // Set up test: set vl = 8
        vl = 8;
        // Provide a valid vector instruction (example: vadd.vv)
        instr = 32'b0000000_00010_00001_000_00011_1010111; // Example encoding
        // Wait for ready
        wait (ready == 1);
        $display("Result: %h", vreg_out);
        $finish;
    end
endmodule

