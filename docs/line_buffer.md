# BRAM-Based Line Buffer for FPGA Vision Pipelines

A VHDL implementation of a 3×3 sliding-window generator for streaming image data, built for the Zynq XC7Z020 (ALINX AX7020). This module converts a raster-scanned 1D pixel stream into a fully parallel 3×3 neighborhood, suitable for convolution-based image processing (Sobel, Harris, general 3×3 kernels) in a single clock cycle per pixel.
<img width="640" height="480" alt="test_image" src="https://github.com/user-attachments/assets/7981ec53-f1db-416c-b36f-4f9e376468ec" />

---

## Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [Design Approach](#design-approach)
- [Architecture](#architecture)
- [Interface](#interface)
- [Resource Cost](#resource-cost)
- [Latency](#latency)
- [Known Limitations & System Constraints](#known-limitations--system-constraints)
- [Lessons Learned / Hardware Bugs Conquered](#lessons-learned--hardware-bugs-conquered)
- [Usage Example & Final Output](#usage-example--final-output)

---

## Overview

A 3×3 spatial filter (Sobel, Harris, box blur, sharpen, etc.) needs simultaneous access to 9 pixels: the current pixel and its 8 neighbors. But a camera or DMA engine delivers pixels **one at a time**, in raster order (left→right, top→bottom). This module — the **line buffer** — bridges that gap: it consumes one pixel per clock cycle and produces a complete, aligned 3×3 window every cycle, with a fixed startup latency and no wasted cycles thereafter.

This is the standard architecture used in real-time FPGA vision pipelines, and is deliberately built here from primitives (BRAM inference + counters + shift registers) rather than using a vendor IP block, so that every stage — timing, memory, addressing — is fully understood and debuggable.

---

## The Problem

Consider computing a Sobel-filtered output for pixel `(row, col)`. The math requires:

```
[ (row-1,col-1)  (row-1,col)  (row-1,col+1) ]
[ (row,  col-1)  (row,  col)  (row,  col+1) ]
[ (row+1,col-1)  (row+1,col)  (row+1,col+1) ]
```

But the incoming stream only ever presents **one** of these 9 values at a time, and by the time row `row+1` arrives, row `row-1`'s pixels are long gone from the wire — unless something stored them.

Naively, you could buffer the *entire image* and randomly-access it, but that costs far more memory than necessary and defeats the purpose of a streaming architecture (it also can't operate on data as it arrives from a live camera). The insight this design uses: **you only ever need the current row plus the two rows immediately above it.** Everything older than that is irrelevant to any future window.

---

## Design Approach

The window is decomposed into two independent delay problems:

| Delay type | Purpose | Mechanism | Depth |
|---|---|---|---|
| **Vertical** (row-to-row) | Reconstruct "the pixel one row up" and "two rows up" | BRAM used as a fixed-length delay line | `IMG_WIDTH` cycles each |
| **Horizontal** (column-to-column) | Reconstruct "the pixel one column left" and "two columns left" | Small flip-flop shift registers | 2 cycles each |

Combining a live value + a 1-cycle-delayed value + a 2-cycle-delayed value for each of 3 rows gives exactly 9 pixels: a full 3×3 window, refreshed every clock cycle once the pipeline has filled.

---

## Architecture

**<img width="1354" height="896" alt="Capture d&#39;écran 2026-07-14 175258" src="https://github.com/user-attachments/assets/1faca4b1-4b3f-4034-aad0-b855df19d3dd" />**

### Vertical delay: BRAM as a shift register

Rather than physically shifting an entire row of pixel data through a chain of registers every cycle (which would be extremely wasteful for a 640-pixel-wide row), this design uses a **counter-addressed BRAM** as an implicit delay line:

```vhdl
signal col_addr : integer range 0 to IMG_WIDTH-1 := 0;
...
row1_pixel <= row_buf1(col_addr);   -- READ (old value at this address)
row_buf1(col_addr) <= pixel_in;     -- WRITE (new value at this address)
```

Both operations target the **same address**, on the **same clock edge**. Because `col_addr` counts from `0` to `IMG_WIDTH-1` and then wraps, the value read back at address `N` on this cycle is exactly the value that was written to address `N` **one full lap of the counter ago** — i.e., `IMG_WIDTH` clock cycles in the past. Since one clock cycle corresponds to one pixel, `IMG_WIDTH` cycles corresponds to exactly **one row**.

This is a **read-before-write** access pattern on the same memory location within a single clock edge. This is safe and well-defined: in synthesizable VHDL, all signal reads within a clocked process observe values from *before* the current clock edge, and all writes take effect only *after* the process completes — matching real BRAM "read-first" behavior. There is no race condition.

Two such BRAMs are chained in series:

```
pixel_in ──►[ BRAM 1, depth = IMG_WIDTH ]──► row1_pixel ──►[ BRAM 2, depth = IMG_WIDTH ]──► row2_pixel
   (row N, live)      delayed 1 row = row N-1      delayed 2 rows = row N-2
```

- **BRAM 1** delays the live input by one row → its output is "row N-1".
- **BRAM 2** delays BRAM 1's *output* by another row → its output is "row N-2".

The delays stack because each stage only ever knows "delay whatever I receive by one row-length" — it has no awareness of which row it's holding, which keeps the design simple and uniform.

### Horizontal delay: per-row shift registers

The BRAM delay lines above give exactly **one pixel per row per cycle** — the value at the *current* column position, for the current row and the two rows above it. That covers the **middle column** of the 3×3 window only. To get the left and right neighbors in each row, a small 2-deep shift register is attached to each row's signal:

```vhdl
type shift_reg_t is array (0 to 1) of std_logic_vector(7 downto 0);
signal row0_sr, row1_sr, row2_sr : shift_reg_t;
...
row0_sr(1) <= row0_sr(0);
row0_sr(0) <= pixel_in;
```

Each row therefore contributes 3 values every cycle:

| Position | Signal |
|---|---|
| Current column (no delay) | `pixel_in` / `row1_pixel` / `row2_pixel` |
| 1 column back | `row*_sr(0)` |
| 2 columns back | `row*_sr(1)` |

Three independent shift registers are required — one per row — because all three rows are live, parallel data streams updating every cycle; a single shared register cannot hold three unrelated histories at once without overwriting itself.

### Window assembly and indexing

The 9 signals above map onto the 3×3 grid in **row-major order** (`index = row*3 + column`), matching how the window is consumed downstream:

```
window(0)=A  window(1)=B  window(2)=C     <- row N-2 (oldest / top)
window(3)=D  window(4)=E  window(5)=F     <- row N-1 (middle)
window(6)=G  window(7)=H  window(8)=I     <- row N   (live / bottom)
```

```vhdl
window_out(0) <= row2_sr(1);   -- A: top-left     (row N-2, 2 cols back)
window_out(1) <= row2_sr(0);   -- B: top-mid      (row N-2, 1 col back)
window_out(2) <= row2_pixel;   -- C: top-right    (row N-2, live)
window_out(3) <= row1_sr(1);   -- D: mid-left
window_out(4) <= row1_sr(0);   -- E: center
window_out(5) <= row1_pixel;   -- F: mid-right
window_out(6) <= row0_sr(1);   -- G: bot-left
window_out(7) <= row0_sr(0);   -- H: bot-mid
window_out(8) <= pixel_in;     -- I: bot-right (current live input pixel)
```

`window(4)` (center, `E`) is always the pixel the current output is computed *for*.

### Pipeline warm-up (`window_valid`)

At the very start of a frame, no window can possibly be valid yet — the BRAMs are still holding reset/garbage values until at least 2 full rows plus 3 pixels have streamed in. A counter tracks this:

```vhdl
signal fill_count : integer range 0 to (IMG_WIDTH*2 + 3) := 0;
...
if fill_count < (IMG_WIDTH*2 + 3) then
    fill_count   <= fill_count + 1;
    window_valid <= '0';   -- still warming up, window not trustworthy yet
else
    window_valid <= '1';   -- 2 rows + 3 pixels have passed, window is real
end if;
```

Once asserted, `window_valid` stays high for the remainder of the frame (subject to the stall-handling rule below). Downstream consumers (e.g. a Sobel core) must gate on this signal and ignore `window_out` while it is low.

### Row/frame resynchronization

For robustness beyond pure free-running counting, the column counter also resets on AXI4-Stream framing signals, when available:

```vhdl
if tuser_in = '1' then
    col_addr <= 0;     -- Start of Frame
elsif tlast_in = '1' then
    col_addr <= 0;     -- End of Row / End of Frame
elsif col_addr = IMG_WIDTH - 1 then
    col_addr <= 0;     -- normal wraparound
else
    col_addr <= col_addr + 1;
end if;
```

This resynchronizes the row boundary from an external, authoritative signal rather than relying purely on the counter never drifting. Note: this only provides real protection if the upstream source actually asserts `TLAST` **per row** — some DMA configurations (e.g. simple/direct-register-mode transfers of a whole frame as one packet) only assert `TLAST` once, at the very end of the entire frame, in which case the free-running counter wraparound is doing all the real work and `TLAST` is not providing per-row protection. This is worth verifying against your specific DMA configuration.

---

## Interface

```vhdl
entity line_buffer is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        pixel_in     : in  std_logic_vector(7 downto 0);  -- incoming 8-bit grayscale pixel
        pixel_valid  : in  std_logic;                      -- new pixel present this cycle
        tlast_in     : in  std_logic;                       -- end-of-row/frame marker (optional resync)
        tuser_in     : in  std_logic;                       -- start-of-frame marker (optional resync)

        window_out   : out pixel_window_t;                  -- 9-element array, 8 bits each
        window_valid : out std_logic                        -- window_out is valid this cycle
    );
end entity line_buffer;
```

`pixel_window_t` is defined in a shared package (`sobel_pkg.vhd`) so it can be referenced consistently by both this module and any downstream consumer:

```vhdl
type pixel_window_t is array (0 to 8) of std_logic_vector(7 downto 0);
```

---

## Resource Cost

For an image width of `IMG_WIDTH = 640` and 8-bit pixels:

| Resource | Quantity | Notes |
|---|---|---|
| BRAM delay lines | 2 × (640 × 8 bits) | Each ≈ 5 Kb; Vivado infers Block RAM primitives from the array + counter-addressed read/write pattern |
| Flip-flops (shift regs) | 3 rows × 2 stages × 8 bits = 48 FF | Small, negligible LUT/FF cost |
| Counters | `col_addr` (10 bits), `fill_count` (11 bits) | Negligible |

The dominant cost is the two BRAM delay lines, whose depth scales linearly with image width — for wider images, expect proportionally more BRAM (or larger BRAM primitives at fixed width).

---

## Latency

- **Startup (fill) latency:** `2 × IMG_WIDTH + 3` clock cycles before the first valid window is produced — inherent to needing 2 full rows of context before any 3×3 window exists.
- **Steady-state (register) latency:** a small, fixed number of cycles due to the module's own registered outputs — separate from and much smaller than the startup latency. This adds a constant delay between a pixel entering the module and its corresponding window appearing at the output; it does not affect image quality, only overall pipeline timing (relevant only if synchronizing against another signal, e.g. overlaying output on the original frame).

---

## Known Limitations & System Constraints

- **AXI DMA Buffer Length Limit:** This IP relies on being fed by a DMA engine. Xilinx AXI DMA defaults the `LENGTH` register to 14 bits (max 16,383 bytes). Streaming a 640×480 grayscale image requires a single block transfer of 307,200 bytes. The DMA will silently truncate the transfer and halt after ~19 rows unless the **Width of Buffer Length Register** is manually expanded to at least 26 bits in the Vivado Block Design.
- **Row/column boundaries:** pixels at the very first/last column of a row, or the first/last row of a frame, have some notionally out-of-frame neighbors (e.g. "column -1" for the leftmost pixel). This implementation does not currently apply explicit edge padding or replication — border-pixel outputs should be treated as approximate/invalid by downstream consumers, or extended with zero-padding/edge-replication logic if exact border behavior is required.
- **`IMG_WIDTH` is a compile-time constant.** Supporting multiple resolutions requires either regenerating the bitstream with a different constant, or extending the design with a runtime-configurable width (would require dynamic BRAM addressing logic, not currently implemented).
- **No backpressure output.** This module currently assumes it can always accept a new pixel when `pixel_valid` is asserted (i.e., it never needs to assert its own "not ready" signal upstream). If a downstream consumer can stall (e.g., a multi-cycle compute stage without matching backpressure handling), data loss or corruption could occur without an end-to-end backpressure chain.

---

## Lessons Learned / Hardware Bugs Conquered

Documented here because these cost real debugging time and are easy to reintroduce during future edits:

1. **Missing stall-handling `else` branch (horizontal ghosting).** If `window_valid` (and any other state driven only inside the `pixel_valid = '1'` branch) doesn't have an explicit `else` clause forcing it low during stalls, a paused input stream (e.g. a DMA bus contention stall) leaves stale outputs marked "valid," causing the downstream stage to reprocess the same frozen window repeatedly. Visually, this manifested as a horizontal image shift with ghosted/duplicated content.

   **<img width="512" height="389" alt="bug" src="https://github.com/user-attachments/assets/065fc9f4-9a82-4bb5-9d3f-6b28c246e853" />**

2. **BRAM read latency placement (diagonal shearing).** Initially, the read assignment `row1_pixel <= row_buf1(col_addr);` was placed inside the clocked `process(clk)`. This is correctly synthesized as a registered (sequential) read, introducing an unintended 1-clock-cycle delay relative to the rest of the window. This desynchronized the vertical columns of the window relative to each other, resulting in visible diagonal shearing across the output image. Moving the read to a combinatorial (0-cycle) assignment realigned the rows and resolved the shearing.

3. **A single flipped bit in the `window_valid` warm-up logic silently disables the entire pipeline.** The branch intended to assert `window_valid <= '1'` once the BRAMs are full was, at one point, mistakenly left as `'0'` (a copy-paste artifact) — this produces no compile-time error, and downstream stages simply never receive a valid window, with no obvious symptom other than wrong/blank output. Always double check this specific line after any edit near it.

4. **Vivado incremental synthesis can mask a fix.** After editing this file and repackaging it as an IP, forgetting to **Reset Runs** on `synth_1`/`impl_1` before regenerating the bitstream can cause Vivado to silently reuse a stale, previously-synthesized netlist — meaning a "freshly generated" bitstream may still contain a bug that was already fixed in source. Always reset runs after a source-level correction to a packaged IP.

5. **IP top-level confusion.** If this module (or any submodule) is temporarily set as the project's synthesis "Top" for the purpose of IP packaging, remember to reset "Set as Top" back to the actual system-level wrapper before generating a bitstream — otherwise Vivado will attempt to synthesize this module's raw ports as physical chip I/O pins, producing `NSTD-1`/`UCIO-1` DRC failures unrelated to the module's actual logic.

---

## Usage Example & Final Output

```vhdl
lb: entity work.line_buffer
    port map (
        clk          => clk,
        rst          => rst,
        pixel_in     => s_axis_tdata,
        pixel_valid  => s_axis_tvalid,
        tlast_in     => s_axis_tlast,
        tuser_in     => s_axis_tuser,
        window_out   => window_sig,
        window_valid => window_valid_sig
    );
```

Downstream, a compute stage (e.g. a Sobel filter) consumes `window_sig`/`window_valid_sig` and should be gated identically — ignore/hold output whenever `window_valid_sig = '0'`.

**<img width="512" height="389" alt="output" src="https://github.com/user-attachments/assets/48528e6a-5b9a-488a-8007-b2a0380edf66" />**
