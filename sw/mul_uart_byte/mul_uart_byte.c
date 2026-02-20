#include <stdint.h>
#define UART_BASE_ADDR   0x03002000u   // UART base (MMIO)
#define UART_RXTX_OFF    0x00u         // TX/RX data register (write: TX one byte)
/* Multiply via shift-add (RV32I-only), then:
   1) write LSB to UART TX (one byte),
   2) store full 32-bit product into DMEM located 128 words (512 bytes) after IMEM. */
int main(void) {
    uint32_t prod;
    __asm__ volatile(
        // a = 10, b = 20, prod = 0
        "addi   t0, x0, 10\n\t"    // t0 = a
        "addi   t1, x0, 20\n\t"    // t1 = b
        "addi   %0, x0, 0\n\t"     // prod = 0

        "1:\n\t"
        "andi   t2, t1, 1\n\t"     // if (b & 1) prod += a;
        "beq    t2, x0, 2f\n\t"
        "add    %0, %0, t0\n\t"
        "2:\n\t"
        "slli   t0, t0, 1\n\t"     // a <<= 1
        "srli   t1, t1, 1\n\t"     // b >>= 1
        "bne    t1, x0, 1b\n\t"    // while (b != 0)

        : "=&r"(prod)
        :
        : "t0","t1","t2","memory"
    );
    // For 10*20 = 200 -> 0xC8.
    *(volatile uint8_t *)(UART_BASE_ADDR + UART_RXTX_OFF) = (uint8_t)prod;

    uintptr_t dmem_ptr;
    __asm__ volatile(
        "auipc  %0, 0\n\t"        // %0 = current PC (within IMEM)
        "andi   %0, %0, -512\n\t" // align down to 512-byte boundary => IMEM base
        "addi   %0, %0, 512\n\t"  // move to DMEM base (= IMEM base + 512 bytes)
        : "=&r"(dmem_ptr)
        :
        : /* no clobbers */
    );
    *(volatile uint32_t *)dmem_ptr = prod;  // store product at DMEM[0]
    return 1;
}

