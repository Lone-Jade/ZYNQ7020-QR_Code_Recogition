from paths import PROJECT,tool
import sys
from pathlib import Path
"""Fail before synthesis if passive taps detach real AXI/AXIS endpoints."""
import re,json

def verify(work):
 path=work/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.gen/sources_1/bd/system/synth/system.v'
 hdl=path.read_text()
 def block(instance):
  m=re.search(r'\b'+instance+r'\s*\n?\s*\((.*?)\);',hdl,re.S);assert m,instance;return m[1]
 def net(instance,pin):
  m=re.search(r'\.'+pin+r'\(([^)]+)\)',block(instance));assert m,(instance,pin,'disconnected')
  s=re.sub(r'\[[^]]+\]','',m[1]);assert "'" not in s,(instance,pin,'constant');return s
 pairs=[('awaddr','m_axi_s2mm_awaddr','S01_AXI_awaddr'),('awlen','m_axi_s2mm_awlen','S01_AXI_awlen'),('awsize','m_axi_s2mm_awsize','S01_AXI_awsize'),('awvalid','m_axi_s2mm_awvalid','S01_AXI_awvalid'),('awready','m_axi_s2mm_awready','S01_AXI_awready'),('bresp','m_axi_s2mm_bresp','S01_AXI_bresp'),('bvalid','m_axi_s2mm_bvalid','S01_AXI_bvalid'),('bready','m_axi_s2mm_bready','S01_AXI_bready'),('araddr','m_axi_mm2s_araddr','S00_AXI_araddr'),('arvalid','m_axi_mm2s_arvalid','S00_AXI_arvalid'),('arready','m_axi_mm2s_arready','S00_AXI_arready')]
 checked={}
 for tap,vdma,memory in pairs:
  n=net('display_guard',tap);assert n==net('display_vdma',vdma)==net('display_memory',memory),(tap,'AXI tap detached the bus');checked[tap]=n
 for tap,field in [('stream_user','tuser'),('stream_valid','tvalid'),('stream_ready','tready')]:
  n=net('display_guard',tap);assert n==net('display_camera_cdc','m_axis_'+field)==net('display_sof','s_axis_'+field),(tap,'AXIS tap detached the bus');checked[tap]=n
 for instance,pin in [('display_vdma','s_axis_s2mm_tdata'),('display_sof','m_axis_tdata')]:
  assert net(instance,pin)=='display_sof_M_AXIS_TDATA'
 module_path=work/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.gen/sources_1/bd/system/ip/system_display_vdma_0/system_display_vdma_0.xci'
 # Actual width is also checked from exported HWH after implementation.
 assert not re.search(r'Width mismatch[^\n]*display_vdma/s_axis_s2mm', (work/'create.stdout').read_text())
 (work/'r4_bus_bindings.json').write_text(json.dumps(dict(passed=True,connections=checked,generated_hdl=str(path)),indent=2)+'\n')
 return checked
