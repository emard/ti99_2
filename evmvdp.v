module sys
(
  input  wire clk_25mhz,
  
  output wire [3:0] gpdi_dp, gpdi_dn,

  output wire usb_fpga_pu_dp, usb_fpga_pu_dn,
  input  wire usb_fpga_dp, usb_fpga_dn,

  output wire wifi_gpio0,
  output wire wifi_gpio16, // RX input on ESP32
  input  wire wifi_gpio17, // TX output on ESP32
  output wire wifi_gpio26,      // wifi_gpio5 = CTS input on ESP32

  output wire ftdi_rxd, // FTDI receives
  input  wire ftdi_txd, // FTDI transmits

  input  wire [6:0] btn,
  output wire [7:0] led

`ifdef __ICARUS__
  , input  wire reset, vint
`endif
);

  assign wifi_gpio0  = btn[0];
//  assign wifi_gpio26 = 1'b1;
  
  assign ftdi_rxd = wifi_gpio16 & wifi_gpio17; // echo ESP32 to FTDI, should be half duplex

  // clock generation
  //
  wire pll_250mhz, pll_125mhz, pll_25mhz;

`ifdef __ICARUS__
  assign pll_250mhz = 0;
  assign pll_125mhz = 0;
  assign pll_25mhz  = clk_25mhz;
`else
  clk_25_250_125_25 clk_pll (
    .clki(clk_25mhz),
    .clko(pll_250mhz),
    .clks1(pll_125mhz),
    .clks2(pll_25mhz)
  );
`endif

`ifndef __ICARUS__
  // reset for 255 clocks
  reg [7:0] ctr = 0;
  always @(posedge clk_25mhz) if (reset) ctr <= ctr+1;
  wire reset = !&ctr;
`endif

  // The 99/2 VDP circuit + HDMI encoder
  //
  wire [15:0] mab, vab, cab, rab; // memory, video and CPU address bus
  wire  [7:0] vdb_in;
`ifdef __ICARUS__
  wire vma, hold;
`else
  wire vma, hold, vint;
`endif
  wire vde, hsyn, vsyn, video, viden;
  wire [7:0] v8 = ~{8{video}}; // expand VDP video into 8 bits

`ifdef __ICARUS__
  vdp99_2  vdp(1'd0, vde, hsyn, vsyn, video, vab, vdb_in, vma, hold, viden, /*vint*/);
`else
  vdp99_2  vdp(pll_25mhz, vde, hsyn, vsyn, video, vab, vdb_in, vma, hold, viden, vint);
`endif
  HDMI_out out(pll_25mhz, pll_125mhz, v8, v8, v8, vde, hsyn, vsyn, gpdi_dp, gpdi_dn);

  // Basic CPU/RAM/ROM circuit
  //
  wire rd, wr;
  wire [15:0] db_out, db_in, rom_o, ram_o;
  wire nRAMCE = !mab[15];
  wire nROMCE =  mab[15];

  wire cruout, cruclk;
  reg  cruin;
  wire [3:0] bst;

  wire int, iaqs;
  wire nmi = 0, ready = 1;

  tms99000 cpu(pll_25mhz, reset, cab, db_in, db_out, rd, wr, ready, iaqs, /*as*/, int, 4'd4, nmi, cruin, cruout, cruclk, hold, bst);
  RAM      ram(pll_25mhz, nRAMCE, !wr, mab[14:1], db_out, ram_o);
  ROM      rom(pll_25mhz, nROMCE,      rab[14:1], rom_o);

  /* Debug trap
  reg [15:0] ins_ab;
  wire check = (cab==16'he9cc || cab==16'he9ce) && wr;
  always @(posedge pll_25mhz) begin
    if (iaqs) ins_ab <= cab;
    if (check) begin
      $display("trap at ins %h, adr %h, val %h\n", ins_ab, cab, db_out);
    end
  end
  */
  
  // Bus multiplexers
  //
  assign mab    = (vma) ? vab : cab;
  assign db_in  = (nROMCE) ? ram_o : rom_o;
  assign vdb_in = (vab[0]) ? db_in[7:0] : db_in[15:8]; // big endian
  
  // ROM bank switching
  wire A13 = (mab[14]) ? s[0] : mab[13];
  assign rab = { 1'b0, mab[14], A13, mab[12:0] };
  
  // 9995 specifics: flag register and INT4 latch
  //
  localparam inta = 4'b0101;
  reg  int4  = 0;
  
  always @(posedge pll_25mhz) begin
    if (vint) int4 <= 1;
    if (bst==inta && cab[5:2]==4'h4) int4 <= 0;
  end
  
  assign int = vint | int4;
  
  wire flgsel = (cab[15:5] == 11'h0F7); // CRU 1EE0-1EFF
  
  reg [15:0] flag = 0;
  
  always @(negedge cruclk)
  begin
    if (flgsel) flag[cab[4:1]] = cruout;
  end
  
  // HEXBUS
  //
  wire hexsel = (cab[15:4] == 12'hE80);
  wire hex_out;
  
  HEXBUS_992 hexbus(pll_25mhz, hexsel, cab[3:1], cruout, hex_out, cruclk, wifi_gpio16, wifi_gpio17, wifi_gpio26, led);

  // Keyboard I/O
  //
  wire kbdsel = (cab[15:4] == 12'hE00);
  wire kbdout;
  
  reg [7:0] s = 0;
  
  always @(negedge cruclk) begin
    if (kbdsel) s[cab[3:1]] = cruout;
  end
  
  assign viden = s[7];

  // enable pull ups on both D+ and D- on the USB / PS2 connector
  assign usb_fpga_pu_dp = 1'b1; 
  assign usb_fpga_pu_dn = 1'b1;
  
  ps2matrix kbd(pll_25mhz, usb_fpga_dp, usb_fpga_dn, s[5:0], cab[3:1], kbdout);

  // CRUIN multiplexer
  //
  always @(*)
  begin
    cruin = 1;
    if (flgsel)
      case (cab[4:1])
        4: cruin = int4;
        default: cruin = flag[cab[4:1]];
      endcase
    else if (kbdsel)
      cruin = kbdout;
    else if (hexsel)
      cruin = hex_out;
  end

  // ulx3s visual
  /*
  assign led[0] = hold;
  assign led[1] = vma;
  assign led[7:2] = 0;
  /**/
endmodule

`ifndef __ICARUS__

module clk_25_250_125_25(
  input clki, 
  output clks1,
  output clks2,
  output locked,
  output clko
);
  wire clkfb;
  wire clkos;
  wire clkop;
  (* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
  EHXPLLL #(
      .PLLRST_ENA("DISABLED"),
      .INTFB_WAKE("DISABLED"),
      .STDBY_ENABLE("DISABLED"),
      .DPHASE_SOURCE("DISABLED"),
      .CLKOP_FPHASE(0),
      .CLKOP_CPHASE(0),
      .OUTDIVIDER_MUXA("DIVA"),
      .CLKOP_ENABLE("ENABLED"),
      .CLKOP_DIV(2),
      .CLKOS_ENABLE("ENABLED"),
      .CLKOS_DIV(4),
      .CLKOS_CPHASE(0),
      .CLKOS_FPHASE(0),
      .CLKOS2_ENABLE("ENABLED"),
      .CLKOS2_DIV(20),
      .CLKOS2_CPHASE(0),
      .CLKOS2_FPHASE(0),
      .CLKFB_DIV(10),
      .CLKI_DIV(1),
      .FEEDBK_PATH("INT_OP")
    ) pll_i (
      .CLKI(clki),
      .CLKFB(clkfb),
      .CLKINTFB(clkfb),
      .CLKOP(clkop),
      .CLKOS(clks1),
      .CLKOS2(clks2),
      .RST(1'b0),
      .STDBY(1'b0),
      .PHASESEL0(1'b0),
      .PHASESEL1(1'b0),
      .PHASEDIR(1'b0),
      .PHASESTEP(1'b0),
      .PLLWAKESYNC(1'b0),
      .ENCLKOP(1'b0),
      .LOCK(locked)
    );
  assign clko = clkop;
endmodule

`endif