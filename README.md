# TI99/2

Main repository is here: 
[TI99/2](https://gitlab.com/pnru/ti99/tree/master/ti99_2)

here are only additional files for easier compling ti99_2 on my
trellis installation and some helper files for ESP32 standalone
operation to load bistream and run the hexbus server

create directory /sd/hexbus and upload "hexbus.py"

    ftp> mkdir sd
    ftp> mkdir sd/hexbus
    ftp> put hexbus.py

from python console start the server

    >>> import ti99

Connect PS/2 keyboard to US2 port over OTG adapter and try
load/save from TI99/2 with file names prefixed with "HEXBUS.1."

    >10 PRINT 1234
    >LIST
     10 PRINT 1234

    >RUN
    1234
    >SAVE HEXBUS.1.PRINT1234
    >NEW
    >LIST
     * CAN'T DO THAT
    >OLD HEXBUS.1.PRINT1234
    >LIST
     10 PRINT 1234
