from machine import UART, Pin
import uselect
import utime

class Hexbus:

  def init(self):
    self.u2 = UART(2, 115200)
    self.poll = uselect.poll()
    self.poll.register(self.u2, uselect.POLLIN)
    self.dbg = False
    self.gpio0 = Pin(0, Pin.IN)

  def work(self):
    while 1:
      t = utime.time()
      while self.u2.any()<10:
        self.poll.poll(20)
        if self.gpio0.value() < 1: raise Exception("Button")
        #if (utime.time()-t) > 600: raise Exception("Timeout")
      self.t1 = utime.ticks_us()
      self.do_msg()

  def rd_byte(self):
    # get next byte
    if self.u2.any()==0: self.poll.poll(20)
    if self.u2.any()==0: raise Exception("Missing data")
    b = self.u2.read(1)
    return b[0]
    
  def getlen(self, d):
    # get length of d, zero for None
    if isinstance(d, bytes):
      return len(d)
    return 0
     
  def do_msg(self):
    # check for new msg signature (= BAV went low)
    if self.rd_byte()!=0xc1: raise Exception("Expected BAV start")
    
    # read first 9 bytes = command header
    self.dev = self.rd_byte()
    self.cmd = self.rd_byte()
    self.lun = self.rd_byte()
    self.rec_no = self.rd_byte() + 256 * self.rd_byte()
    self.buflen = self.rd_byte() + 256 * self.rd_byte()
    self.datlen = self.rd_byte() + 256 * self.rd_byte()
    
    # read data portion
    data = self.u2.read(self.datlen);
    while self.getlen(data) < self.datlen:
      self.poll.poll(10)
      if self.u2.any()==0: raise Exception("Data too late")
      data = data + self.u2.read(self.datlen - self.getlen(data))
    self.data = data

    # handle commands
    if self.cmd==0xff:
      #reset - do nothing
      pass
      
    elif self.cmd==0x00:
      #open - accept and set buf size to 128
      if len(data)>3:
        name = data[3:].decode()
      else:
        name = "NONE"
      mode = ["a","r","w","r+"][data[2] // 64]
      if data[2] & 8:
        mode = mode + "b"
      self.mod = data[2]
      print(name)
      print(mode)
      self.fds = open("/sd/hexbus/"+name, mode)
      self.u2.write(b'\xc3\x04\x00\x80\x00')
      self.u2.write(self.rec_no.to_bytes(2,"little"))
      self.u2.write(b'\x00')

    elif self.cmd==0x01:
      #close - accept
      self.u2.write(b'\xc3\x00\x00\x00')
      self.fds.close()

    elif self.cmd==0x03:
      # read - get data and accept
      if self.mod & 8:
        rec = self.fds.read(128)
      else:
        rec = self.fds.readline()[0:-1]
      self.u2.write(b'\xc3')
      self.u2.write(len(rec).to_bytes(2,"little"))
      self.u2.write(rec)
      self.u2.write(b'\x00')

    elif self.cmd==0x04:
      #write - print data and accept
      self.u2.write(b'\xc3\x00\x00\x00')
      self.fds.write(data)
      if (self.mod & 8)==0: self.fds.write("\n")

    elif self.cmd==0x1a:
      #save - accept, get name & data, save in file
      self.u2.write(b'\xc3\x00\x00\x00')
      namlen = self.datlen - self.buflen
      name = data[0:namlen-1].decode()
      fd = open("/sd/hexbus/"+name,"wb")
      fd.write(data[namlen:])
      fd.close()

    elif self.cmd==0x19:
      #load - accept, get name, get data from file, send
      name = data.decode()
      fd = open("/sd/hexbus/"+name,"rb")
      old = fd.read()
      size = len(old)
      self.u2.write(b'\xc3')
      self.u2.write(size.to_bytes(2,"little"))
      self.u2.write(old)
      self.u2.write(b'\x00')
      fd.close()

    else:
      # any other: print data & accept
      self.u2.write(b'\xc3')
      self.u2.write(b'\x00')
      self.u2.write(b'\x00')
      self.u2.write(b'\x00')

    self.t = utime.ticks_us() - self.t1

    # wait for BAV to go high, must follow within 20 ms
    while self.u2.any()<1:
      self.poll.poll(1)
    #if self.u2.any()<2: raise Exception("Bus timeout")
    #if self.rd_byte()!=0xc2: raise Exception("Expected BAV end")
    self.u2.read(1)
    
    # report if needed
    if self.dbg:
      print("dev=0x%02x" % self.dev)
      print("cmd=0x%02x" % self.cmd)
      print("lun=0x%02x" % self.lun)
      print("rec_no: %d" % self.rec_no)
      print("buflen: %d" % self.buflen)
      print("datlen: %d" % self.datlen)
      print("data:")
      print(data)
      print("---")
      print(self.t)
      print("===")      
    return
