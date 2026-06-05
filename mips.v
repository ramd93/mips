`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.05.2026 16:50:16
// Design Name: 
// Module Name: mips
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ============================================================================
// ULTIMATE 5-STAGE PIPELINED MIPS PROCESSOR (Simplified Mux Syntax)
// Handles: Structural Hazards, Data Hazards, Load-Use Hazards, Control Hazards, 
// AND Branch-Data Hazards (Stall + ID-Stage Forwarding)
// ============================================================================

// ----------------------------------------------------------------------------
// 1. FOUNDATION BLOCKS
// ----------------------------------------------------------------------------

module register_file(
    input clk, reset, reg_write,
    input [4:0] read_reg1, read_reg2, write_reg,
    input [31:0] write_data,
    output [31:0] read_data1, read_data2
);
    reg [31:0] registers [31:0];
    integer i;

    assign read_data1 = (read_reg1 == 0) ? 32'b0 : registers[read_reg1];
    assign read_data2 = (read_reg2 == 0) ? 32'b0 : registers[read_reg2];

    // Write on NEGEDGE to solve Structural Hazards (Writeback-to-Decode)
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) registers[i] <= 32'b0;
        end else if (reg_write && write_reg != 0) begin
            registers[write_reg] <= write_data;
        end
    end
endmodule

module alu(
    input [31:0] a, b,
    input [3:0] alu_control,
    output reg [31:0] result
);
    always @(*) begin
        case(alu_control)
            4'b0000: result = a & b; // AND
            4'b0001: result = a | b; // OR
            4'b0010: result = a + b; // ADD
            4'b0110: result = a - b; // SUB
            4'b0111: result = (a < b) ? 32'd1 : 32'd0; // SLT
            default: result = 32'b0;
        endcase
    end
endmodule

module instruction_memory(
    input [31:0] pc, output [31:0] instruction
);
    reg [31:0] rom [0:255];
    initial $readmemh("machine_code.mem", rom);
    assign instruction = rom[pc[9:2]]; // Word aligned
endmodule

module data_memory(
    input clk, mem_read, mem_write,
    input [31:0] address, write_data,
    output [31:0] read_data
);
    reg [31:0] ram [0:255];
    assign read_data = (mem_read) ? ram[address[9:2]] : 32'b0;
    always @(posedge clk) begin
        if (mem_write) ram[address[9:2]] <= write_data;
    end
endmodule

// ----------------------------------------------------------------------------
// 2. CONTROL & HAZARD UNITS
// ----------------------------------------------------------------------------

module main_control(
    input [5:0] opcode,
    output reg reg_dst, alu_src, mem_to_reg, reg_write, mem_read, mem_write, branch,
    output reg [1:0] alu_op
);
    always @(*) begin
        reg_dst = 0; alu_src = 0; mem_to_reg = 0; reg_write = 0; 
        mem_read = 0; mem_write = 0; branch = 0; alu_op = 2'b00;
        case(opcode)
            6'b000000: begin reg_dst=1; reg_write=1; alu_op=2'b10; end // R-Type
            6'b100011: begin alu_src=1; mem_to_reg=1; reg_write=1; mem_read=1; alu_op=2'b00; end // lw
            6'b101011: begin alu_src=1; mem_write=1; alu_op=2'b00; end // sw
            6'b000100: begin branch=1; alu_op=2'b01; end // beq
            6'b001000: begin alu_src=1; reg_write=1; alu_op=2'b00; end // addi
        endcase
    end
endmodule

module alu_control(
    input [1:0] alu_op, input [5:0] funct, output reg [3:0] alu_ctrl
);
    always @(*) begin
        case(alu_op)
            2'b00: alu_ctrl = 4'b0010; // lw/sw
            2'b01: alu_ctrl = 4'b0110; // beq
            2'b10: case(funct)         // R-Type
                6'b100000: alu_ctrl = 4'b0010; // add
                6'b100010: alu_ctrl = 4'b0110; // sub
                6'b100100: alu_ctrl = 4'b0000; // and
                6'b100101: alu_ctrl = 4'b0001; // or
                6'b101010: alu_ctrl = 4'b0111; // slt
                default: alu_ctrl = 4'b0000;
            endcase
            default: alu_ctrl = 4'b0000;
        endcase
    end
endmodule

module hazard_detection_unit(
    input branch,
    input [4:0] if_id_rs, if_id_rt,
    input id_ex_mem_read, id_ex_reg_write,
    input [4:0] id_ex_rt, id_ex_write_reg,
    input ex_mem_mem_read,
    input [4:0] ex_mem_write_reg,
    
    output reg pc_write, if_id_write, control_mux_sel
);
    always @(*) begin
        // 1. Standard Load-Use Hazard
        if (id_ex_mem_read && ((id_ex_rt == if_id_rs) || (id_ex_rt == if_id_rt))) begin
            pc_write = 0; if_id_write = 0; control_mux_sel = 0;
        end
        // 2. Branch-Data Hazard (ALU)
        else if (branch && id_ex_reg_write && id_ex_write_reg != 0 && ((id_ex_write_reg == if_id_rs) || (id_ex_write_reg == if_id_rt))) begin
            pc_write = 0; if_id_write = 0; control_mux_sel = 0;
        end
        // 3. Branch-Data Hazard (Load)
        else if (branch && ex_mem_mem_read && ex_mem_write_reg != 0 && ((ex_mem_write_reg == if_id_rs) || (ex_mem_write_reg == if_id_rt))) begin
            pc_write = 0; if_id_write = 0; control_mux_sel = 0;
        end
        // No Hazards
        else begin
            pc_write = 1; if_id_write = 1; control_mux_sel = 1;
        end
    end
endmodule

// EX Stage Forwarding Unit
module forwarding_unit(
    input [4:0] id_ex_rs, id_ex_rt, ex_mem_rd, mem_wb_rd,
    input ex_mem_reg_write, mem_wb_reg_write,
    output reg [1:0] forward_a, forward_b
);
    always @(*) begin
        forward_a = 2'b00; forward_b = 2'b00;
        // EX Hazard
        if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs)) forward_a = 2'b10;
        if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rt)) forward_b = 2'b10;
        // MEM Hazard (Double Hazard protected)
        if (mem_wb_reg_write && (mem_wb_rd != 0) && !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs)) && (mem_wb_rd == id_ex_rs)) forward_a = 2'b01;
        if (mem_wb_reg_write && (mem_wb_rd != 0) && !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rt)) && (mem_wb_rd == id_ex_rt)) forward_b = 2'b01;
    end
endmodule

// ID Stage Forwarding Unit
module id_forwarding_unit(
    input [4:0] rs, rt,
    input [4:0] ex_mem_rd, mem_wb_rd,
    input ex_mem_reg_write, mem_wb_reg_write,
    output reg [1:0] forward_a_id, forward_b_id
);
    always @(*) begin
        forward_a_id = 2'b00; forward_b_id = 2'b00;
        if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == rs) forward_a_id = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == rs) forward_a_id = 2'b01;

        if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == rt) forward_b_id = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == rt) forward_b_id = 2'b01;
    end
endmodule

// Optimized ID-Stage Branch Hardware
module branch_hardware(
    input [31:0] pc_plus_4, sign_ext_imm, cmp_in_a, cmp_in_b,
    input branch_control,
    output [31:0] branch_target,
    output pc_src, if_flush
);
    assign branch_target = pc_plus_4 + (sign_ext_imm << 2);
    assign pc_src = branch_control & (cmp_in_a == cmp_in_b);
    assign if_flush = pc_src; 
endmodule

// ----------------------------------------------------------------------------
// 3. PIPELINE REGISTERS
// ----------------------------------------------------------------------------

module if_id_reg(
    input clk, reset, write_en, flush,
    input [31:0] pc_plus_4_in, inst_in,
    output reg [31:0] pc_plus_4_out, inst_out
);
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin pc_plus_4_out <= 0; inst_out <= 0; end 
        else if (write_en) begin pc_plus_4_out <= pc_plus_4_in; inst_out <= inst_in; end
    end
endmodule

module id_ex_reg(
    input clk, reset,
    input reg_write_in, mem_to_reg_in, mem_read_in, mem_write_in, reg_dst_in, alu_src_in,
    input [1:0] alu_op_in,
    input [31:0] pc_plus_4_in, rdata1_in, rdata2_in, sign_ext_in,
    input [4:0] rs_in, rt_in, rd_in,
    output reg reg_write_out, mem_to_reg_out, mem_read_out, mem_write_out, reg_dst_out, alu_src_out,
    output reg [1:0] alu_op_out,
    output reg [31:0] pc_plus_4_out, rdata1_out, rdata2_out, sign_ext_out,
    output reg [4:0] rs_out, rt_out, rd_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_write_out<=0; mem_to_reg_out<=0; mem_read_out<=0; mem_write_out<=0; 
            reg_dst_out<=0; alu_src_out<=0; alu_op_out<=0;
            pc_plus_4_out<=0; rdata1_out<=0; rdata2_out<=0; sign_ext_out<=0;
            rs_out<=0; rt_out<=0; rd_out<=0;
        end else begin
            reg_write_out<=reg_write_in; mem_to_reg_out<=mem_to_reg_in; mem_read_out<=mem_read_in; 
            mem_write_out<=mem_write_in; reg_dst_out<=reg_dst_in; alu_src_out<=alu_src_in; alu_op_out<=alu_op_in;
            pc_plus_4_out<=pc_plus_4_in; rdata1_out<=rdata1_in; rdata2_out<=rdata2_in; 
            sign_ext_out<=sign_ext_in; rs_out<=rs_in; rt_out<=rt_in; rd_out<=rd_in;
        end
    end
endmodule

module ex_mem_reg(
    input clk, reset,
    input reg_write_in, mem_to_reg_in, mem_read_in, mem_write_in,
    input [31:0] alu_result_in, write_data_in,
    input [4:0] dest_reg_in,
    output reg reg_write_out, mem_to_reg_out, mem_read_out, mem_write_out,
    output reg [31:0] alu_result_out, write_data_out,
    output reg [4:0] dest_reg_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_write_out<=0; mem_to_reg_out<=0; mem_read_out<=0; mem_write_out<=0;
            alu_result_out<=0; write_data_out<=0; dest_reg_out<=0;
        end else begin
            reg_write_out<=reg_write_in; mem_to_reg_out<=mem_to_reg_in; mem_read_out<=mem_read_in; mem_write_out<=mem_write_in;
            alu_result_out<=alu_result_in; write_data_out<=write_data_in; dest_reg_out<=dest_reg_in;
        end
    end
endmodule

module mem_wb_reg(
    input clk, reset,
    input reg_write_in, mem_to_reg_in,
    input [31:0] read_data_in, alu_result_in,
    input [4:0] dest_reg_in,
    output reg reg_write_out, mem_to_reg_out,
    output reg [31:0] read_data_out, alu_result_out,
    output reg [4:0] dest_reg_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_write_out<=0; mem_to_reg_out<=0;
            read_data_out<=0; alu_result_out<=0; dest_reg_out<=0;
        end else begin
            reg_write_out<=reg_write_in; mem_to_reg_out<=mem_to_reg_in;
            read_data_out<=read_data_in; alu_result_out<=alu_result_in; dest_reg_out<=dest_reg_in;
        end
    end
endmodule

// ----------------------------------------------------------------------------
// 4. THE MOTHERBOARD (TOP MODULE)
// ----------------------------------------------------------------------------

module mips_top(
    input clk,
    input reset
);

    // =======================================================
    // INTERNAL WIRES AND REGS
    // =======================================================
    wire [31:0] pc_current, pc_plus_4_if, pc_next, instruction_if;
    wire [31:0] pc_plus_4_id, instruction_id, sign_ext_id, read_data1_id, read_data2_id, branch_target_id;
    reg  [31:0] cmp_in_a, cmp_in_b; // Changed to reg for always block
    wire [5:0] opcode_id, funct_id;
    wire [4:0] rs_id, rt_id, rd_id;
    wire pc_write, if_id_write, control_mux_sel, pc_src_id, if_flush_id;
    wire branch_id, mem_read_id_raw, mem_write_id_raw, reg_dst_id_raw, alu_src_id_raw, mem_to_reg_id_raw, reg_write_id_raw;
    wire [1:0] alu_op_id_raw, forward_a_id, forward_b_id;
    wire branch_id_muxed, mem_read_id_muxed, mem_write_id_muxed, reg_dst_id_muxed, alu_src_id_muxed, mem_to_reg_id_muxed, reg_write_id_muxed;
    wire [1:0] alu_op_id_muxed;
    
    wire [31:0] pc_plus_4_ex, read_data1_ex, read_data2_ex, sign_ext_ex;
    wire [4:0] rs_ex, rt_ex, rd_ex, write_reg_ex;
    wire reg_write_ex, mem_to_reg_ex, mem_read_ex, mem_write_ex, reg_dst_ex, alu_src_ex;
    wire [1:0] alu_op_ex, forward_a, forward_b;
    wire [3:0] alu_control_ex;
    reg  [31:0] alu_in_a, alu_in_b_forwarded; // Changed to reg for always block
    wire [31:0] alu_in_b_final, alu_result_ex;
    
    wire reg_write_mem, mem_to_reg_mem, mem_read_mem, mem_write_mem;
    wire [31:0] alu_result_mem, write_data_mem, read_data_mem;
    wire [4:0] write_reg_mem;
    
    wire reg_write_wb, mem_to_reg_wb;
    wire [31:0] read_data_wb, alu_result_wb, write_data_wb;
    wire [4:0] write_reg_wb;

    // =======================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =======================================================
    assign pc_plus_4_if = pc_current + 32'd4;
    assign pc_next = (pc_src_id) ? branch_target_id : pc_plus_4_if;

    reg [31:0] pc_reg;
    assign pc_current = pc_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) pc_reg <= 32'b0;
        else if (pc_write) pc_reg <= pc_next;
    end

    instruction_memory imem (.pc(pc_current), .instruction(instruction_if));

    if_id_reg IF_ID (
        .clk(clk), .reset(reset), .write_en(if_id_write), .flush(if_flush_id),
        .pc_plus_4_in(pc_plus_4_if), .inst_in(instruction_if),
        .pc_plus_4_out(pc_plus_4_id), .inst_out(instruction_id)
    );

    // =======================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // =======================================================
    assign opcode_id = instruction_id[31:26];
    assign rs_id     = instruction_id[25:21];
    assign rt_id     = instruction_id[20:16];
    assign rd_id     = instruction_id[15:11];
    assign sign_ext_id = {{16{instruction_id[15]}}, instruction_id[15:0]};

    hazard_detection_unit hazard_unit (
        .branch(branch_id), .if_id_rs(rs_id), .if_id_rt(rt_id),
        .id_ex_mem_read(mem_read_ex), .id_ex_reg_write(reg_write_ex), .id_ex_rt(rt_ex), .id_ex_write_reg(write_reg_ex),
        .ex_mem_mem_read(mem_read_mem), .ex_mem_write_reg(write_reg_mem),
        .pc_write(pc_write), .if_id_write(if_id_write), .control_mux_sel(control_mux_sel)
    );

    main_control control_unit (
        .opcode(opcode_id), .reg_dst(reg_dst_id_raw), .alu_src(alu_src_id_raw), .mem_to_reg(mem_to_reg_id_raw),
        .reg_write(reg_write_id_raw), .mem_read(mem_read_id_raw), .mem_write(mem_write_id_raw),
        .branch(branch_id), .alu_op(alu_op_id_raw)
    );

    assign reg_write_id_muxed  = control_mux_sel ? reg_write_id_raw  : 1'b0;
    assign mem_to_reg_id_muxed = control_mux_sel ? mem_to_reg_id_raw : 1'b0;
    assign mem_read_id_muxed   = control_mux_sel ? mem_read_id_raw   : 1'b0;
    assign mem_write_id_muxed  = control_mux_sel ? mem_write_id_raw  : 1'b0;
    assign reg_dst_id_muxed    = control_mux_sel ? reg_dst_id_raw    : 1'b0;
    assign alu_src_id_muxed    = control_mux_sel ? alu_src_id_raw    : 1'b0;
    assign alu_op_id_muxed     = control_mux_sel ? alu_op_id_raw     : 2'b00;

    register_file reg_file (
        .clk(clk), .reset(reset), .reg_write(reg_write_wb),
        .read_reg1(rs_id), .read_reg2(rt_id), .write_reg(write_reg_wb), .write_data(write_data_wb),
        .read_data1(read_data1_id), .read_data2(read_data2_id)
    );

    id_forwarding_unit id_fwd (
        .rs(rs_id), .rt(rt_id), .ex_mem_rd(write_reg_mem), .mem_wb_rd(write_reg_wb),
        .ex_mem_reg_write(reg_write_mem), .mem_wb_reg_write(reg_write_wb),
        .forward_a_id(forward_a_id), .forward_b_id(forward_b_id)
    );

    // Cleaned up ID Stage Forwarding Muxes
    always @(*) begin
        case(forward_a_id)
            2'b10:   cmp_in_a = alu_result_mem;
            2'b01:   cmp_in_a = write_data_wb;
            default: cmp_in_a = read_data1_id;
        endcase

        case(forward_b_id)
            2'b10:   cmp_in_b = alu_result_mem;
            2'b01:   cmp_in_b = write_data_wb;
            default: cmp_in_b = read_data2_id;
        endcase
    end

    branch_hardware branch_hw (
        .pc_plus_4(pc_plus_4_id), .sign_ext_imm(sign_ext_id),
        .cmp_in_a(cmp_in_a), .cmp_in_b(cmp_in_b), .branch_control(branch_id),
        .branch_target(branch_target_id), .pc_src(pc_src_id), .if_flush(if_flush_id)
    );

    id_ex_reg ID_EX (
        .clk(clk), .reset(reset),
        .reg_write_in(reg_write_id_muxed), .mem_to_reg_in(mem_to_reg_id_muxed), .mem_read_in(mem_read_id_muxed),
        .mem_write_in(mem_write_id_muxed), .reg_dst_in(reg_dst_id_muxed), .alu_src_in(alu_src_id_muxed), .alu_op_in(alu_op_id_muxed),
        .pc_plus_4_in(pc_plus_4_id), .rdata1_in(read_data1_id), .rdata2_in(read_data2_id), .sign_ext_in(sign_ext_id),
        .rs_in(rs_id), .rt_in(rt_id), .rd_in(rd_id),
        .reg_write_out(reg_write_ex), .mem_to_reg_out(mem_to_reg_ex), .mem_read_out(mem_read_ex),
        .mem_write_out(mem_write_ex), .reg_dst_out(reg_dst_ex), .alu_src_out(alu_src_ex), .alu_op_out(alu_op_ex),
        .pc_plus_4_out(pc_plus_4_ex), .rdata1_out(read_data1_ex), .rdata2_out(read_data2_ex), .sign_ext_out(sign_ext_ex),
        .rs_out(rs_ex), .rt_out(rt_ex), .rd_out(rd_ex)
    );

    // =======================================================
    // STAGE 3: EXECUTE (EX)
    // =======================================================
    assign write_reg_ex = (reg_dst_ex) ? rd_ex : rt_ex;

    forwarding_unit fwd_unit (
        .id_ex_rs(rs_ex), .id_ex_rt(rt_ex), .ex_mem_rd(write_reg_mem), .mem_wb_rd(write_reg_wb),
        .ex_mem_reg_write(reg_write_mem), .mem_wb_reg_write(reg_write_wb),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    // Cleaned up EX Stage Forwarding Muxes
    always @(*) begin
        case(forward_a)
            2'b10:   alu_in_a = alu_result_mem;
            2'b01:   alu_in_a = write_data_wb;
            default: alu_in_a = read_data1_ex;
        endcase

        case(forward_b)
            2'b10:   alu_in_b_forwarded = alu_result_mem;
            2'b01:   alu_in_b_forwarded = write_data_wb;
            default: alu_in_b_forwarded = read_data2_ex;
        endcase
    end

    // ALU Src Mux (2-to-1)
    assign alu_in_b_final = (alu_src_ex) ? sign_ext_ex : alu_in_b_forwarded;

    alu_control alu_ctrl_unit (.alu_op(alu_op_ex), .funct(sign_ext_ex[5:0]), .alu_ctrl(alu_control_ex));
    alu main_alu (.a(alu_in_a), .b(alu_in_b_final), .alu_control(alu_control_ex), .result(alu_result_ex));

    ex_mem_reg EX_MEM (
        .clk(clk), .reset(reset),
        .reg_write_in(reg_write_ex), .mem_to_reg_in(mem_to_reg_ex), .mem_read_in(mem_read_ex), .mem_write_in(mem_write_ex),
        .alu_result_in(alu_result_ex), .write_data_in(alu_in_b_forwarded), .dest_reg_in(write_reg_ex),
        .reg_write_out(reg_write_mem), .mem_to_reg_out(mem_to_reg_mem), .mem_read_out(mem_read_mem), .mem_write_out(mem_write_mem),
        .alu_result_out(alu_result_mem), .write_data_out(write_data_mem), .dest_reg_out(write_reg_mem)
    );

    // =======================================================
    // STAGE 4: MEMORY (MEM)
    // =======================================================
    data_memory dmem (
        .clk(clk), .mem_read(mem_read_mem), .mem_write(mem_write_mem),
        .address(alu_result_mem), .write_data(write_data_mem), .read_data(read_data_mem)
    );

    mem_wb_reg MEM_WB (
        .clk(clk), .reset(reset),
        .reg_write_in(reg_write_mem), .mem_to_reg_in(mem_to_reg_mem),
        .read_data_in(read_data_mem), .alu_result_in(alu_result_mem), .dest_reg_in(write_reg_mem),
        .reg_write_out(reg_write_wb), .mem_to_reg_out(mem_to_reg_wb),
        .read_data_out(read_data_wb), .alu_result_out(alu_result_wb), .dest_reg_out(write_reg_wb)
    );

    // =======================================================
    // STAGE 5: WRITEBACK (WB)
    // =======================================================
    assign write_data_wb = (mem_to_reg_wb) ? read_data_wb : alu_result_wb;

endmodule
