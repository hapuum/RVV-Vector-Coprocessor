`include "./rvv_defs.sv"
`timescale 1ns/1ps
//=============================================================
// RISC-V Vector Extension (RVV) 512-bit Vector function unit
//=============================================================

module rvv_vector_top #(
    parameter VLEN = 512,               // Vector register length in bits (512b)
    parameter ELEN = 64,                // Max element width in bits
    parameter MEM_SIZE_BYTES = 65536    // 64KB memory size
)(
    input  logic              clk,
    input  logic              rst,

    // Vector instruction inputs
    input  valu_mode_t        valu_mode,
    input  vtype_t            vtype,
    input  logic [31:0]       vl,
    input  valu_opcode_t      opcode,
    input  logic [VLEN-1:0]   vs1,
    input  logic [VLEN-1:0]   vs2,
    input  logic [VLEN-1:0]   vs3,
    input  logic [ELEN-1:0]   rs1,
    input  logic [4:0]        imm,
    input  logic [VLEN-1:0]   vmask,
    input  logic              vm,          // mask enable



    // Memory load/store control
    input  logic              mem_load,    // 1 = vector load
    input  logic              mem_store,   // 1 = vector store

    // Outputs
    output logic              vector_memcache_write_en,
    output logic              vector_memcache_read_en,
    output logic [ELEN-1:0]   vector_memcache_addr,
    output logic [VLEN-1:0]   vector_memcache_wdata,
    output logic [VLEN-1:0]   vreg_out,
    output logic              ready
);

    // Vector ALU function (element-wise)
    function automatic logic [ELEN-1:0] vector_alu(
        input valu_opcode_t opcode,
        input logic [ELEN-1:0] op1,
        input logic [ELEN-1:0] op2,
        input logic [4:0] imm,
        input logic is_signed,
        input int unsigned SEW
    );
        
        logic [ELEN-1:0] result;
        // Only operate on lower SEW bits of op1/op2
        logic [511:0] op1_sew, op2_sew;
        // Dynamically select the correct slice based on SEW
        case (SEW)
            8: begin
                op1_sew = op1[7:0];
                op2_sew = op2[7:0];
            end
            16: begin
                op1_sew = op1[15:0];
                op2_sew = op2[15:0];
            end
            32: begin
                op1_sew = op1[31:0];
                op2_sew = op2[31:0];
            end
            64: begin
                op1_sew = op1[63:0];
                op2_sew = op2[63:0];
            end
            128: begin
                op1_sew = op1[127:0];
                op2_sew = op2[127:0];
            end
            256: begin
                op1_sew = op1[255:0];
                op2_sew = op2[255:0];
            end
            512: begin
                op1_sew = op1[511:0];
                op2_sew = op2[511:0];
            end
            default: begin
                op1_sew = '0;
                op2_sew = '0;
            end
        endcase
        case (opcode)
            VADD:    result = op1_sew + op2_sew;
            VSUB:    result = op1_sew - op2_sew;
            VRSUB:   result = op2_sew - op1_sew;
            VMUL:    result = op1_sew * op2_sew;
            VMULH:   result = ($signed(op1_sew) * $signed(op2_sew)) >>> SEW;
            VMULHU:  result = (op1_sew * op2_sew) >> SEW;
            VMULHSU: result = ($signed(op1_sew) * op2_sew) >>> SEW;
            VDIVU:   result = (op2_sew != 0) ? op1_sew / op2_sew : ~'0;
            VDIV:    result = (op2_sew != 0) ? $signed(op1_sew) / $signed(op2_sew) : ~'0;
            VREMU:   result = (op2_sew != 0) ? op1_sew % op2_sew : op1_sew;
            VREM:    result = (op2_sew != 0) ? $signed(op1_sew) % $signed(op2_sew) : op1_sew;
            VAND:    result = op1_sew & op2_sew;
            VOR:     result = op1_sew | op2_sew;
            VXOR:    result = op1_sew ^ op2_sew;
            VSLL: begin
                case (SEW)
                    8:  result = op1_sew << op2_sew[2:0];
                    16: result = op1_sew << op2_sew[3:0];
                    32: result = op1_sew << op2_sew[4:0];
                    64: result = op1_sew << op2_sew[5:0];
                    default: result = '0;
                endcase
            end
            VSRL: begin
                case (SEW)
                    8:  result = op1_sew >> op2_sew[2:0];
                    16: result = op1_sew >> op2_sew[3:0];
                    32: result = op1_sew >> op2_sew[4:0];
                    64: result = op1_sew >> op2_sew[5:0];
                    default: result = '0;
                endcase
            end
            VSRA: begin
                case (SEW)
                    8:  result = $signed(op1_sew) >>> op2_sew[2:0];
                    16: result = $signed(op1_sew) >>> op2_sew[3:0];
                    32: result = $signed(op1_sew) >>> op2_sew[4:0];
                    64: result = $signed(op1_sew) >>> op2_sew[5:0];
                    default: result = '0;
                endcase
            end
            VMSEQ:   result = (op1_sew == op2_sew);
            VMSNE:   result = (op1_sew != op2_sew);
            VMSLTU:  result = (op1_sew < op2_sew);
            VMSLT:   result = ($signed(op1_sew) < $signed(op2_sew));
            VMSLEU:  result = (op1_sew <= op2_sew);
            VMSLE:   result = ($signed(op1_sew) <= $signed(op2_sew));
            VMSGTU:  result = (op1_sew > op2_sew);
            VMSGT:   result = ($signed(op1_sew) > $signed(op2_sew));
            VMINU:   result = (op1_sew < op2_sew) ? op1_sew : op2_sew;
            VMIN:    result = ($signed(op1_sew) < $signed(op2_sew)) ? op1_sew : op2_sew;
            VMAXU:   result = (op1_sew > op2_sew) ? op1_sew : op2_sew;
            VMAX:    result = ($signed(op1_sew) > $signed(op2_sew)) ? op1_sew : op2_sew;
            VMERGE:  result = op2_sew;
            VMV:     result = op1_sew;
            VSEXT: begin
                case (imm)
                    1:  result = $signed(op1[0:0]);
                    2:  result = $signed(op1[1:0]);
                    3:  result = $signed(op1[2:0]);
                    4:  result = $signed(op1[3:0]);
                    5:  result = $signed(op1[4:0]);
                    6:  result = $signed(op1[5:0]);
                    7:  result = $signed(op1[6:0]);
                    8:  result = $signed(op1[7:0]);
                    16: result = $signed(op1[15:0]);
                    32: result = $signed(op1[31:0]);
                    64: result = $signed(op1[63:0]);
                    default: result = '0;
                endcase
            end
            VZEXT: begin
                case (imm)
                    1:  result = op1[0:0];
                    2:  result = op1[1:0];
                    3:  result = op1[2:0];
                    4:  result = op1[3:0];
                    5:  result = op1[4:0];
                    6:  result = op1[5:0];
                    7:  result = op1[6:0];
                    8:  result = op1[7:0];
                    16: result = op1[15:0];
                    32: result = op1[31:0];
                    64: result = op1[63:0];
                    default: result = '0;
                endcase
            end
            VNOT:    result = ~op1_sew;
            default: result = '0;
        endcase
        return result;
    endfunction

    // VV operation function
    function automatic logic [VLEN-1:0] vv_operations(
        input vtype_t vtype,
        input logic [31:0] vl,
        input logic [VLEN-1:0] vs1,
        input logic [VLEN-1:0] vs2,
        input logic [VLEN-1:0] vmask,
        input logic vm,
        input valu_opcode_t opcode
    );
        int unsigned SEW = 8 << vtype.vsew;
        logic [VLEN-1:0] result = '0;
        logic is_signed = ~vtype.vma;
        case (SEW)
            8: begin
                for (int i = 0; i < VLEN/8; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [7:0] elem1 = vs1[i*8 +: 8];
                    logic [7:0] elem2 = vs2[i*8 +: 8];
                    logic [7:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 8);
                        elem_result = tmp_result[7:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*8 +: 8] = elem_result;
                end
            end
            16: begin
                for (int i = 0; i < VLEN/16; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [15:0] elem1 = vs1[i*16 +: 16];
                    logic [15:0] elem2 = vs2[i*16 +: 16];
                    logic [15:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 16);
                        elem_result = tmp_result[15:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*16 +: 16] = elem_result;
                end
            end
            32: begin
                for (int i = 0; i < VLEN/32; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [31:0] elem1 = vs1[i*32 +: 32];
                    logic [31:0] elem2 = vs2[i*32 +: 32];
                    logic [31:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 32);
                        elem_result = tmp_result[31:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*32 +: 32] = elem_result;
                end
            end
            64: begin
                for (int i = 0; i < VLEN/64; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [63:0] elem1 = vs1[i*64 +: 64];
                    logic [63:0] elem2 = vs2[i*64 +: 64];
                    logic [63:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 64);
                        elem_result = tmp_result[63:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*64 +: 64] = elem_result;
                end
            end
            128: begin
                for (int i = 0; i < VLEN/128; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [127:0] elem1 = vs1[i*128 +: 128];
                    logic [127:0] elem2 = vs2[i*128 +: 128];
                    logic [127:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 128);
                        elem_result = tmp_result[127:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*128 +: 128] = elem_result;
                end
            end
            256: begin
                for (int i = 0; i < VLEN/256; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [255:0] elem1 = vs1[i*256 +: 256];
                    logic [255:0] elem2 = vs2[i*256 +: 256];
                    logic [255:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 256);
                        elem_result = tmp_result[255:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*256 +: 256] = elem_result;
                end
            end
            512: begin
                for (int i = 0; i < VLEN/512; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [511:0] elem1 = vs1[i*512 +: 512];
                    logic [511:0] elem2 = vs2[i*512 +: 512];
                    logic [511:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        tmp_result = vector_alu(opcode, elem1, elem2, 5'b0, is_signed, 512);
                        elem_result = tmp_result[511:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*512 +: 512] = elem_result;
                end
            end
            default: result = '0;
        endcase
        return result;
    endfunction

    // VS operation function
    function automatic logic [VLEN-1:0] vs_operations(
        input vtype_t vtype,
        input logic [31:0] vl,
        input logic [VLEN-1:0] vs1,
        input logic [ELEN-1:0] rs1,
        input logic [VLEN-1:0] vmask,
        input logic vm,
        input valu_opcode_t opcode
    );
        
        int unsigned SEW = 8 << vtype.vsew;
        logic [VLEN-1:0] result = '0;
        logic is_signed = ~vtype.vma;
        case (SEW)
            8: begin
                for (int i = 0; i < VLEN/8; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [7:0] elem1 = vs1[i*8 +: 8];
                    logic [7:0] scalar = rs1[7:0];
                    logic [7:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 8);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 8);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 8);
                        elem_result = tmp_result[7:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*8 +: 8] = elem_result;
                end
            end
            16: begin
                for (int i = 0; i < VLEN/16; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [15:0] elem1 = vs1[i*16 +: 16];
                    logic [15:0] scalar = rs1[15:0];
                    logic [15:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 16);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 16);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 16);
                        elem_result = tmp_result[15:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*16 +: 16] = elem_result;
                end
            end
            32: begin
                for (int i = 0; i < VLEN/32; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [31:0] elem1 = vs1[i*32 +: 32];
                    logic [31:0] scalar = rs1[31:0];
                    logic [31:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 32);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 32);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 32);
                        elem_result = tmp_result[31:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*32 +: 32] = elem_result;
                end
            end
            64: begin
                for (int i = 0; i < VLEN/64; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [63:0] elem1 = vs1[i*64 +: 64];
                    logic [63:0] scalar = rs1[63:0];
                    logic [63:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 64);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 64);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 64);
                        elem_result = tmp_result[63:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*64 +: 64] = elem_result;
                end
            end
            128: begin
                for (int i = 0; i < VLEN/128; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [127:0] elem1 = vs1[i*128 +: 128];
                    logic [127:0] scalar = rs1[127:0];
                    logic [127:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 128);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 128);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 128);
                        elem_result = tmp_result[127:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*128 +: 128] = elem_result;
                end
            end
            256: begin
                for (int i = 0; i < VLEN/256; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [255:0] elem1 = vs1[i*256 +: 256];
                    logic [255:0] scalar = rs1[255:0];
                    logic [255:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 256);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 256);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 256);
                        elem_result = tmp_result[255:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*256 +: 256] = elem_result;
                end
            end
            512: begin
                for (int i = 0; i < VLEN/512; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [511:0] elem1 = vs1[i*512 +: 512];
                    logic [511:0] scalar = rs1[511:0];
                    logic [511:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 512);
                        else if (opcode == VRSUB)
                            tmp_result = vector_alu(opcode, scalar, elem1, 5'b0, is_signed, 512);
                        else
                            tmp_result = vector_alu(opcode, elem1, scalar, 5'b0, is_signed, 512);
                        elem_result = tmp_result[511:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*512 +: 512] = elem_result;
                end
            end
            default: result = '0;
        endcase
        return result;
    endfunction

    // VI operation function
    function automatic logic [VLEN-1:0] vi_operations(
        input vtype_t vtype,
        input logic [31:0] vl,
        input logic [VLEN-1:0] vs1,
        input logic [4:0] imm,
        input logic [VLEN-1:0] vmask,
        input logic vm,
        input valu_opcode_t opcode
    );
        int unsigned SEW = 8 << vtype.vsew;
        logic [VLEN-1:0] result = '0;
        logic is_signed = ~vtype.vma;
        case (SEW)
            8: begin
                for (int i = 0; i < VLEN/8; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [7:0] elem1 = vs1[i*8 +: 8];
                    logic [7:0] immediate = {{3{imm[4]}}, imm};
                    logic [7:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 8);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 8);
                        elem_result = tmp_result[7:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*8 +: 8] = elem_result;
                end
            end
            16: begin
                for (int i = 0; i < VLEN/16; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [15:0] elem1 = vs1[i*16 +: 16];
                    logic [15:0] immediate = {{11{imm[4]}}, imm};
                    logic [15:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 16);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 16);
                        elem_result = tmp_result[15:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*16 +: 16] = elem_result;
                end
            end
            32: begin
                for (int i = 0; i < VLEN/32; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [31:0] elem1 = vs1[i*32 +: 32];
                    logic [31:0] immediate = {{27{imm[4]}}, imm};
                    logic [31:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 32);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 32);
                        elem_result = tmp_result[31:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*32 +: 32] = elem_result;
                end
            end
            64: begin
                for (int i = 0; i < VLEN/64; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [63:0] elem1 = vs1[i*64 +: 64];
                    logic [63:0] immediate = {{59{imm[4]}}, imm};
                    logic [63:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 64);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 64);
                        elem_result = tmp_result[63:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*64 +: 64] = elem_result;
                end
            end
            128: begin
                for (int i = 0; i < VLEN/128; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [127:0] elem1 = vs1[i*128 +: 128];
                    logic [127:0] immediate = {{121{imm[4]}}, imm};
                    logic [127:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 128);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 128);
                        elem_result = tmp_result[127:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*128 +: 128] = elem_result;
                end
            end
            256: begin
                for (int i = 0; i < VLEN/256; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [255:0] elem1 = vs1[i*256 +: 256];
                    logic [255:0] immediate = {{251{imm[4]}}, imm};
                    logic [255:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 256);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 256);
                        elem_result = tmp_result[255:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*256 +: 256] = elem_result;
                end
            end
            512: begin
                for (int i = 0; i < VLEN/512; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    logic [511:0] elem1 = vs1[i*512 +: 512];
                    logic [511:0] immediate = {{507{imm[4]}}, imm};
                    logic [511:0] elem_result;
                    logic [ELEN-1:0] tmp_result;
                    if (active) begin
                        if (opcode == VMSGTU || opcode == VMSGT)
                            tmp_result = vector_alu(opcode, immediate, elem1, imm, is_signed, 512);
                        else
                            tmp_result = vector_alu(opcode, elem1, immediate, imm, is_signed, 512);
                        elem_result = tmp_result[511:0];
                    end else elem_result = vtype.vta ? 'x : elem1;
                    result[i*512 +: 512] = elem_result;
                end
            end
            default: begin
                result = '0;
            end
        endcase
        return result;
    endfunction

    // Main ALU wrapper function
    function automatic logic [VLEN-1:0] alu_operations(
        input valu_mode_t valu_mode,
        input vtype_t vtype,
        input logic [31:0] vl,
        input logic [VLEN-1:0] vs1,
        input logic [VLEN-1:0] vs2,
        input logic [ELEN-1:0] rs1,
        input logic [4:0] imm,
        input logic [VLEN-1:0] vmask,
        input logic vm,
        input valu_opcode_t opcode
    );
        logic [VLEN-1:0] result;
        $display("alu_operations start: valu_mode=%0h, vtype=%0h, vl=%0d, vs1=%0h, vs2=%0h, rs1=%0h, imm=%0h, vmask=%0h, vm=%0b, opcode=%0h", valu_mode, vtype, vl, vs1, vs2, rs1, imm, vmask, vm, opcode);
        case (valu_mode)
            VV_OP: result = vv_operations(vtype, vl, vs1, vs2, vmask, vm, opcode);
            VS_OP: result = vs_operations(vtype, vl, vs1, rs1, vmask, vm, opcode);
            VI_OP: result = vi_operations(vtype, vl, vs2, imm, vmask, vm, opcode);
            default: result = '0;
        endcase
        //$display("alu_operations result: %0h", result);
        return result;


    endfunction

    // // --------------------------------------------------------
    // // Memory Subsystem: 512-bit Vector Memory
    // // --------------------------------------------------------
    // // TEST PURPOSE ONLY. In a real implementation, memory signals would be connected to a data cache, instead of
    // // internal memory doing operations.
    // // Internal memory: array of 512-bit words (64 bytes)
    // localparam MEM_WORDS = MEM_SIZE_BYTES / (VLEN/8);
    // typedef logic [VLEN-1:0] mem_word_t;
    // mem_word_t mem_array [0:MEM_WORDS-1];

    // // Memory request signals
    // mem_req_t mem_req;

    // // Ready signal for memory operation
    // logic mem_ready;

    // // Temporary register for memory read data
    // vreg_t mem_read_data;

    // // Instantiate AGU
    // logic [63:0] addresses [0:VLEN/64-1];

    // agu agu_inst (
    //     .req(mem_req),
    //     .addresses(addresses)
    // );

    // // Memory read/write logic
    // // Function for unit stride memory load
    // function automatic vreg_t unit_stride_load(
    //     input logic [63:0] base_addr
    // );
    //     int word_idx = base_addr[($clog2(MEM_WORDS)+2)-1:3];
    //     $display("[LOAD]  addr=0x%0h data=0x%0h", base_addr, mem_array[word_idx]);
    //     return mem_array[word_idx];
    // endfunction

    // // Task for unit stride memory store
    // task automatic unit_stride_store(
    //     input logic [63:0] base_addr,
    //     input vreg_t data_in
    // );
    //     int word_idx = base_addr[($clog2(MEM_WORDS)+2)-1:3];
    //     mem_array[word_idx] <= data_in;
    //     $display("[STORE] addr=0x%0h data=0x%0h", base_addr, data_in);
    // endtask

    // // Memory read/write logic
    // always_ff @(posedge clk or posedge rst) begin
    //     if (rst) begin
    //         mem_ready <= 0;
    //         mem_read_data <= '0;
    //     end else begin
    //         mem_ready <= 0;
    //         if (mem_load) begin
    //             mem_read_data <= unit_stride_load(mem_req.base_addr);
    //             mem_ready <= 1;
    //         end else if (mem_store) begin
    //             //$display("Store operation: base_addr = %0h, data = %0h", mem_req.base_addr, vs3); // 
    //             //unit_stride_store(mem_req.base_addr, vs1);
    //             unit_stride_store(mem_req.base_addr, vs3);
    //             mem_ready <= 1;
    //         end else begin
    //             mem_ready <= 1; // No memory operation, ready immediately
    //         end
    //     end
    // end

    // // --------------------------------------------------------
    // // Control Logic: Integrate ALU and Memory Operations
    // // --------------------------------------------------------

    // // Prepare memory request for unit stride accesses
    // always_comb begin
    //     mem_req.access_type = UNIT_STRIDE;
    //     mem_req.base_addr = rs1;
    //     mem_req.stride = 64; // 64 bytes per 512-bit element
    //     mem_req.indices = '0;
    // end

    // Output register and ready signal
    logic [VLEN-1:0] alu_result;
    logic internal_ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vreg_out <= '0;
            ready <= 0;
        end else begin
            ready <= 0;
            vreg_out <= 0;
            if (mem_load) begin
                if (mem_ready) begin
                    // ADD MEMORY REQUEST TO CACHE
                    vector_memcache_read_en <= '1;
                    vector_memcache_addr <= '0;
                    ready <= 1;
                end
            end else if (mem_store) begin
                if (mem_ready) begin
                    // ADD MEMORY REQUEST TO CACHE
                    vector_memcache_write_en <= '1;
                    vector_memcache_wdata <= '0; // @TODO: add combinational logic to determine wdata / addr
                    vector_memcache_addr <= '0;
                    ready <= 1;
                end
            end else begin
                // ALU operations
                vreg_out <= alu_operations(valu_mode, vtype, vl, vs1, vs2, rs1, imm, vmask, vm, opcode);
                ready <= 1;
            end
        end
    end

    logic [ADDRESS_SIZE - 1 : 0] memory_op_addr;
    logic [VLEN - 1 : 0] memory_wdata;

    always_comb begin
        
    end


    // --------------------------------------------------------
    // Mask and Tail Policy Application Function
    // --------------------------------------------------------
    function automatic logic [VLEN-1:0] apply_mask_tail(
        input vtype_t vtype,
        input logic [31:0] vl,
        input logic [VLEN-1:0] data_in,
        input logic [VLEN-1:0] vmask,
        input logic vm
    );
        int unsigned SEW = 8 << vtype.vsew;
        logic [VLEN-1:0] data_out = '0;
        // For each possible SEW, handle masking and tail policy
        case (SEW)
            8: begin
                for (int i = 0; i < VLEN/8; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    if (i >= vl || (!vm && !active)) begin
                        if (vtype.vta) begin
                            data_out[i*8 +: 8] = 'x;
                        end else if (vtype.vma) begin
                            data_out[i*8 +: 8] = data_in[i*8 +: 8];
                        end else begin
                            data_out[i*8 +: 8] = '0;
                        end
                    end else begin
                        data_out[i*8 +: 8] = data_in[i*8 +: 8];
                    end
                end
            end
            16: begin
                for (int i = 0; i < VLEN/16; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    if (i >= vl || (!vm && !active)) begin
                        if (vtype.vta) begin
                            data_out[i*16 +: 16] = 'x;
                        end else if (vtype.vma) begin
                            data_out[i*16 +: 16] = data_in[i*16 +: 16];
                        end else begin
                            data_out[i*16 +: 16] = '0;
                        end
                    end else begin
                        data_out[i*16 +: 16] = data_in[i*16 +: 16];
                    end
                end
            end
            32: begin
                for (int i = 0; i < VLEN/32; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    if (i >= vl || (!vm && !active)) begin
                        if (vtype.vta) begin
                            data_out[i*32 +: 32] = 'x;
                        end else if (vtype.vma) begin
                            data_out[i*32 +: 32] = data_in[i*32 +: 32];
                        end else begin
                            data_out[i*32 +: 32] = '0;
                        end
                    end else begin
                        data_out[i*32 +: 32] = data_in[i*32 +: 32];
                    end
                end
            end
            64: begin
                for (int i = 0; i < VLEN/64; i++) begin
                    logic active = (i < vl) && (vm ? 1'b1 : vmask[i]);
                    if (i >= vl || (!vm && !active)) begin
                        if (vtype.vta) begin
                            data_out[i*64 +: 64] = 'x;
                        end else if (vtype.vma) begin
                            data_out[i*64 +: 64] = data_in[i*64 +: 64];
                        end else begin
                            data_out[i*64 +: 64] = '0;
                        end
                    end else begin
                        data_out[i*64 +: 64] = data_in[i*64 +: 64];
                    end
                end
            end
            default: data_out = '0;
        endcase
        return data_out;
    endfunction
endmodule

