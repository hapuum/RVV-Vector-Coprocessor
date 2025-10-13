#include "Vrvv_vector_system.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <cstdint>
#include <cstring>
#include <iomanip>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vrvv_vector_system* top = new Vrvv_vector_system;

    // Optional: Enable waveform tracing
    VerilatedVcdC* tfp = nullptr;
    #ifdef VM_TRACE
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open("wave.vcd");
    #endif

    // Reset
    top->rst = 1;
    top->alu_rst = 1; // NEW: ALU reset asserted
    top->clk = 0;
    top->instr = 0;
    top->vl = 8;
    for (int i = 0; i < 5; ++i) {
        top->clk = !top->clk;
        top->eval();
        if (tfp) tfp->dump(main_time++);
    }
    top->rst = 0;      // Release global reset
    top->alu_rst = 0;  // Release ALU reset

    // vsetvli
    top->instr = 0b0'000'01010001'00001'111'00010'1010111;
    for (int i = 0; i < 2; ++i) {
        top->clk = !top->clk;
        top->eval();
        if (tfp) tfp->dump(main_time++);
    }

    // Pulse ALU reset between instructions (if needed)
    top->alu_rst = 1;
    top->clk = !top->clk;
    top->eval();
    if (tfp) tfp->dump(main_time++);
    top->alu_rst = 0;

    // vadd.vi v2, v2, 2
    top->instr = 0b000000'1'00001'00010'011'00010'1010111;

    // Simulate a few cycles
    for (int i = 0; i < 100; ++i) {
        top->clk = !top->clk;
        top->eval();
        if (tfp) tfp->dump(main_time++);
        if (top->ready) {
            std::cout << "vreg_out = 0x";
            // Print from most significant word to least
            for (int j = 15; j >= 0; --j) {
                std::cout << std::hex << std::setfill('0') << std::setw(8)
                          << top->vreg_out[j] << " ";
            }
            std::cout << std::dec << std::endl;
            for (int k = 0; k < 4; ++k) {
                top->clk = !top->clk;
                top->eval();
                if (tfp) tfp->dump(main_time++);
            }
            break;
        }
    }

    // ALU reset between instructions
    top->alu_rst = 1;
    top->clk = !top->clk;
    top->eval();
    if (tfp) tfp->dump(main_time++);
    top->alu_rst = 0;

    // vse16.v
    top->instr = 0b010'0'00'1'00000'00100'101'00010'0100111; 
             //                sumop rs1 width vs3
             // rs1 : base address
             // vs3 : store data

    for (int i = 0; i < 100; ++i) {
        top->clk = !top->clk;
        top->eval();
        if (tfp) tfp->dump(main_time++);
        if (top->ready) {
            std::cout << "vse16.v complete" << std::endl;
            break;
        }
    }


    // ALU reset between instructions
    top->alu_rst = 1;
    top->clk = !top->clk;
    top->eval();
    if (tfp) tfp->dump(main_time++);
    top->alu_rst = 0;

    // Fourth instruction vle8.v
    top->instr = 0b01000010000000100000000000000111;
    for (int i = 0; i < 100; ++i) {
        top->clk = !top->clk;
        top->eval();
        if (tfp) tfp->dump(main_time++);
        if (top->ready) {
            std::cout << "vle8.v complete" << std::endl;
            break;
        }
    }

    // Finish
    if (tfp) {
        tfp->close();
        delete tfp;
    }
    top->final();
    delete top;
    return 0;
}