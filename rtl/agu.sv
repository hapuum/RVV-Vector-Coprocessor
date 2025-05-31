`include "./rvv_defs.sv"

module agu (
    input  mem_req_t req,
    output logic [63:0] addresses [0:VLEN/64-1]
);
    always_comb begin
        case(req.access_type)
            UNIT_STRIDE: begin
                foreach(addresses[i])
                    addresses[i] = req.base_addr + (i * 8); // 8 bytes per 64b element
            end
            // Strided and indexed address generation is deprecated/unsupported
            default: begin
                foreach(addresses[i])
                    addresses[i] = 64'b0;
            end
        endcase
    end
endmodule
