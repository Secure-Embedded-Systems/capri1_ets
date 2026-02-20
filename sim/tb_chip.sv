`timescale 1ns/1ps

`define TRACE_WAVE

module tb_chip #(
    parameter time         ClkPeriod     = 50ns,
    parameter time         ClkPeriodJtag = 50ns,
    parameter time         ClkPeriodRef  = 50ns,
    parameter time         ClkPeriodRO   = 50ns,
    parameter time         TAppl         = 0.2*ClkPeriod,
    parameter time         TTest         = 0.8*ClkPeriod,
    parameter int unsigned RstCycles     = 1,
    parameter int unsigned RstCyclesRO   = 1,
    parameter int unsigned  UartBaudRate      = 115200,
    parameter int unsigned  UartParityEna     = 0,
    parameter scan_bits = 12756,
    localparam int unsigned ClkFrequency = 1s / ClkPeriod
)();


  localparam bit [31:0] BootAddrAddr   = croc_pkg::SocCtrlAddrOffset
                                        + soc_ctrl_reg_pkg::SOC_CTRL_BOOTADDR_OFFSET;
  localparam bit [31:0] FetchEnAddr    = croc_pkg::SocCtrlAddrOffset
                                        + soc_ctrl_reg_pkg::SOC_CTRL_FETCHEN_OFFSET;
  localparam bit [31:0] CoreStatusAddr = croc_pkg::SocCtrlAddrOffset
                                        + soc_ctrl_reg_pkg::SOC_CTRL_CORESTATUS_OFFSET;


    logic clk_i;        // top_0
    logic rst_ni;       // top_1
    logic scan_en_i;    // top_2
    logic scan_mode_i;  // top_3
    logic ref_clk_i;    // top_4
    logic tdi_i;        // top_5
    logic tdo_o;        // top_6

    logic jtag_tck_i;   // left_0
    logic jtag_trst_ni; // left_1
    logic jtag_tms_i;   // left_2
    logic jtag_tdi_i;   // left_3
    logic uart_rx_i;    // left_4
    logic fetch_en_i;   // left_5

    logic jtag_tdo_o;   // bottom_0
    logic uart_tx_o;    // bottom_1
    logic status_o;     // bottom_2
 //   logic [1:0] gpio_o; // bottom_3, bottom_4
    logic ro_q;         // bottom_5
    logic ro_chain_q;   // bottom_6
    (* dont_touch = "true" *) logic [3:0] ro_data_q; // bottom_7..10

    logic ro_clk;       // right_0
    logic ro_rst_n;     // right_1
    logic ro_ce_n;      // right_2
    logic ro_en;        // right_3
    logic ro_chain_i;   // right_4
    (* dont_touch = "true" *) logic [3:0] ro_data_d; // right_5..8

    localparam int unsigned GpioCount = 2;

    logic [GpioCount-1:0] gpio_i;
    logic [GpioCount-1:0] gpio_o;
    logic [GpioCount-1:0] gpio_out_en_o;

//--------------------clk -----------------

    clk_rst_gen #(
        .ClkPeriod    ( ClkPeriod ),
        .RstClkCycles ( RstCycles )
    ) i_clk_rst_sys (
        .clk_o  ( clk_i  ),
        .rst_no ( rst_ni )
    );

    clk_rst_gen #(
        .ClkPeriod    ( ClkPeriodRef ),
        .RstClkCycles ( RstCycles )
    ) i_clk_rst_rtc (
        .clk_o  ( ref_clk_i ),
        .rst_no ( )
    );

    clk_rst_gen #(
        .ClkPeriod    ( ClkPeriodJtag ),
        .RstClkCycles ( RstCycles )
    ) i_clk_jtag (
        .clk_o  ( jtag_tck_i ),
        .rst_no ( )
    );

    clk_rst_gen #(
        .ClkPeriod    ( ClkPeriodRO ),
        .RstClkCycles ( RstCyclesRO )
    ) i_clk_ro (
        .clk_o  (ro_clk),
        .rst_no (ro_rst_n)
    );

//------------------------ JTAG ------------------
   localparam dm::sbcs_t JtagInitSbcs = dm::sbcs_t'{
        sbautoincrement: 1'b1, sbreadondata: 1'b1, sbaccess: 3, default: '0};

    riscv_dbg_simple #(
        .IrLength ( 5 ),
        .TA       ( TAppl ),
        .TT       ( TTest )
    ) jtag_dbg (
        .jtag_tck_i   ( jtag_tck_i   ),
        .jtag_trst_no ( jtag_trst_ni ),
        .jtag_tms_o   ( jtag_tms_i ),
        .jtag_tdi_o   ( jtag_tdi_i ),
        .jtag_tdo_i   ( jtag_tdo_o   )
    );

    initial begin
      #(ClkPeriod/2);
      jtag_dbg.reset_master();
    end

    task automatic jtag_write(
        input dm::dm_csr_e addr,
        input logic [31:0] data,
        input bit wait_cmd = 0,
        input bit wait_sba = 0
    );
        jtag_dbg.write_dmi(addr, data);
        if (wait_cmd) begin
            dm::abstractcs_t acs;
            do begin
                jtag_dbg.read_dmi_exp_backoff(dm::AbstractCS, acs);
                if (acs.cmderr) $fatal(1, "[JTAG] Abstract command error!");
            end while (acs.busy);
        end
        if (wait_sba) begin
            dm::sbcs_t sbcs;
            do begin
                jtag_dbg.read_dmi_exp_backoff(dm::SBCS, sbcs);
                if (sbcs.sberror | sbcs.sbbusyerror) $fatal(1, "[JTAG] System bus error!");
            end while (sbcs.sbbusy);
        end
    endtask


    // Initialize the debug module
    task automatic jtag_init;
        logic [31:0] idcode;
        dm::dmcontrol_t dmcontrol = '{dmactive: 1, default: '0};
        // Check ID code
        repeat(100) @(posedge jtag_tck_i);
        jtag_dbg.get_idcode(idcode);
        if (idcode != croc_pkg::PulpJtagIdCode)
            $fatal(1, "@%t | [JTAG] Unexpected ID code: expected 0x%h, got 0x%h!",
                $time, croc_pkg::PulpJtagIdCode, idcode);
        // Activate, wait for debug module
        jtag_write(dm::DMControl, dmcontrol);
        do jtag_dbg.read_dmi_exp_backoff(dm::DMControl, dmcontrol);
        while (~dmcontrol.dmactive);
        // Activate, wait for system bus
        jtag_write(dm::SBCS, JtagInitSbcs, 0, 1);
        jtag_write(dm::SBAddress1, '0); // 32-bit addressing only
        $display("@%t | [JTAG] Initialization success", $time);
    endtask

    // Halt the core
    task automatic jtag_halt;
      dm::dmstatus_t status;
      // Halt hart 0
      jtag_write(dm::DMControl, dm::dmcontrol_t'{haltreq: 1, dmactive: 1, default: '0});
      $display("@%t | [JTAG] Halting hart 0... ", $time);
      do jtag_dbg.read_dmi_exp_backoff(dm::DMStatus, status);
      while (~status.allhalted);
      $display("@%t | [JTAG] Halted", $time);
    endtask

    task automatic jtag_resume;
      dm::dmstatus_t status;
      // Halt hart 0
      jtag_write(dm::DMControl, dm::dmcontrol_t'{resumereq: 1, dmactive: 1, default: '0});
      $display("@%t | [JTAG] Resumed hart 0 ", $time);
    endtask

    task automatic jtag_read_reg32(
        input logic [31:0] addr,
        output logic [31:0] data,
        input int unsigned idle_cycles = 10
    );
        automatic dm::sbcs_t sbcs = dm::sbcs_t'{sbreadonaddr: 1'b1, sbaccess: 2, default: '0};
        jtag_write(dm::SBCS, sbcs, 0, 1);
        jtag_write(dm::SBAddress0, addr[31:0]);
        jtag_dbg.wait_idle(idle_cycles);
        jtag_dbg.read_dmi_exp_backoff(dm::SBData0, data);
        $display("@%t | [JTAG] Read 0x%h from 0x%h", $time, data, addr);
    endtask

   task automatic jtag_write_reg32(
        input logic [31:0] addr,
        input logic [31:0] data,
        input bit check_write = 1'b0,
        input int unsigned idle_cycles = 10
    );
        automatic dm::sbcs_t sbcs = dm::sbcs_t'{sbaccess: 2, default: '0};
        $display("@%t | [JTAG] Writing 0x%h to 0x%h", $time, data, addr);
        jtag_write(dm::SBCS, sbcs, 0, 1);
        jtag_write(dm::SBAddress0, addr);
        jtag_write(dm::SBData0, data);
        jtag_dbg.wait_idle(idle_cycles);
        if (check_write) begin
            logic [31:0] rdata;
            jtag_read_reg32(addr, rdata);
            if (rdata !== data) $fatal(1,"@%t | [JTAG] Read back incorrect data 0x%h!", $time, rdata);
            else $display("@%t | [JTAG] Read back correct data", $time);
        end
    endtask

    // Load the binary formated as 32bit hex file
    task jtag_load_hex(input string filename);
        int file;
        int status;
        string line;
        bit [31:0] addr;
        bit [31:0] data;
        bit [7:0] byte_data;
        int byte_count;
        static dm::sbcs_t sbcs = dm::sbcs_t'{sbautoincrement: 1'b1, sbaccess: 2, default: '0};

        file = $fopen(filename, "r");
        if (file == 0) begin
            if (file == 0) begin
                $fatal(1, "Error: Failed to open file %s", filename);
        end
        end

        $display("@%t | [JTAG] Loading binary from %s", $time, filename);
        jtag_dbg.write_dmi(dm::SBCS, sbcs);

        // line by line
        while (!$feof(file)) begin
            if ($fgets(line, file) == 0) begin
                break; // End of file
            end
                // '@' indicates address
            if (line[0] == "@") begin
                status = $sscanf(line, "@%h", addr);
                if (status != 1) begin
                    $fatal(1, "Error: Incorrect address line format in file %s", filename);
                end
                $display("@%t | [JTAG] Writing to memory @%08x ", $time, addr);
                jtag_dbg.write_dmi(dm::SBAddress0, addr);
                continue;
            end

            byte_count = 0;
            data = 32'h0;

            // Loop through the line to read bytes
            while (line.len() > 0) begin
                status = $sscanf(line, "%h", byte_data); // Extract one byte
                if (status != 1) begin
                    break; // No more data to read on this line
                end

                // Shift in the byte to the correct position in the data word
                data = {byte_data, data[31:8]}; // Combine bytes into a 32-bit word
                byte_count++;

                // remove the byte from the line (2 numbers + 1 space)
                line = line.substr(3, line.len()-1);

                // write a complete word via jtag
                if (byte_count == 4) begin
                    jtag_write(dm::SBData0, data);
                    addr += 4;
                    data = 32'h0;
                    byte_count = 0;
                end
            end
        end
        jtag_dbg.write_dmi(dm::SBCS, JtagInitSbcs);
        $fclose(file);
    endtask

    // Wait for termination signal and get return code
    // currently this gives a system bus error
 task automatic jtag_wait_for_eoc(output bit [31:0] exit_code);
            automatic dm::sbcs_t sbcs = dm::sbcs_t'{sbreadonaddr: 1'b1, sbaccess: 2, default: '0};
               automatic int max_attempts = 200; // Set a reasonable timeout limit
                  automatic int attempt = 0;
                  logic [31:0] dpc_value;
                     jtag_write(dm::SBCS, sbcs, 0, 1);
                        jtag_write(dm::SBAddress1, '0);

                    do begin
                            jtag_write(dm::SBAddress0, CoreStatusAddr);
                        $display("@%t | [JTAG] Simulation check attempt %0d", $time, attempt);

                    jtag_dbg.wait_idle(20);
            jtag_dbg.read_dmi_exp_backoff(dm::SBData0, exit_code);

        attempt++;
        if (attempt >= max_attempts) begin
                    $error("@%t | [JTAG] Timeout waiting for end of computation", $time);
                break;
        end
    end while (exit_code == 0);
    $display("@%t | [JTAG] Simulation finished: return code 0x%0h", $time, exit_code);

endtask
//-------------------- counter & per-cycle dump --------------------
string dump_dir = "scan_out";
integer clk_counter;

initial begin
  clk_counter = 0;
end

always @(posedge clk_i) begin
  string fname;
  integer fd_cycle;
  integer i;

  if (fetch_en_i) begin
    // ---------- Create unique file for each cycle ----------
//    $sformat(fname, "cycle_%0d.txt", clk_counter);
    $sformat(fname, "%s/cycle_%0d.txt", dump_dir, clk_counter);
    fd_cycle = $fopen(fname, "w");
    if (fd_cycle == 0) begin
      $display("ERROR: cannot open %s", fname);
      $finish;
    end

    // ---------- Header ----------
    $fdisplay(fd_cycle,"------------------------------------------------------------\n\
Cycle #%0d (fetch_en=%0d)\n\
pc_if = %h\n\
pc_id = %h\n\
------------------------------------------------------------",
      clk_counter, fetch_en_i,
      tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.pc_if_i,
      tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.pc_id_i);

// ===========================================================
// 1. Dump IMEM (SRAM0)
// ===========================================================
$fdisplay(fd_cycle, "\n--- IMEM (sram0) contents ---");
for (i = 0; i < 128; i = i + 1) begin
  automatic logic [$bits(tb_chip.u_chip.i_croc_soc.i_croc.gen_sram_bank[0].i_sram.mem[i])-1:0] val_imem;
  val_imem = tb_chip.u_chip.i_croc_soc.i_croc.gen_sram_bank[0].i_sram.mem[i];
  $fdisplay(fd_cycle, "IMEM[%0d] = %b", i, val_imem);
end

// ===========================================================
// 2. Dump DMEM (SRAM1)
// ===========================================================
$fdisplay(fd_cycle, "\n--- DMEM (sram1) contents ---");
for (i = 0; i < 128; i = i + 1) begin
  automatic logic [$bits(tb_chip.u_chip.i_croc_soc.i_croc.gen_sram_bank[1].i_sram.mem[i])-1:0] val_dmem;
  val_dmem = tb_chip.u_chip.i_croc_soc.i_croc.gen_sram_bank[1].i_sram.mem[i];
  $fdisplay(fd_cycle, "DMEM[%0d] = %b", i, val_dmem);
end

// ===========================================================
// 3. Dump Ibex core internal state (GPRs)
// ===========================================================
$fdisplay(fd_cycle, "\n--- IBEX CORE STATE ---");
$fdisplay(fd_cycle, "--- GPRs (x0–x31) ---");
for (i = 0; i < 32; i = i + 1) begin
  automatic logic [$bits(tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.register_file_i.rf_reg[i])-1:0] val_gpr;
  val_gpr = tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.register_file_i.rf_reg[i];
  $fdisplay(fd_cycle, "x%0d = %b", i, val_gpr);
end

// ===========================================================
// IF STAGE
// ===========================================================
$fdisplay(fd_cycle, "\n--- IF STAGE ---");
$fdisplay(fd_cycle, "instr_rdata_alu_id_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_rdata_alu_id_o);
$fdisplay(fd_cycle, "instr_rdata_c_id_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_rdata_c_id_o);
$fdisplay(fd_cycle, "instr_rdata_id_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_rdata_id_o);
$fdisplay(fd_cycle, "pc_id_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.pc_id_o);
$fdisplay(fd_cycle, "instr_fetch_err_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_fetch_err_o);
$fdisplay(fd_cycle, "prefetch_buffer_i_fifo_i_valid_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.fifo_i.valid_q);
$fdisplay(fd_cycle, "instr_fetch_err_plus2_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_fetch_err_plus2_o);
$fdisplay(fd_cycle, "prefetch_buffer_i_fifo_i_rdata_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.fifo_i.rdata_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_fifo_i_err_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.fifo_i.err_q);
$fdisplay(fd_cycle, "illegal_c_insn_id_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.illegal_c_insn_id_o);
$fdisplay(fd_cycle, "instr_is_compressed_id_o_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_is_compressed_id_o);
$fdisplay(fd_cycle, "prefetch_buffer_i_fifo_i_instr_addr_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.fifo_i.instr_addr_q);
$fdisplay(fd_cycle, "instr_valid_id_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.instr_valid_id_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_stored_addr_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.stored_addr_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_fetch_addr_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.fetch_addr_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_branch_discard_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.branch_discard_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_rdata_outstanding_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.rdata_outstanding_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_discard_req_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.discard_req_q);
$fdisplay(fd_cycle, "prefetch_buffer_i_valid_req_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.if_stage_i.prefetch_buffer_i.valid_req_q);

// ===========================================================
// ID STAGE
// ===========================================================
$fdisplay(fd_cycle, "\n--- ID STAGE ---");
$fdisplay(fd_cycle, "id_fsm_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.id_fsm_q);
$fdisplay(fd_cycle, "controller_i_debug_mode_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.debug_mode_q);
$fdisplay(fd_cycle, "controller_i_exc_req_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.exc_req_q);
$fdisplay(fd_cycle, "controller_i_illegal_insn_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.illegal_insn_q);
$fdisplay(fd_cycle, "controller_i_ctrl_fsm_cs_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.ctrl_fsm_cs);
$fdisplay(fd_cycle, "controller_i_enter_debug_mode_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.enter_debug_mode_prio_q);
$fdisplay(fd_cycle, "controller_i_do_single_step_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.do_single_step_q);
$fdisplay(fd_cycle, "branch_jump_set_done_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.branch_jump_set_done_q);
$fdisplay(fd_cycle, "branch_set_raw_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.branch_set_raw_q);
$fdisplay(fd_cycle, "controller_i_store_err_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.store_err_q);
$fdisplay(fd_cycle, "controller_i_load_err_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.id_stage_i.controller_i.load_err_q);

// ===========================================================
// LSU
// ===========================================================
$fdisplay(fd_cycle, "\n--- LSU ---");
$fdisplay(fd_cycle, "rdata_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.rdata_q);
$fdisplay(fd_cycle, "addr_last_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.addr_last_q);
$fdisplay(fd_cycle, "lsu_err_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.lsu_err_q);
$fdisplay(fd_cycle, "ls_fsm_cs_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.ls_fsm_cs);
$fdisplay(fd_cycle, "data_we_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.data_we_q);
$fdisplay(fd_cycle, "data_type_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.data_type_q);
$fdisplay(fd_cycle, "rdata_offset_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.rdata_offset_q);
$fdisplay(fd_cycle, "data_sign_ext_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.data_sign_ext_q);
$fdisplay(fd_cycle, "handle_misaligned_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.load_store_unit_i.handle_misaligned_q);

// ===========================================================
// CSR
// ===========================================================
$fdisplay(fd_cycle, "\n--- CSR ---");
$fdisplay(fd_cycle, "mtval_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mtval_q);
$fdisplay(fd_cycle, "mepc_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mepc_q);
$fdisplay(fd_cycle, "mcause_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mcause_q);
$fdisplay(fd_cycle, "depc_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.depc_q);
$fdisplay(fd_cycle, "mscratch_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mscratch_q);
$fdisplay(fd_cycle, "dcsr_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.dcsr_q);
$fdisplay(fd_cycle, "dscratch0_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.dscratch0_q);
$fdisplay(fd_cycle, "dscratch1_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.dscratch1_q);
$fdisplay(fd_cycle, "minstret_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.minstret_raw);
$fdisplay(fd_cycle, "mtvec_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mtvec_q);
$fdisplay(fd_cycle, "mie_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mie_q);
$fdisplay(fd_cycle, "mcycle_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mhpmcounter[0]);
$fdisplay(fd_cycle, "mstatus_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mstatus_q);
$fdisplay(fd_cycle, "mcountinhibit_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.mcountinhibit_q);
$fdisplay(fd_cycle, "priv_lvl_q = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_core_wrap.i_ibex.cs_registers_i.priv_lvl_q);

// ===========================================================
// OBI
// ===========================================================
$fdisplay(fd_cycle, "\n--- OBI ---");
$fdisplay(fd_cycle, "croc_demux_sel_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_obi_demux.select_q);
$fdisplay(fd_cycle, "croc_demux_cnt_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_croc.i_obi_demux.i_counter.counter_q);
$fdisplay(fd_cycle, "user_demux_cnt_q_reg = %b", tb_chip.u_chip.i_croc_soc.i_user.i_obi_demux.i_counter.counter_q);
//============================================================
$fdisplay(fd_cycle, "\n--- rst ---");
$fdisplay(fd_cycle,"rst=%b",tb_chip.u_chip.i_croc_soc.i_rstgen.i_rstgen_bypass.synch_regs_q);
//===================
  $fdisplay(fd_cycle, "\n--- GPIO ---");                                                                                                                                                                    
  $fdisplay(fd_cycle, "gpio_en=%b",  tb_chip.u_chip.i_croc_soc.i_croc.i_gpio.i_reg_file.reg_q.en);
  $fdisplay(fd_cycle, "gpio_dir=%b", tb_chip.u_chip.i_croc_soc.i_croc.i_gpio.i_reg_file.reg_q.dir);                                                                                                         
  $fdisplay(fd_cycle, "gpio_out=%b", tb_chip.u_chip.i_croc_soc.i_croc.i_gpio.i_reg_file.reg_q.out); 

    // ---------- Close this cycle's file ----------
    $fclose(fd_cycle);
     //clk_counter++;
    // ---------- Stop after N cycles ----------
    if (clk_counter >= 190) begin
      $display("Reached 190 cycles — dumping complete.");
      $finish;
    end
    clk_counter++;
//    clk_counter <= clk_counter + 1;
  end
end


//-----------------------UART-------------------
typedef bit [ 7:0] byte_bt;
    localparam int unsigned UartDivisior = ClkFrequency / (UartBaudRate*16);
    localparam UartRealBaudRate = ClkFrequency / (UartDivisior*16);
    localparam time UartBaudPeriod = 1s/UartRealBaudRate;

    initial begin
        $display("ClkFrequency: %dMHz", ClkFrequency/1000_000);
        $display("UartRealBaudRate: %d", UartRealBaudRate);
    end

    localparam byte_bt UartDebugCmdRead  = 'h11;
    localparam byte_bt UartDebugCmdWrite = 'h12;
    localparam byte_bt UartDebugCmdExec  = 'h13;
    localparam byte_bt UartDebugAck      = 'h06;
    localparam byte_bt UartDebugEot      = 'h04;
    localparam byte_bt UartDebugEoc      = 'h14;

    logic   uart_reading_byte;

    initial begin
        uart_rx_i         = 1;
        uart_reading_byte = 0;
    end

    task automatic uart_read_byte(output byte_bt bite);
        // Start bit
        @(negedge uart_tx_o);
        uart_reading_byte = 1;
        #(UartBaudPeriod/2);
        // 8-bit byte
        for (int i = 0; i < 8; i++) begin
        #UartBaudPeriod bite[i] = uart_tx_o;
        end
        // Parity bit
        if(UartParityEna) begin
        bit parity;
        #UartBaudPeriod parity = uart_tx_o;
        if(parity ^ (^bite))
            $error("[UART] - Parity error detected!");
        end
        // Stop bit
        #UartBaudPeriod;
        uart_reading_byte=0;
    endtask

    task automatic uart_write_byte(input byte_bt bite);
        // Start bit
        uart_rx_i = 1'b0;
        // 8-bit byte
        for (int i = 0; i < 8; i++)
        #UartBaudPeriod uart_rx_i = bite[i];
        // Parity bit
        if (UartParityEna)
        #UartBaudPeriod uart_rx_i = (^bite);
        // Stop bit
        #UartBaudPeriod uart_rx_i = 1'b1;
        #UartBaudPeriod;
    endtask

    initial begin
        static byte_bt uart_read_buf[$];
        byte_bt bite;

        @(posedge fetch_en_i);
        uart_read_buf.delete();
        forever begin
            uart_read_byte(bite);

            if (bite == "\n" || uart_read_buf.size() > 80) begin
                 if (uart_read_buf.size() > 0) begin
                    automatic string uart_str = "";
                    foreach (uart_read_buf[i]) begin
                        uart_str = {uart_str, uart_read_buf[i]};
                    end

                    $display("@%t | [UART] %s", $time, uart_str);
                    uart_read_buf.push_back(bite);
                    $display("@%t | [UART] raw: %p", $time, uart_read_buf);

                end else begin
                    $display("@%t | [UART] ???", $time);
                end

                uart_read_buf.delete();
            end else begin
                uart_read_buf.push_back(bite);
            end
        end
    end
//---------------------scan chain-----------------
    integer fd;

    logic [scan_bits-1:0] scan_out_reg;

    always @(posedge clk_i) begin
    if (scan_mode_i) begin
        //$display("clock going high");
        scan_out_reg = { scan_out_reg[scan_bits-2:0], tdo_o };
        tdi_i = tdo_o;
    end
    end

    task dump_scan_chain;
        integer i;
        begin


            for (i = 0; i < scan_bits; i = i + 1) begin
                @(posedge clk_i);
            end

            fd = $fopen("scan_dump.txt", "w");
            $fdisplay(fd, "%b", scan_out_reg);

        end
    endtask

//-----------------DUT------------------
    chip u_chip (
      .top_0   (clk_i),
      .top_1   (rst_ni),
      .top_2   (scan_en_i),
      .top_3   (scan_mode_i),
      .top_4   (ref_clk_i),
      .top_5   (tdi_i),
      .top_6   (tdo_o),
      .top_7   (),
      .top_8   (),
      .top_9   (),
      .top_10  (),
      .top_11  (),

      .left_0  (jtag_tck_i),
      .left_1  (jtag_trst_ni),
      .left_2  (jtag_tms_i),
      .left_3  (jtag_tdi_i),
      .left_4  (uart_rx_i),
      .left_5  (fetch_en_i),
      .left_6  (),
      .left_7  (),
      .left_8  (),
      .left_9  (),
      .left_10 (),
      .left_11 (),

      .bottom_0   (jtag_tdo_o),
      .bottom_1   (uart_tx_o),
      .bottom_2   (status_o),
      .bottom_3   (gpio_o[0]),
      .bottom_4   (gpio_o[1]),
      .bottom_5   (ro_q),
      .bottom_6   (ro_chain_q),
      .bottom_7   (ro_data_q[0]),
      .bottom_8   (ro_data_q[1]),
      .bottom_9   (ro_data_q[2]),
      .bottom_10  (ro_data_q[3]),

      .right_0   (ro_clk),
      .right_1   (ro_rst_n),
      .right_2   (ro_ce_n),
      .right_3   (ro_en),
      .right_4   (ro_chain_i),
      .right_5   (ro_data_d[0]),
      .right_6   (ro_data_d[1]),
      .right_7   (ro_data_d[2]),
      .right_8   (ro_data_d[3]),
      .right_9   (),
      .right_10  (),
      .right_11  ()
    );

assign gpio_i = gpio_out_en_o ? gpio_o : '0;

//--------------------test bench ----------------
string hexfile;
initial begin
    if ($value$plusargs("binary=%s", hexfile)) begin
        $display("Running program: %s", hexfile);
    end else begin
        $display("No binary path provided. Running helloworld.");
        hexfile = "../sw/bin/helloworld.hex";
    end
end


logic [31:0] tb_data;

initial begin
  $timeformat(-9, 0, "ns", 12);

  `ifdef TRACE_WAVE
    `ifndef SCANDUMP
      $dumpfile("tb_chip.vcd");
      $dumpvars(0, tb_chip);
    `endif
  `endif

  `ifdef GATELEVEL
      $sdf_annotate(`SDFFILE, u_chip, , , "MAXIMUM");
  `endif

  // ---------------- Initialization ----------------
  uart_rx_i   = 1'b0;
  fetch_en_i  = 1'b0;
  scan_en_i   = 1'b0;
  scan_mode_i = 1'b0;


  #ClkPeriod;

  jtag_init();
  jtag_write_reg32(croc_pkg::SramBaseAddr, 32'h12345678, 1'b1);

//  if (!$value$plusargs("binary=%s", hexfile)) begin
//    $fatal("HEXFILE argument not provided. Use +HEXFILE=../sw/bin/helloworld.hex");
//  end

  $dumpoff;

  init_sram_zero();	

  jtag_load_hex(hexfile);
  $dumpon;

  $display("@%t | [CORE] Start fetching instructions", $time);
  fetch_en_i = 1'b1;

 // $display("@%t | [CORE] Wait for end of code...", $time);

  // give ample time for the program to finish execution
  #40000;   // 

  // ---------------- Scan Chain Dump ----------------
  //jtag_halt();
  //$display("@%t | [CORE] Dumping scan chain...", $time);

  //fetch_en_i  = 1'b0;
  //scan_mode_i = 1'b1;
  //scan_en_i   = 1'b1;

  //$dumpoff;
  //dump_scan_chain();
  //$dumpon;   //

  //scan_mode_i = 1'b0;
  //scan_en_i   = 1'b0;
  //fetch_en_i  = 1'b1;

  //jtag_resume();
  $finish;
end

task init_sram_zero;
  integer i;
  for (i = 0; i < 128; i = i + 1) begin
    u_chip.i_croc_soc.i_croc.gen_sram_bank[0].i_sram.mem[i] = 32'h00000000;
    u_chip.i_croc_soc.i_croc.gen_sram_bank[1].i_sram.mem[i] = 32'h00000000;
  end
endtask

endmodule
