# Zynq AXI DMA Sobel Accelerator

A custom hardware accelerator for a Zynq SoC that performs Sobel edge detection on a 640x480 image. The pipeline uses a custom VHDL IP block for the math and line buffering, connected to the ARM processor via AXI DMA.

## System Architecture
* **Hardware:** Custom `line_buffer` and `sobel` VHDL IP, packaged in Vivado.
* **Interface:** AXI DMA (configured for 26-bit buffer length to handle 307,200-byte bursts).
* **Software:** Linux C driver using `mmap()` to `/dev/mem` with the `O_SYNC` flag for direct, un-cached physical DDR RAM access.

## Current Status: Pipeline Synchronization Bug
The underlying mathematical logic and DMA memory mapping are fully functional. However, the output image currently exhibits two visual artifacts due to a pipeline synchronization or AXI stream timing bug:

1. **Horizontal Phase Shift / Wrap-Around:** The image shifts horizontally, with the right side wrapping around to the left edge.
2. **Row Shearing / Ghosting:** Vertical lines are smeared horizontally, suggesting a 1-clock-cycle delay mismatch between the rows in the 3x3 pixel window.

*See the `/images` folder for visual examples of the artifacts on a test image of a car and a geometric maze.*

## Code Structure
* `/vhdl_src/`: Contains the VHDL source code for the 3x3 line buffer and the Sobel gradient math.
* `/c_driver/`: Contains the C application that configures the AXI DMA registers and triggers the memory transfer.
