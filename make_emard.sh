#!/bin/sh -e

# Build TI-99/2 system for ULX3S board

# https://github.com/YosysHQ/yosys
YOSYS=/mt/scratch/tmp/openfpga/yosys/yosys
# https://github.com/YosysHQ/nextpnr
NEXTPNR_ECP5=/mt/scratch/tmp/openfpga/nextpnr/nextpnr-ecp5
# https://github.com/SymbiFlow/prjtrellis
TRELLIS=/mt/scratch/tmp/openfpga/prjtrellis

ECPPLL=$TRELLIS/libtrellis/ecppll
ECPPACK=$TRELLIS/libtrellis/ecppack
TRELLISDB=$TRELLIS/database
LIBTRELLIS=$TRELLIS/libtrellis

# synthesise design
# generates warnings, but these are okay
$YOSYS -q -p "synth_ecp5 -json vdp.json" tiram.v tirom.v evmvdp.v tms99000.v ps2kb.v vdp99_2.v hdmi.v hexbus.v

# place & route
# assumes 25F device
$NEXTPNR_ECP5 --25k --package CABGA381 --json vdp.json --lpf ulx3s.lpf --lpf-allow-unconstrained --textcfg vdp.cfg

# pack bitstream
# idcode only needed when sending bitstream to 12F devices
LANG=C LD_LIBRARY_PATH=$LIBTRELLIS $ECPPACK --db $TRELLISDB --compress vdp.cfg vdp.bit --idcode 0x21111043

# send to ULX3S board (store in configuration RAM)
ujprog vdp.bit
