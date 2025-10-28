`include "./rvv_defs.sv"

module rvv_vector_decoder(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] instr,
    
    output valu_mode_t  valu_mode,
    output vtype_t      vtype,
    output valu_opcode_t opcode,
    output logic [4:0]  vd,
    output logic [4:0]  vs1,
    output logic [4:0]  vs2,
    output logic [4:0]  vs3,
    output logic [4:0]  imm5,
    output logic        vm,
    output logic        mem_load,
    output logic        mem_store
);
    localparam VLEN = 512; // Vector length
    // Helper functions for field extraction
    function automatic logic [6:0] get_opcode(input logic [31:0] instr);
        return instr[6:0];
    endfunction
    function automatic logic [2:0] get_funct3(input logic [31:0] instr);
        return instr[14:12];
    endfunction
    function automatic logic [5:0] get_funct6(input logic [31:0] instr);
        return instr[31:26];
    endfunction
    function automatic logic [4:0] get_vd(input logic [31:0] instr);
        return instr[11:7];
    endfunction
    function automatic logic [4:0] get_vs1(input logic [31:0] instr);
        return instr[19:15];
    endfunction
    function automatic logic [4:0] get_vs2(input logic [31:0] instr);
        return instr[24:20];
    endfunction
    function automatic logic [4:0] get_vs3(input logic [31:0] instr);
        return instr[11:7];
    endfunction
    function automatic logic get_vm(input logic [31:0] instr);
        return instr[25];
    endfunction
    function automatic logic [4:0] get_imm5(input logic [31:0] instr);
        return instr[19:15];
    endfunction
    function automatic logic [9:0] get_vtype(input logic [31:0] instr);
        return instr[29:20];
    endfunction

    // valu_mode decoder
    function automatic valu_mode_t decode_valu_mode(
        input logic [6:0] opcode,
        input logic [2:0] funct3
    );
        valu_mode_t mode;
        case (opcode)
            7'b1010111: begin // Vector instructions
                case (funct3)
                    3'b000: begin
                        mode = VV_OP;
                    end
                    3'b100: begin
                        mode = VS_OP;
                    end
                    3'b011: begin
                        mode = VI_OP;
                    end
                    default: begin
                        mode = VV_OP;
                    end
                endcase
            end
            default: mode = VV_OP;
        endcase
        return mode;
    endfunction

    // vtype decoder
    function automatic logic [31:0] decode_vl(input logic [31:0] instr);
        // For simplicity, just return a fixed vl for now
        return 32'd8; // Example fixed vl
    endfunction

    function automatic vtype_t decode_vtype(input logic [9:0] vtype_bits);
        vtype_t vtype;
        vtype.vill  = vtype_bits[9];
        vtype.vma   = vtype_bits[8];
        vtype.vta   = vtype_bits[7];
        vtype.vsew  = vsew_t'(vtype_bits[5:3]);
        vtype.vlmul = vlmul_t'(vtype_bits[2:0]);
        return vtype;
    endfunction

    // Full funct6 mapping for integer vector operations
    function automatic valu_opcode_t decode_valu_opcode(
        input logic [5:0] funct6,
        input logic [2:0] funct3
    );
        case (funct6)
            6'b000000: return VADD;
            6'b000010: return VSUB;
            6'b000011: return VRSUB;
            6'b100000: if (funct3 == 3'b011) return VMSLEU; else return VMUL;
            6'b100001: if (funct3 == 3'b011) return VMSLE;  else return VMULH;
            6'b100010: if (funct3 == 3'b011) return VMSGTU; else return VMULHSU;
            6'b100011: if (funct3 == 3'b011) return VMSGT;  else return VMULHU;
            6'b100100: return VDIVU;
            6'b100101: if (funct3 == 3'b100) return VAND;   else return VDIV;
            6'b100110: if (funct3 == 3'b100) return VOR;    else return VREMU;
            6'b100111: if (funct3 == 3'b100) return VXOR;   else return VREM;
            6'b101011: return VSLL;
            6'b101101: return VSRL;
            6'b101111: return VSRA;
            6'b011000: return VMINU;
            6'b011001: return VMIN;
            6'b011010: return VMAXU;
            6'b011011: return VMAX;
            6'b011100: return VMSEQ;
            6'b011101: return VMSNE;
            6'b011110: return VMSLTU;
            6'b011111: return VMSLT;
            // Merge/Move/Sign/Zero extension/Not (VI only)
            /*
            6'b010111: return VMERGE;
            6'b010000: return VMV;
            6'b010100: return VSEXT;
            6'b010101: return VZEXT;
            6'b011110: return VNOT;
            */
            default:   return VUNIMPL;
        endcase
    endfunction

    // Internal vtype register
    vtype_t vtype_reg;
    logic [31:0] vl;

    // Detect vsetvli/vsetvl (opcode 7'b1010111, funct3 3'b111 for vsetvli, 3'b110 for vsetvl)
    // these instructions may need to be moved to execution stage based on user need. 
    wire is_vsetvli = (get_opcode(instr) == 7'b1010111) && (get_funct3(instr) == 3'b111);
    wire is_vsetvl  = (get_opcode(instr) == 7'b1010111) && (get_funct3(instr) == 3'b110);

    // vtype register update logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vtype_reg <= '0;
        end else if (is_vsetvli || is_vsetvl) begin
            vtype_t new_vtype = decode_vtype(get_vtype(instr));
            $display("update vtype_reg: vill: %d, vma: %d, vta: %d, vsew: %d, vlmul: %d",
                     new_vtype.vill, new_vtype.vma, new_vtype.vta,
                     8 << new_vtype.vsew, new_vtype.vlmul);
            vtype_reg <= new_vtype;
            vl <= decode_vl(instr);
        end
    end

    // Main decode logic
    always_comb begin
        vd         = get_vd(instr);
        vs1        = get_vs1(instr);
        vs2        = get_vs2(instr);
        vs3        = get_vs3(instr);
        vm         = get_vm(instr);
        imm5       = get_imm5(instr);
        valu_mode  = decode_valu_mode(get_opcode(instr), get_funct3(instr));
        opcode     = decode_valu_opcode(get_funct6(instr), get_funct3(instr));
        if (is_vsetvli || is_vsetvl)
            vtype = decode_vtype(get_vtype(instr));
        else
            vtype = vtype_reg;
        // vl is now an input, so do not assign it here
        mem_load   = (get_opcode(instr) == 7'b0000111); // vector load
        mem_store  = (get_opcode(instr) == 7'b0100111); // vector store
    end
endmodule
