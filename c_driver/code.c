#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdint.h>
#include <string.h>

#define DMA_BASE   0x40400000
#define MAP_SIZE   0x1000

// DMA register offsets
#define MM2S_DMACR   0x00
#define MM2S_DMASR   0x04
#define MM2S_SA      0x18
#define MM2S_LENGTH  0x28
#define S2MM_DMACR   0x30
#define S2MM_DMASR   0x34
#define S2MM_DA      0x48
#define S2MM_LENGTH  0x58

#define IMG_ADDR     0x1E000000   // where we'll put our test image
#define OUT_ADDR     0x1E100000   // where Sobel output will land
#define IMG_SIZE     (640*480)    // adjust to your actual test image size

int main() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open"); return 1; }

    // Map the DMA control registers
    volatile uint32_t *dma = mmap(NULL, MAP_SIZE, PROT_READ|PROT_WRITE,
                                    MAP_SHARED, fd, DMA_BASE);
    if (dma == MAP_FAILED) { perror("mmap dma"); return 1; }

    // Map the image buffer region (so we can write our test image into DDR)
    volatile uint8_t *img_buf = mmap(NULL, IMG_SIZE, PROT_READ|PROT_WRITE,
                                       MAP_SHARED, fd, IMG_ADDR);
    if (img_buf == MAP_FAILED) { perror("mmap img"); return 1; }

    volatile uint8_t *out_buf = mmap(NULL, IMG_SIZE, PROT_READ|PROT_WRITE,
                                       MAP_SHARED, fd, OUT_ADDR);
    if (out_buf == MAP_FAILED) { perror("mmap out"); return 1; }

    // TODO: load actual test image bytes into img_buf here (we'll add this next)
    // Load test image (raw grayscale bytes) from a file already SCP'd to the board
    FILE *f = fopen("test_image.bin", "rb");
    if (!f) { perror("fopen"); return 1; }
    fread((void*)img_buf, 1, IMG_SIZE, f);
    fclose(f);

    // Reset both DMA channels first (good practice, clears any stale state)
    dma[MM2S_DMACR/4] = 0x4;  // bit 2 = Reset
    dma[S2MM_DMACR/4] = 0x4;
    usleep(1000);

    // Start both channels (bit 0 = Run/Stop, set to 1 = run)
    dma[MM2S_DMACR/4] = 0x1;
    dma[S2MM_DMACR/4] = 0x1;

    // Tell S2MM where to write, and how much to expect (set this up BEFORE starting MM2S,
    // since S2MM must be "ready" before data starts arriving)
    dma[S2MM_DA/4] = OUT_ADDR;
    dma[S2MM_LENGTH/4] = IMG_SIZE;   // writing this register also kicks off S2MM's wait-for-data

    // Tell MM2S where to read from, and how much to send — writing LENGTH starts the actual transfer
    dma[MM2S_SA/4] = IMG_ADDR;
    dma[MM2S_LENGTH/4] = IMG_SIZE;   // writing this register triggers the read

    // Poll status registers until both report completion (bit 1 = Idle, meaning done)
    while (!(dma[MM2S_DMASR/4] & 0x2));
    while (!(dma[S2MM_DMASR/4] & 0x2));

    printf("Transfer complete!\n");

    // Save output buffer to a file so we can SCP it back and view it
    FILE *out = fopen("output_image.bin", "wb");
    fwrite((void*)out_buf, 1, IMG_SIZE, out);
    fclose(out);

    munmap((void*)dma, MAP_SIZE);
    munmap((void*)img_buf, IMG_SIZE);
    munmap((void*)out_buf, IMG_SIZE);
    close(fd);
    return 0;
}
