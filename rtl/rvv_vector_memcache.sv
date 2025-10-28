`include "rvv_defs.sv"

/*
    Direct mapped, write-through cache to combine vector memory accesses and scalar memory accesses.
    
    split address to:
    tag | index | offset
    tag = [addr_size - 1 : index_width + offset_width]
    index = [index_width + offset_width - 1 : offset_width]
    offset = [offset_width - 1 : 0]
    since each vector register is 512 bits = 64 bytes, we need 6 bits for offset
    # index bits = clog2(CACHE_LINES)
    # tag bits = 32 - index bits - 6
*/



module rvv_vector_memcache #(
    parameter SCALAR_DATA_WIDTH = 32,
    parameter CACHE_LINES = 64,
    parameter CACHE_LINE_WIDTH = 512,
    parameter ADDRESS_SIZE;
)
(
    input logic        clk,
    input logic        rst,
    input logic [ADDRESS_SIZE - 1:0] scalar_addr,
    input logic [ADDRESS_SIZE - 1:0] vector_addr,   // offset may need to be aligned to 64 bytes based on SEW

    input logic scalar_vector_control, // 0 = scalar, 1 = vector

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
    output logic [ADDRESS_SIZE - 1:0] mem_addr,
    output logic       mem_write_en
);
    localparam OFFSET_WIDTH = $clog2(CACHE_LINE_WIDTH/8);
    localparam INDEX_WIDTH = $clog2(CACHE_LINES);
    localparam TAG_WIDTH = ADDRESS_SIZE - INDEX_WIDTH - 6;

    assign mem_write_data = scalar_vector_control
        ? vector_write_en
        ? vector_write_data : '0
        : scalar_write_en
        ? scalar_write_data : '0;

    assign mem_write_en = vector_write_en || scalar_write_en;

    logic valid [0 : CACHE_LINES - 1];
    logic [7:0] data [0 : OFFSET_WIDTH - 1][0 : CACHE_LINES - 1];
    logic [TAG_WIDTH - 1 : 0] tags [0 : CACHE_LINES - 1];

    // reading logic. if requested data found in cache and is valid, assign it to 
    always_comb begin
        vector_read_data = '0;
        scalar_read_data = '0;

        // break up address to tag | index | offset
        logic address = (scalar_vector_control) ? vector_addr : scalar_addr;
        logic [TAG_WIDTH - 1 : 0] tag = address[ADDRESS_SIZE - 1 : INDEX_WIDTH + OFFSET_WIDTH];
        logic [INDEX_WIDTH - 1 : 0] index = address[INDEX_WIDTH + OFFSET_WIDTH - 1 : OFFSET_WIDTH];
        logic [OFFSET_WIDTH - 1 : 0] offset = address[OFFSET_WIDTH - 1 : 0];

        if (scalar_vector_control) begin
            // vector path: ignore offset and load full cache line
            if (tags[index] == tag) vector_read_data = data[index];


            end else begin
            // scalar path:

        end
    end

endmodule