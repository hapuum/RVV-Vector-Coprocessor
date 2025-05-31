`ifndef RVV_DEFS_SV
`define RVV_DEFS_SV

// Parameter for adjustable vector length
parameter int VLEN = 512;

// Type and Opcode Definitions
typedef enum logic [2:0] {
    SEW_8  = 3'b000,  // 8-bit
    SEW_16 = 3'b001,  // 16-bit
    SEW_32 = 3'b010,  // 32-bit
    SEW_64 = 3'b011   // 64-bit
} vsew_t;

typedef enum logic [2:0] {
    LMUL_1   = 3'b000,
    LMUL_2   = 3'b001,
    LMUL_4   = 3'b010,
    LMUL_8   = 3'b011,
    LMUL_F8  = 3'b111 // Fractional LMUL (future support)
} vlmul_t;

typedef struct packed {
    logic        vill;    // Illegal configuration
    logic        vma;     // Mask agnostic
    logic        vta;     // Tail agnostic
    vsew_t       vsew;    // Element width
    vlmul_t      vlmul;   // Register grouping
} vtype_t;

typedef enum logic [6:0] {
    VADD      = 7'd0,
    VSUB      = 7'd1,
    VRSUB     = 7'd2,
    VMUL      = 7'd3,
    VMULH     = 7'd4,
    VMULHU    = 7'd5,
    VMULHSU   = 7'd6,
    VDIVU     = 7'd7,
    VDIV      = 7'd8,
    VREMU     = 7'd9,
    VREM      = 7'd10,
    VAND      = 7'd11,
    VOR       = 7'd12,
    VXOR      = 7'd13,
    VSLL      = 7'd14,
    VSRL      = 7'd15,
    VSRA      = 7'd16,
    VMSEQ     = 7'd17,
    VMSNE     = 7'd18,
    VMSLTU    = 7'd19,
    VMSLT     = 7'd20,
    VMSLEU    = 7'd21,
    VMSLE     = 7'd22,
    VMSGTU    = 7'd23,
    
    VMSGT     = 7'd24,
    VMINU     = 7'd25,
    VMIN      = 7'd26,
    VMAXU     = 7'd27,
    VMAX      = 7'd28,
    VMERGE    = 7'd29,
    VMV       = 7'd30,
    VSEXT     = 7'd31,
    VZEXT     = 7'd32,
    VNOT      = 7'd33,
    VUNIMPL   = 7'd127
} valu_opcode_t;

typedef enum logic [1:0] {
    VV_OP = 2'b00,
    VS_OP = 2'b01,
    VI_OP = 2'b10
} valu_mode_t;

typedef enum logic [1:0] {
    UNIT_STRIDE,
    STRIDED,
    INDEXED,
    SEGMENT
} mem_access_type_t;

typedef struct packed {
    mem_access_type_t access_type;
    logic [63:0] base_addr;
    logic [31:0] stride;
    logic [VLEN-1:0] indices; // Adjusted to use VLEN
} mem_req_t;

typedef logic [VLEN-1:0] vreg_t;

`endif
