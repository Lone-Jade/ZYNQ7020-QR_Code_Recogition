import re
def make_device_tree(s,fitness=False,r3=False,capture_layout="gray",capture_axis_bits=8):
 start=s.index('qr-capture@43c00000');end=s.index('\n\t\t};',start)
 sub=s[start:end];assert 'reg = <0x43c00000 0x10000>;' in sub
 sub=sub.replace('reg = <0x43c00000 0x10000>;','reg = <0x43c00000 0x10000 0x43c20000 0x10000>;\n\t\t\treg-names = "capture", "timing";')
 s=s[:start]+sub+s[end:]
 if r3:
  if capture_layout=='color':
   s=s.replace('compatible = "alinx,ax7021b-qr-capture";', 'compatible = "qrproject,c04-qr-capture-r3";')
   assert 'compatible = "qrproject,c04-qr-capture-r3";' in s
 if capture_axis_bits==32:
  channel=s.index('dma-channel@43010000');end=s.index('\n\t\t\t};',channel)
  node=s[channel:end];assert node.count('xlnx,datawidth = <0x08>;')==1
  s=s[:channel]+node.replace('xlnx,datawidth = <0x08>;','xlnx,datawidth = <0x20>;')+s[end:]
 if fitness:
  assert not re.search(r"phandle\s*=\s*<0x80>",s), "Fitness phandle already in use"
  start=s.index('\n\t\tqr-capture@43c00000')
  s=s[:start]+'''
        fitness-reset@41230000 {
            compatible = "xlnx,axi-gpio-2.0", "xlnx,xps-gpio-1.00.a";
            reg = <0x41230000 0x10000>; clocks = <1 15>;
            clock-names = "s_axi_aclk"; gpio-controller; #gpio-cells = <2>;
            xlnx,gpio-width = <1>; xlnx,all-outputs = <1>; phandle = <0x80>;
        };
        fitness@43c10000 {
            compatible = "qrproject,c04-fitness-v1";
            reg = <0x43c10000 0x10000 0x43c30000 0x10000>;
            reg-names = "control", "profile";
            clocks = <1 15>; clock-names = "s_axi_aclk";
            interrupt-parent = <4>; interrupts = <0 34 4>;
            reset-gpios = <0x80 0 0>;
        };
'''+s[start:]
  if r3:s=s.replace('compatible = "qrproject,c04-fitness-v1";', 'compatible = "qrproject,c04-fitness-v2";')
 return s

