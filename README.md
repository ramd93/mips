# mips
5-Stage Pipelined MIPS32 Processor

A fully functional, 5-stage pipelined MIPS32 processor implemented in Verilog. This project demonstrates advanced computer architecture concepts, including dynamic hazard resolution, data forwarding, and pipeline stalling. It is capable of executing load/store, arithmetic, and branch instructions.

Architecture Overview

The processor follows the classic 5-stage RISC pipeline design:
Instruction Fetch (IF): Fetches the next instruction from Instruction Memory.
Instruction Decode (ID): Decodes the instruction, reads the Register File, and evaluates branches early to minimize penalties.
Execute (EX): Performs arithmetic/logic operations and calculates memory addresses using the main ALU.
Memory (MEM): Reads from or writes to the Data Memory.
Write Back (WB): Writes the final result back into the Register File.

Key Features & Optimizations

Early Branch Resolution: Branch equality comparators are shifted to the Decode (ID) stage, reducing the branch penalty to a single clock cycle.

EX-Stage Forwarding: Resolves Read-After-Write (RAW) data hazards for arithmetic instructions by bypassing the register file.
ID-Stage Forwarding: A dedicated forwarding unit specifically designed to feed fresh data to the early branch comparator.
Dynamic Hazard Detection: Actively monitors for load-use data hazards and control hazards, automatically injecting pipeline stalls (bubbles) and flushing instructions when necessary.
