from paths import PROJECT,tool
import sys
from pathlib import Path
"""R4 exclusive display ownership on the retained matched C04 device tree."""
from ac_package_boot import make_device_tree as c04_tree

def span(text,name):
 start=text.index(name+' {');opening=text.index('{',start);depth=1;i=opening+1
 while depth:
  if text[i]=='{':depth+=1
  elif text[i]=='}':depth-=1
  i+=1
 assert text[i]==';'
 return start,i+1

def make_device_tree(text):
 s=c04_tree(text,fitness=True,r3=True,capture_layout='gray',capture_axis_bits=32)
 assert s.count('compatible = "alinx,ax7021b-qr-capture";')==1
 s=s.replace('compatible = "alinx,ax7021b-qr-capture";','compatible = "xiwei,c04-qr-capture-r4";')
 start,end=span(s,'dma@43000000')
 s=s[:start]+'''dma@43000000 {
            compatible = "xiwei,c04-camera-display-r4";
            reg = <0x43000000 0x10000 0x43c40000 0x10000>;
            reg-names = "vdma", "osd";
            interrupt-parent = <4>;
            interrupts = <0 29 4 0 35 4>;
            interrupt-names = "read", "write";
            clocks = <1 15>; clock-names = "video";
            hdmi-i2c = <0x3a>;
            hdmi-reset-gpios = <0x17 0 1>;
            phandle = <0x16>;
        };'''+s[end:]
 start,end=span(s,'hdmi@39');s=s[:start]+'''hdmi@39 {
                compatible = "alinx,ax7021b-hdmi-fb";
                reg = <0x39>;
                status = "disabled";
            };'''+s[end:]
 assert 'dma-channel@43000000' not in s
 assert 'dmas = <0x16' not in s
 assert s.count('0x43c40000')==1
 # Do not remove capture VDMA's provider; it still owns HP1 and three QR slots.
 assert 'dma-channel@43010000' in s and 'xiwei,c04-fitness-v2' in s
 return s
