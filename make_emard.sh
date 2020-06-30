#!/bin/sh -e

# Build TI-99/2 system for ULX3S board
# 12/25/45/85
FPGA_SIZE=12

# https://github.com/YosysHQ/yosys
#YOSYS=/mt/scratch/tmp/openfpga/yosys/yosys
YOSYS=yosys
# https://github.com/YosysHQ/nextpnr
#NEXTPNR_ECP5=/mt/scratch/tmp/openfpga/nextpnr/nextpnr-ecp5
NEXTPNR_ECP5=nextpnr-ecp5
# https://github.com/SymbiFlow/prjtrellis
TRELLIS=/mt/scratch/tmp/openfpga/prjtrellis
TRELLISDB=$TRELLIS/database
LIBTRELLIS=$TRELLIS/libtrellis

#ECPPLL=$TRELLIS/libtrellis/ecppll
#ECPPACK=$TRELLIS/libtrellis/ecppack
ECPPACK=ecppack

# synthesise design
# generates warnings, but these are okay
$YOSYS -q -p "synth_ecp5 -json vdp.json" \
  evmvdp.v \
  ecp5pll.sv \
  ti99/ti99_2/tiram.v \
  ti99/ti99_2/tirom.v \
  ti99/ti99_2/tms99000.v \
  ti99/ti99_2/ps2kb.v \
  ti99/ti99_2/vdp99_2.v \
  ti99/ti99_2/hdmi.v \
  ti99/ti99_2/hexbus.v

# place & route
# assumes 25F device
$NEXTPNR_ECP5 --${FPGA_SIZE}k --package CABGA381 --json vdp.json --lpf ulx3s.lpf --lpf-allow-unconstrained --textcfg vdp.cfg

# pack bitstream
#LANG=C LD_LIBRARY_PATH=$LIBTRELLIS $ECPPACK --db $TRELLISDB --compress vdp.cfg vdp.bit --idcode 0x21111043
LANG=C $ECPPACK --compress vdp.cfg vdp.bit

# send to ULX3S board (store in configuration RAM)
ujprog vdp.bit

# rm vdp.*
