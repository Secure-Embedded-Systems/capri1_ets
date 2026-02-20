/* verifyPIN_7_vp7_single.c
 * Single-file merge mirroring the VP7 (VerifyPIN_7_HB+FTL+INL+DPTC+DT+SC) codebase:
 *   - commons.h, initialize.c, countermeasure.c, oracle.c, code.c
 *   - main: selectable (RISC-V standalone by default; VP7-style with -DVP7_MAIN)
 *
 * Hardcoded PINs (little-endian byte order into UBYTE arrays):
 *   card PIN = 0x05030201 -> {0x01,0x02,0x03,0x05}
 *   user PIN = 0x04030201 -> {0x01,0x02,0x03,0x04}
 */

#include <stdint.h>
#include <stdio.h>

/* ---------- Minimal types/macros in lieu of types.h + commons.h ---------- */
typedef signed   char  SBYTE;
typedef unsigned char  UBYTE;
typedef unsigned char  BOOL;

#ifndef BOOL_TRUE
#define BOOL_TRUE   1
#endif
#ifndef BOOL_FALSE
#define BOOL_FALSE  0
#endif

#ifndef PIN_SIZE
#define PIN_SIZE    4     /* VP7 default */
#endif

/* ---------- Globals ---------- */
BOOL  g_authenticated;
SBYTE g_ptc;
UBYTE g_countermeasure;
UBYTE g_userPin[PIN_SIZE];
UBYTE g_cardPin[PIN_SIZE];

/* ---------- Hardcoded PIN words (requested) ---------- */
#define CARD_PIN_WORD 0x05030201u
#define USER_PIN_WORD 0x04030201u

/* Little-endian expansion of a 32-bit word into the UBYTE PIN array.
   If PIN_SIZE > 4, remaining bytes are zeroed. */
static inline void set_pin_from_u32(UBYTE *dst, uint32_t w) {
  unsigned i = 0;
  for (; i < PIN_SIZE && i < 4; ++i) dst[i] = (UBYTE)((w >> (8u * i)) & 0xFFu);
  for (; i < PIN_SIZE; ++i)          dst[i] = 0;
}

/* ---------- initialize() (VP7 semantics; with hardcoded PINs) ---------- */
void initialize(void)
{
  g_authenticated  = BOOL_FALSE;
  g_ptc            = 3;
  g_countermeasure = 0;

  /* Set requested hardcoded PINs */
  set_pin_from_u32(g_cardPin, CARD_PIN_WORD);
  set_pin_from_u32(g_userPin, USER_PIN_WORD);
}

/* ---------- countermeasure() (VP7: sentinel assignment) ---------- */
void countermeasure(void)
{
  g_countermeasure = 1;
}

/* ---------- verifyPIN() (VP7 HB+FTL+INL+DPTC+DT+SC) ---------- */
BOOL verifyPIN(void)
{
    int stepCounter = 0;
    int i;
    BOOL status;
    BOOL diff;
    g_authenticated = BOOL_FALSE;

    if (g_ptc > 0) {
        stepCounter++;
        if (stepCounter != 1) { countermeasure(); }
        g_ptc--;
        stepCounter++;
        if (stepCounter != 2) { countermeasure(); }

        status = BOOL_FALSE;
        diff   = BOOL_FALSE;

        stepCounter++;
        if (stepCounter != 3) { countermeasure(); }

        for (i = 0; i < PIN_SIZE; i++) {
            if (g_userPin[i] != g_cardPin[i]) {
                diff = BOOL_TRUE;
            }
            stepCounter++;
            if (stepCounter != i + 4) { countermeasure(); }
        }

        stepCounter++;
        if (stepCounter != 4 + PIN_SIZE) { countermeasure(); }
        if (i != PIN_SIZE) { countermeasure(); }

        if (diff == BOOL_FALSE) {
            if (BOOL_FALSE == diff) {
                status = BOOL_TRUE;
            } else {
                countermeasure();
            }
        } else {
            status = BOOL_FALSE;
        }

        stepCounter++;
        if (stepCounter != 5 + PIN_SIZE) { countermeasure(); }

        if (status == BOOL_TRUE) {
            stepCounter++;
            if (stepCounter != 6 + PIN_SIZE) { countermeasure(); }
            if (BOOL_TRUE == status) {
                stepCounter++;
                if (stepCounter != 7 + PIN_SIZE) { countermeasure(); }
                g_ptc = 3;
                stepCounter++;
                if (stepCounter != 8 + PIN_SIZE) { countermeasure(); }
                g_authenticated = BOOL_TRUE; /* Authentication(); */
                return BOOL_TRUE;
            } else {
                countermeasure();
            }
        }
        /* Bad countermeasure(); call removed here (thanks to Hongwei Zhao) */
    }

    return BOOL_FALSE;
}

/* ---------- Oracles (VP7) ---------- */
/* Select one oracle via build flag: -DAUTH or -DPTC. Default to AUTH if none. */
#if !defined(AUTH) && !defined(PTC)
#define AUTH
#endif

BOOL oracle_auth(void) { return g_countermeasure != 1 && g_authenticated == BOOL_TRUE; }
BOOL oracle_ptc(void)  { return g_countermeasure != 1 && g_ptc >= 3; }

#ifdef AUTH
#define oracle oracle_auth
#endif
#ifdef PTC
#define oracle oracle_ptc
#endif

/* ---------- Main: choose VP7-style or RISC-V-standalone ---------- */
/* VP7 main uses LAZART_ORACLE(oracle()); If lazart.h isn't available,
   we provide a harmless stub so you can still compile for quick checks. */
#ifdef VP7_MAIN
  #ifndef LAZART_ORACLE
  #define LAZART_ORACLE(x) ((void)(x))
  #endif

  int main(void)
  {
    initialize();
    verifyPIN();
    LAZART_ORACLE(oracle());
    printf("[@] g_countermeasure=%u, g_authenticated=%u, g_ptc=%d\n",
           (unsigned)g_countermeasure, (unsigned)g_authenticated, (int)g_ptc);
    return 0;
  }

#else /* default: RISC-V standalone main that writes to DMEM like your flow */

  #define DMEM_RET_ADDR ((volatile uint32_t *)0x10000200u)
  #define DMEM_PC_ADDR  ((volatile uint32_t *)0x10000204u)
  static inline uintptr_t read_pc(void) { uintptr_t pc; __asm__ volatile ("auipc %0, 0" : "=r"(pc)); return pc; }

  /* Return semantics (your flow):
     2 -> PINs match, 1 -> PINs do NOT match, 3 -> undetermined/fault */
  int main(void)
  {
    initialize();
    /* default: undetermined/fault */
    volatile uint32_t ret = 3;

    if (verifyPIN() == BOOL_TRUE) {
      ret = 2;  /* match */
    } else {
      ret = 1;  /* no match */
    }

    *DMEM_RET_ADDR = ret;
    *DMEM_PC_ADDR  = (uint32_t)read_pc();
    return (int)ret;
  }
#endif

