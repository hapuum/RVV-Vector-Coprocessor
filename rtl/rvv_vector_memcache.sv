`include "rvv_defs.sv"

/*
    Direct mapped, write-through cache to combine vector memory accesses and scalar memory accesses.
    
    split address to:
    tag | index | offset

    since each vector register is 512 bits = 64 bytes, we need 6 bits for offset
    # index bits = clog2(CACHE_LINES)
    # tag bits = 32 - index bits - 6
*/



module rvv_vector_memcache #(
    parameter SCALAR_DATA_WIDTH = 32,
    parameter CACHE_LINES = 64,
    parameter CACHE_LINE_WIDTH = 512
)
(
    input logic        clk,
    input logic        rst,
    input logic [31:0] scalar_addr,
    input logic [31:0] vector_addr,   // offset may need to be aligned to 64 bytes based on SEW

    input logic        scalar_write_en,
    input logic        vector_write_en,
    input logic [SCALAR_DATA_WIDTH-1:0] scalar_write_data,
    input logic [CACHE_LINE_WIDTH-1:0] vector_write_data,
    output logic [SCALAR_DATA_WIDTH-1:0] scalar_read_data,
    output logic [CACHE_LINE_WIDTH-1:0] vector_read_data,

    input logic       mem_ready,
    input logic [CACHE_LINE_WIDTH-1:0] mem_read_data,
    output logic      mem_read_en,
    output logic [CACHE_LINE_WIDTH-1:0] mem_write_data,
    output logic [31:0] mem_addr,
    output logic       mem_write_en
);
    localparam OFFSET_WIDTH = $clog2(CACHE_LINE_WIDTH/8);
    localparam INDEX_WIDTH = $clog2(CACHE_LINES);
    localparam TAG_WIDTH = 32 - INDEX_WIDTH - 6;


    assign scalar_read_data = mem_read_data;
    assign vector_read_data = mem_read_data;

    always_comb begin
        
    end

endmodule