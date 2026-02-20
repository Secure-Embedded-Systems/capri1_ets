/* verifyPIN_7.c
 *
 * Single-file merge of commons.h, initialize.c, countermeasure.c, oracle.c,
 * code.c and a riscv-friendly main(). Place in directory verifyPIN_7/
 * and build with: make PROGRAM=verifyPIN_7
 *
 * Return semantics:
 *   0 -> PINs match
 *   1 -> PINs do NOT match
 *   2 -> undetermined / fault (default)
 */

#include <stdint.h>
#include <stdio.h>

/* ------------------ copied/adapted commons.h content ------------------ */

/* basic types */
typedef signed char   SBYTE;
typedef unsigned char UBYTE;
typedef unsigned char BOOL;
typedef unsigned long ULONG;

#define BOOL_TRUE  0xAA
#define BOOL_FALSE 0x55

/* If no PIN_SIZE provided externally, default to 4 */
#ifndef PIN_SIZE
#define PIN_SIZE 4
#endif

/* ------------------ globals (merged) ------------------ */

BOOL  g_authenticated;
SBYTE g_ptc;
UBYTE g_countermeasure;
UBYTE g_userPin[PIN_SIZE];
UBYTE g_cardPin[PIN_SIZE];

/* ------------------ initialize.c (adapted) ------------------ */

void initialize(void)
{
    /* initialize globals so behavior is identical/predictable for test harness */
    g_authenticated  = BOOL_FALSE;
    g_ptc            = 3;         /* attempts */
    g_countermeasure = 0x00;
}

/* ------------------ countermeasure.c (adapted) ------------------ */
/* Keep it small & volatile to avoid compiler removing it in optimization.
   In your real experiments replace / augment this with the HW countermeasure
   logic that toggles sensors / dummy loops / noise injection, etc. */
void countermeasure(void)
{
    /* small volatile op to force side-effect */
    volatile UBYTE t = g_countermeasure;
    t ^= 0x5A;
    g_countermeasure = (UBYTE)t;
}

/* ------------------ oracle.c (adapted) ------------------ */
/* The uploaded oracle in your tree applies checks and may call countermeasure.
   Here we provide a simple stub that demonstrates how you'd call it in verifyPIN().
   Replace its internals with your measurement/oracle if needed. */
BOOL oracle(void)
{
    /* Example: call the countermeasure once and return BOOL_FALSE (no special event) */
    countermeasure();
    return BOOL_FALSE;
}

/* ------------------ helper: byteArrayCompare ------------------ */
/* A straightforward constant-time-style (basic) comparison. If you want
   to use masking/hardening or an intentionally vulnerable variant, modify here. */
static inline BOOL byteArrayCompare(const UBYTE *a1, const UBYTE *a2, UBYTE size)
{
    UBYTE i;
    for (i = 0; i < size; i++) {
        if (a1[i] != a2[i]) {
            return 0;
        }
    }
    return 1;
}

/* ------------------ verifyPIN (merged from code.c) ------------------ */
/* This implementation follows the uploaded code.c intent: it hardcodes both
 * the user PIN (input) and the card PIN (stored), performs stepwise checks,
 * uses a step counter, and invokes countermeasure() on certain branches.
 *
 * The behavior:
 *  - If attempts remain (g_ptc > 0): compare PINs
 *  - On success: restore g_ptc to 3, set g_authenticated, return BOOL_TRUE
 *  - On mismatch: decrement g_ptc, return BOOL_FALSE
 *  - If no attempts: return BOOL_FALSE
 *
 * Replace hardcoded PINs or fetch them from memory / mmio if you want
 * to generate different testcases/programs.
 */

/* Hardcoded user PIN (simulate input) */
#define USER_PIN_0 0x01
#define USER_PIN_1 0x02
#define USER_PIN_2 0x03
#define USER_PIN_3 0x04

/* Hardcoded card PIN (stored on card) - last nibble slightly different to test mismatch */
#define CARD_PIN_0 0x01
#define CARD_PIN_1 0x02
#define CARD_PIN_2 0x03
#define CARD_PIN_3 0x05

BOOL verifyPIN(void)
{
    int stepCounter = 0;
    int i;
    BOOL status = BOOL_FALSE;
    BOOL diff;

    /* Reset authentication flag */
    g_authenticated = BOOL_FALSE;

    /* Hardcode the user PIN (simulate reading user input) */
    g_userPin[0] = USER_PIN_0;
    g_userPin[1] = USER_PIN_1;
    g_userPin[2] = USER_PIN_2;
    g_userPin[3] = USER_PIN_3;

    /* Hardcode the card PIN (what's stored on the card) */
    g_cardPin[0] = CARD_PIN_0;
    g_cardPin[1] = CARD_PIN_1;
    g_cardPin[2] = CARD_PIN_2;
    g_cardPin[3] = CARD_PIN_3;

    /* Optional oracle call — keep for parity with your original design.
       If the oracle indicates a measurement/fault condition, you can branch
       to trigger countermeasure or early return. Here we call it and ignore. */
    (void)oracle();

    /* If attempts remain, perform the comparison */
    if (g_ptc > 0) {
        /* stepCounter illustrates per-byte processing (useful for leakage analysis) */
        stepCounter = 0;
        diff = 0;

        for (i = 0; i < PIN_SIZE; i++) {
            /* increment step */
            stepCounter++;

            /* Compare byte i */
            if (g_userPin[i] != g_cardPin[i]) {
                diff = 1;
                /* call a countermeasure on mismatch branch to mimic hardened code */
                countermeasure();
                /* continue loop (we do not early return — helps to model constant-time) */
            } else {
                /* optionally do a different small op on match */
                /* keep symmetry: still call countermeasure to keep side-effects consistent */
                countermeasure();
            }
        }

        /* after loop — evaluate result */
        if (diff == 0) {
            /* match: restore attempts, set authenticated flag */
            g_ptc = 3;
            g_authenticated = BOOL_TRUE;
            return BOOL_TRUE;
        } else {
            /* mismatch: decrement attempts and return false */
            g_ptc--;
            return BOOL_FALSE;
        }
    }

    /* attempts exhausted => return false */
    return BOOL_FALSE;
}

/* ------------------ main() ------------------ */
/* Minimal main to match the Makefile expectations and return codes:
 * 0 = success (PIN matched)
 * 1 = PIN did not match
 * 2 = undetermined/fault (left as default)
 */
int main(void)
{
    initialize();

    /* default to 2: undetermined / fault */
    int ret = 2;

    BOOL pin_verified = verifyPIN();
    if (pin_verified == BOOL_TRUE) {
        ret = 0;   /* pins match */
    } else if (pin_verified == BOOL_FALSE) {
        ret = 1;   /* pins do not match */
    }

    return ret;
}

