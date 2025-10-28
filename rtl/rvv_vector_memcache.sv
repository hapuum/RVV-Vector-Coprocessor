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

    input logic scalar_vector_control, // 0 = scalar, 1 = vector

    // input from processor
    input logic [ADDRESS_SIZE - 1:0] scalar_addr,
    input logic [ADDRESS_SIZE - 1:0] vector_addr,
    input logic scalar_read_en;
    input logic vector_read_en;
    input logic scalar_write_en,
    input logic vector_write_en,
    input logic [SCALAR_DATA_WIDTH-1:0] scalar_write_data,
    input logic [CACHE_LINE_WIDTH-1:0] vector_write_data,

    // memory request
    input logic       mem_ready,
    input logic [CACHE_LINE_WIDTH-1:0] mem_read_data,
    output logic      mem_read_en,
    output logic      mem_write_en,
    output logic [CACHE_LINE_WIDTH-1:0] mem_write_data,
    output logic [ADDRESS_SIZE - 1:0] mem_addr,

    // output to the processor
    output logic [SCALAR_DATA_WIDTH - 1 : 0] scalar_read_data,
    output logic [CACHE_LINE_WIDTH - 1 : 0] vector_read_data,
    output logic cache_ready  // if cache is not ready to read data to processor, must stall
);
    localparam OFFSET_WIDTH = $clog2(CACHE_LINE_WIDTH/8);
    localparam INDEX_WIDTH = $clog2(CACHE_LINES);
    localparam TAG_WIDTH = ADDRESS_SIZE - INDEX_WIDTH - 6;

    // cache declaration

    logic valid [0 : CACHE_LINES - 1];
    logic [7:0] data [0 : CACHE_LINES - 1][0 : CACHE_LINE_WIDTH / 8 - 1];
    logic [TAG_WIDTH - 1 : 0] tags [0 : CACHE_LINES - 1];

    // break up address to tag | index | offset

    function automatic logic [TAG_WIDTH - 1 : 0] get_tag(input logic [ADDRESS_SIZE - 1 : 0] addr);
        return addr[ADDRESS_SIZE - 1 : INDEX_WIDTH + OFFSET_WIDTH];
    endfunction

    function automatic logic [INDEX_WIDTH - 1 : 0] get_index(input logic [ADDRESS_SIZE - 1 : 0] addr);
        return addr[INDEX_WIDTH + OFFSET_WIDTH - 1 : OFFSET_WIDTH]
    endfunction

    function automatic logic [OFFSET_WIDTH - 1 : 0] get_offset(input logic [ADDRESS_SIZE - 1 : 0] addr);
        return addr[OFFSET_WIDTH - 1];
    endfunction

    logic [ADDRESS_SIZE - 1 : 0] address = (scalar_vector_control) ? vector_addr : scalar_addr;
    logic [TAG_WIDTH - 1 : 0] tag = get_tag(address);
    logic [INDEX_WIDTH - 1 : 0] index = get_index(address);
    logic [OFFSET_WIDTH - 1 : 0] offset = get_offset(address);

    typedef enum {
        read,
        write,
        non_memory
    } instruction_type;
    
    logic [ADDRESS_SIZE - 1 : 0] prev_mem_addr;
    instruction_type prev_instruction_type;
    instruction_type curr_instruction_type;

    assign curr_instruction_type = (scalar_read_en || vector_read_en)
    ? read : (scalar_write_en || vector_write_en)
    ? write : non_memory;

    // memory request and cache reset
    always_ff@(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < CACHE_LINES; i++) {
                valid[i] = '0;
            }
            prev_mem_addr <= '0;
            prev_instruction_type <= non_memory;
        end

        prev_mem_addr <= mem_addr;
        prev_instruction_type <= curr_instruction_type;   
    end

    assign mem_addr = scalar_vector_control ? vector_addr : scalar_addr;
    
    // write
    always_comb begin
        mem_write_en = scalar_write_en || vector_write_en;
        
        for (int i = 0; i < CACHE_LINE_WIDTH / 8; i++) begin
            data[index][i] = '0;
        end
        if (mem_write_en) begin
            if (scalar_vector_control) begin
                for (int i = 0; i < CACHE_LINE_WIDTH / 8; i++) begin
                    data[index][i] = vector_write_data[i*8 +: 8];
                end
                write_data = vector_write_data;
            end
            else begin
                // need to add checks for wraparound/out of bounds behavior
                for (int i = 0; i < SCALAR_DATA_WIDTH / 8; i++) begin
                    data[index][offset + i] = scalar_write_data[i*8 +: 8];
                end
                write_data = scalar_write_data;
            end
            tags[index] = tag;
        end

    end

    // read - cycle 1 : send request to memory and check for cache hit
    // read - cycle 2 : process request sent in previous clock cycle
    // if we read after read and hit cache while getting previous clock cycle, return previous clock
    // need to extend pipeline to 6 stage with cache.
    always_comb begin
        mem_read_en = scalar_read_en || vector_read_en; 
        vector_read_data = '0;
        scalar_read_data = '0;
        cache_ready = '0;

        if (mem_ready && prev_instruction_type == read) begin
            if (scalar_vector_control) begin
                vector_read_data = mem_read_data;
            end
            else begin
                scalar_read_data = mem_read_data[8 * offset +: 8];
            end
            cache_ready = '1;

            // store to cache
            logic [TAG_WIDTH - 1 : 0] prev_tag = get_tag(prev_mem_addr);
            logic [INDEX_WIDTH - 1 : 0] prev_index = get_index(prev_mem_addr);
            logic [OFFSET_WIDTH - 1 : 0] prev_offset = get_offset(prev_mem_addr);

            tags[prev_index] = prev_tag;
            if (scalar_vector_control) begin
                for (int i = 0; i < CACHE_LINE_WIDTH / 8; i++) begin
                    data[prev_index][i] = mem_read_data[i*8 +: 8];
                end
            end
            else begin
                // need to add checks for wraparound/out of bounds behavior
                for (int i = 0; i < SCALAR_DATA_WIDTH / 8; i++) begin
                    data[prev_index][prev_offset + i] = mem_read_data[i*8 +: 8];
                end
            end

        end
        else if (tags[index] == tag && valid[index]) begin
            if (scalar_vector_control) begin
                for (int i = 0; i < CACHE_LINE_WIDTH / 8; i++) begin
                    vector_read_data[i*8 +: 8] = data[index][i];
                end
            end
            else begin
                for (int i = 0; i < SCALAR_DATA_WIDTH / 8; i++) begin
                    scalar_read_data[i*8 +: 8] = data[index][offset + i];
                end
            end
            cache_ready = '1;

        end
    end
endmodule