#include <stdint.h>
#include <stdio.h>

#define UART_BASE_ADDR 0x03002000

//------------types-----------------------
#ifndef H_TYPES
#define H_TYPES
typedef signed char   SBYTE;
typedef unsigned char UBYTE;
typedef unsigned char BOOL;
typedef unsigned long ULONG;

#define BOOL_TRUE  0xAA
#define BOOL_FALSE 0x55
#endif // H_TYPES

// If PIN_SIZE isn't provided by an external header, default to 4
#ifndef PIN_SIZE
#define PIN_SIZE 4
#endif

//-----------interface ------------
#ifndef H_INTERFACE
#define H_INTERFACE
void  countermeasure(void);
void  initialize(void);
BOOL  oracle(void);
#endif // H_INTERFACE

//------------globals & initialize---------------------------

// global variables definition
BOOL  g_authenticated;
SBYTE g_ptc;
UBYTE g_countermeasure;
UBYTE g_userPin[PIN_SIZE];
UBYTE g_cardPin[PIN_SIZE];

void initialize(void)
{
    // global variables initialization
    g_authenticated  = 0;
    g_ptc            = 3;
    g_countermeasure = 0;
}

//-------------verifyPIN()----------------------
extern SBYTE g_ptc;
extern BOOL  g_authenticated;
extern UBYTE g_userPin[PIN_SIZE];
extern UBYTE g_cardPin[PIN_SIZE];

// Hardcoded user PIN
#define USER_PIN_0 0x01
#define USER_PIN_1 0x02
#define USER_PIN_2 0x03
#define USER_PIN_3 0x04

// Hardcoded card PIN (last byte intentionally different)
#define CARD_PIN_0 0x01
#define CARD_PIN_1 0x02
#define CARD_PIN_2 0x03
#define CARD_PIN_3 0x05

// Fixed DMEM addresses for result logging
#define DMEM_RET_ADDR ((volatile uint32_t *)0x10000200u)
#define DMEM_PC_ADDR  ((volatile uint32_t *)0x10000204u)

// Read the current PC using AUIPC (RISC-V)
static inline uintptr_t read_pc(void) {
    uintptr_t pc;
    __asm__ volatile ("auipc %0, 0" : "=r"(pc));
    return pc;
}

#ifdef INLINE
__attribute__((always_inline)) inline BOOL byteArrayCompare(UBYTE* a1, UBYTE* a2, UBYTE size)
#else
BOOL byteArrayCompare(UBYTE* a1, UBYTE* a2, UBYTE size)
#endif
{
  //  *(DMEM_PC_ADDR+16)  = (uint32_t)read_pc();   // current PC (near this point)
    UBYTE i;
    for (i = 0; i < size; i++) {
        if (a1[i] != a2[i]) {
            return 0;
        }
    }
    return 1;
}

BOOL verifyPIN(void)
{
    g_authenticated = 0;

    // Hardcode the user PIN
    g_userPin[0] = USER_PIN_0;
    g_userPin[1] = USER_PIN_1;
    g_userPin[2] = USER_PIN_2;
    g_userPin[3] = USER_PIN_3;

    // Hardcode the card PIN
    g_cardPin[0] = CARD_PIN_0;
    g_cardPin[1] = CARD_PIN_1;
    g_cardPin[2] = CARD_PIN_2;
    g_cardPin[3] = CARD_PIN_3;

    if (g_ptc > 0) {
        if (byteArrayCompare(g_userPin, g_cardPin, PIN_SIZE) == 1) {
            g_ptc = 3;
            g_authenticated = 1; // Authentication();
//	    *DMEM_RET_ADDR = (uint32_t)g_authenticated;         // final return value
   //	    *(DMEM_PC_ADDR+12)  = (uint32_t)read_pc();   // current PC (near this point)


            return 1;            // match
        } else {
            g_ptc--;
            return 0;            // no match
        }

    }
    //*DMEM_RET_ADDR = (uint32_t)g_authenticated;         // final return value
    //*(DMEM_PC_ADDR+12)  = (uint32_t)read_pc();   // current PC (near this point)

    return 0;                    // attempts exhausted -> treat as no match
}

//---------------------------------------
extern UBYTE g_countermeasure;


int main(void)
{

    //*DMEM_PC_ADDR  = (uint32_t)read_pc();   // current PC (near this point)

    initialize();

   // *(DMEM_PC_ADDR+4)  = (uint32_t)read_pc();   // current PC (near this point)

    // ret is volatile as requested
    volatile BOOL ret = 3;  // 3 = undetermined/fault, will be overwritten below

 //   *(DMEM_PC_ADDR+8)  = (uint32_t)read_pc();   // current PC (near this point)

    BOOL pin_verified = verifyPIN();
//    *(DMEM_PC_ADDR+20)  = (uint32_t)read_pc();   // current PC (near this point)

    if (pin_verified == 1) {
        ret = 2;   // pins match
    } else if (pin_verified == 0) {
        ret = 1;   // pins do not match
    }
    // else ret remains 2 (e.g., random fault / undetermined)

    // --- Store outputs to DMEM BEFORE returning ---
    *DMEM_RET_ADDR = (uint32_t)ret;         // final return value
    *DMEM_PC_ADDR  = (uint32_t)read_pc();   // current PC (near this point)

    return (int)ret;
}
