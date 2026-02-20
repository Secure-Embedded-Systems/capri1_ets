init
riscv dmi_write 0x10 0x00000001      	;# dmactive=1
riscv dmi_write 0x38 0x20040C07      	;# SBA: 32-bit, autoinc, read-on-data
riscv dmi_write 0x37 0x00000000
riscv dmi_write 0x39 0x03000004      	;# FETCHEN
riscv dmi_write 0x3C 0x00000001      	;# FETCHEN=1

riscv dmi_write 0x10 0x04000003      	;# setresethaltreq|ndmreset|dmactive
sleep 20
riscv dmi_write 0x10 0x04000001      	;# release reset (resethaltreq still set)
sleep 20
riscv dmi_write 0x10 0x02000001      	;# clrresethaltreq
riscv dmi_read  0x11

mww 0x10000000 0x0 256
mdw 0x10000000 256  

halt
load_image ./verifyPIN_0_opt.bin 0x10000000 bin
shutdown

