# Zynq-7000 Edge AI Vision: Hardware-Accelerated Sobel Pipeline

## Overview
This project implements a bare-metal hardware/software co-design for real-time edge detection on an ALINX AX7020 (Zynq XC7Z020) SoC. It streams image data from DDR memory to the FPGA fabric via AXI DMA, processes it through a custom VHDL Sobel convolution engine, and writes the output back to memory.

<img width="640" height="480" alt="Design sans titre" src="https://github.com/user-attachments/assets/7065ee91-337c-44ee-8842-112fcda68d22" />

This repository documents the transition from a standard software algorithm to a fully pipelined, cycle-accurate RTL hardware accelerator.

---

## System Architecture (Vivado Block Design)

> **<img width="1354" height="896" alt="BD" src="https://github.com/user-attachments/assets/9ba469a1-9e65-44ab-9710-440a40706b35" />**

The system is split across the Zynq Processing System (PS) and Programmable Logic (PL):
*   **The PS (ARM Cortex-A9):** Runs a C application via Linux `/dev/mem` (or bare-metal) to configure the AXI DMA registers and initiate the block memory transfer.
*   **The PL (Artix-7 Fabric):** Houses the Xilinx AXI DMA engine and the custom `sobel_axis` VHDL IP, connected via high-speed AXI4-Stream interfaces.

---

## Core Engineering Documentation

The complexity of this project lies in the VHDL memory architecture and handling physical hardware/timing constraints. I have broken down the engineering details into three main sections:

### 1. [The Memory Architecture: BRAM Line Buffers & Latency](./docs/line_buffer.md)
*Click the link above for the deep dive into the VHDL RTL.*
To compute a 3x3 convolution on a 1D pixel stream, I designed a custom sliding-window generator using BRAM read-before-write delay lines and shift registers. This document details the memory architecture, pipeline warm-up logic, and how I debugged AXI stalls and clock-cycle latency shearing.

### 2. The Math: Sobel Convolution (`sobel.vhd`)
The mathematical core derives the Gx/Gy gradients using an 11-bit signed arithmetic pipeline to prevent overflow. To save DSP slices, the final gradient magnitude uses a hardware-friendly absolute sum approximation (`|Gx| + |Gy|`) with strict saturation clamping to 8-bit unsigned output, ensuring crisp pixel intensity without integer wrap-around.

### 3. The Software: AXI DMA Control (`main.c`)
The ARM processor manages the data stream by directly mapping physical hardware addresses. I learned to bypass the standard 14-bit (16KB) DMA transfer limit by widening the Buffer Length Register to 26 bits in hardware, allowing the C code to seamlessly stream a full 307,200-byte grayscale frame in a single uninterrupted burst.
