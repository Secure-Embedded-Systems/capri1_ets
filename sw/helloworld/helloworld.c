#include <stdint.h>

#define GPIO_BASE_ADDR    0x03005000

#define GPIO_DIR_REG_OFFSET           0x000
#define GPIO_EN_REG_OFFSET            0x080
#define GPIO_OUT_REG_OFFSET           0x180
#define GPIO_TOGGLE_REG_OFFSET        0x200

static inline volatile uint32_t *reg32(const unsigned int base, int offs) {
    return (volatile uint32_t *)(base + offs);
}

void gpio_set_direction(uint32_t mask, uint32_t direction) {
    uint32_t dir_old = *reg32(GPIO_BASE_ADDR, GPIO_DIR_REG_OFFSET);
    *reg32(GPIO_BASE_ADDR, GPIO_DIR_REG_OFFSET) = (dir_old & ~mask) | (direction & mask);
}

void gpio_write(uint32_t value) {
    *reg32(GPIO_BASE_ADDR, GPIO_OUT_REG_OFFSET) = value;
}

void gpio_enable(uint32_t mask) {
    *reg32(GPIO_BASE_ADDR, GPIO_EN_REG_OFFSET) |= mask;
}

void gpio_toggle(uint32_t mask) {
    *reg32(GPIO_BASE_ADDR, GPIO_TOGGLE_REG_OFFSET) = mask;
}

int main() {
  int i;
  gpio_enable(0xFFFF);
  gpio_set_direction(0xFFFF, 0x000F);
  gpio_write(0x0A);
  for (i=0; i<10; i++)
	gpio_toggle(0xF);
  return 1;
}
