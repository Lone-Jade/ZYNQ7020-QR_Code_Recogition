set r4_rtl [file join $qr_dir roi_selection rtl]
foreach name {r4_camera_fork.v r4_display_osd.v r4_display_memory_guard.v r4_scan_identity.v r4_font.vh} {add_files -norecurse [file join $r4_rtl $name]}
set_property include_dirs [concat [get_property include_dirs [current_fileset]] [list $r4_rtl]] [current_fileset]
add_files -norecurse [file join $qr_dir .. desktop r4_hdmi_rgb.v]
create_bd_cell -type module -reference r4_display_osd display_osd
create_bd_cell -type module -reference r4_hdmi_rgb display_rgb
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk_xbar "Auto"} [get_bd_intf_pins display_osd/S_AXI]
assign_bd_address -offset 0x43C40000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins display_osd/S_AXI]] -force
connect_bd_net [get_bd_pins pixel_clock/clk_out1] [get_bd_pins display_osd/pixel_clk]
connect_bd_net [get_bd_pins pixel_reset/peripheral_aresetn] [get_bd_pins display_osd/pixel_resetn]
foreach {from to} {raw_rgb pixel_rgb raw_x pixel_x raw_y pixel_y raw_de pixel_de raw_hs pixel_hs raw_vs pixel_vs} {connect_bd_net [get_bd_pins video_timing/$from] [get_bd_pins display_osd/$to]}
foreach {from to} {out_rgb rgb out_de de out_hs hs out_vs vs} {connect_bd_net [get_bd_pins display_osd/$from] [get_bd_pins display_rgb/$to]}
foreach pin {hdmi_d hdmi_de hdmi_hs hdmi_vs} {make_bd_pins_external [get_bd_pins display_rgb/$pin];set_property name $pin [get_bd_ports ${pin}_0]}
foreach {name direction width endpoint} {
 r4_display_enable O 1 capture_enable r4_source_epoch O 32 source_epoch r4_display_clear O 1 clear_toggle
 r4_display_fault I 1 display_fault r4_source_frames I 32 source_frames r4_display_frames I 32 display_frames
 r4_display_drops I 32 display_drops r4_qr_drops I 32 qr_drops
} {
 if {$width==1} {create_bd_port -dir $direction $name} else {create_bd_port -dir $direction -from [expr {$width-1}] -to 0 $name}
 connect_bd_net [get_bd_ports $name] [get_bd_pins display_osd/$endpoint]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 display_camera_cdc
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.TUSER_WIDTH {65} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1}] [get_bd_cells display_camera_cdc]
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 display_video
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TUSER_WIDTH {65}] [get_bd_intf_ports display_video]
connect_bd_intf_net [get_bd_intf_ports display_video] [get_bd_intf_pins display_camera_cdc/S_AXIS]
create_bd_port -dir I -type clk -freq_hz 100000000 display_video_aclk
set_property CONFIG.ASSOCIATED_BUSIF {display_video} [get_bd_ports display_video_aclk]
create_bd_port -dir I -type rst display_video_aresetn
set_property CONFIG.POLARITY {ACTIVE_LOW} [get_bd_ports display_video_aresetn]
connect_bd_net [get_bd_ports display_video_aclk] [get_bd_pins display_camera_cdc/s_axis_aclk]
connect_bd_net [get_bd_ports display_video_aresetn] [get_bd_pins display_camera_cdc/s_axis_aresetn]
connect_bd_net $base_fclk [get_bd_pins display_camera_cdc/m_axis_aclk]
connect_bd_net $base_reset_pin [get_bd_pins display_camera_cdc/m_axis_aresetn]
# The high TUSER bits carry identity through the CDC. VDMA receives SOF only.
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 display_sof
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {2} CONFIG.M_TDATA_NUM_BYTES {2} CONFIG.S_TUSER_WIDTH {65} CONFIG.M_TUSER_WIDTH {1} CONFIG.S_HAS_TLAST {1} CONFIG.M_HAS_TLAST {1} CONFIG.S_HAS_TKEEP {1} CONFIG.M_HAS_TKEEP {1} CONFIG.TUSER_REMAP {tuser[0:0]}] [get_bd_cells display_sof]
connect_bd_net $base_fclk [get_bd_pins display_sof/aclk]
connect_bd_net $base_reset_pin [get_bd_pins display_sof/aresetn]
connect_bd_intf_net [get_bd_intf_pins display_camera_cdc/M_AXIS] [get_bd_intf_pins display_sof/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins display_sof/M_AXIS] [get_bd_intf_pins display_vdma/S_AXIS_S2MM]
set_property CONFIG.NUM_PORTS {7} [get_bd_cells interrupts]
connect_bd_net [get_bd_pins display_vdma/s2mm_introut] [get_bd_pins interrupts/In6]
assign_bd_address -offset 0 -range 0x40000000 -target_address_space [get_bd_addr_spaces display_vdma/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force

connect_bd_net [get_bd_ports display_video_aclk] [get_bd_pins display_osd/cam_clk]
connect_bd_net [get_bd_ports display_video_aresetn] [get_bd_pins display_osd/cam_resetn]
create_bd_cell -type module -reference r4_display_memory_guard display_guard
connect_bd_net $base_fclk [get_bd_pins display_guard/clk]
connect_bd_net $base_reset_pin [get_bd_pins display_guard/resetn]
# Toggle-to-pulse conversion in the guard's own clock domain.
foreach pin {base0 base1 base2 tag0 tag1 tag2 valid_slots memory_errors committed_frames} {
 set guardpin $pin
 if {$pin eq "memory_errors"} {set guardpin errors}
 if {$pin eq "committed_frames"} {set guardpin completed_frames}
 connect_bd_net [get_bd_pins display_osd/$pin] [get_bd_pins display_guard/$guardpin]
}
connect_bd_net [get_bd_pins display_osd/clear_toggle] [get_bd_pins display_guard/clear]
create_bd_cell -type module -reference r4_scan_identity display_identity
connect_bd_net $base_fclk [get_bd_pins display_identity/aclk]
connect_bd_net $base_reset_pin [get_bd_pins display_identity/aresetn]
connect_bd_net [get_bd_pins pixel_clock/clk_out1] [get_bd_pins display_identity/pixel_clk]
connect_bd_net [get_bd_pins pixel_reset/peripheral_aresetn] [get_bd_pins display_identity/pixel_resetn]
connect_bd_net [get_bd_pins video_timing/raw_frame_start] [get_bd_pins display_identity/pixel_start]
connect_bd_net [get_bd_pins display_osd/clear_toggle] [get_bd_pins display_identity/clear_toggle]
connect_bd_net [get_bd_pins display_guard/scan_tag] [get_bd_pins display_identity/fetched_tag]
connect_bd_net [get_bd_pins display_guard/read_tag_push] [get_bd_pins display_identity/push]
connect_bd_net [get_bd_pins display_identity/scan_tag] [get_bd_pins display_osd/scan_tag]
connect_bd_net [get_bd_pins display_identity/unique_frames] [get_bd_pins display_osd/unique_frames]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 display_fault_or
set_property -dict [list CONFIG.C_OPERATION {or} CONFIG.C_SIZE {1}] [get_bd_cells display_fault_or]
connect_bd_net [get_bd_pins display_guard/fault] [get_bd_pins display_fault_or/Op1]
connect_bd_net [get_bd_pins display_identity/fault] [get_bd_pins display_fault_or/Op2]
connect_bd_net [get_bd_pins display_fault_or/Res] [get_bd_pins display_osd/memory_fault]
connect_bd_net [get_bd_pins display_guard/safe_video] [get_bd_pins display_osd/safe_video]
foreach {guardpin axis} {stream_user tuser stream_valid tvalid stream_ready tready} {
 connect_bd_net [get_bd_pins display_camera_cdc/m_axis_$axis] [get_bd_pins display_sof/s_axis_$axis] [get_bd_pins display_guard/$guardpin]
}
foreach {guardpin vpin mpin} {
 awaddr m_axi_s2mm_awaddr S01_AXI_awaddr awlen m_axi_s2mm_awlen S01_AXI_awlen
 awsize m_axi_s2mm_awsize S01_AXI_awsize awvalid m_axi_s2mm_awvalid S01_AXI_awvalid
 awready m_axi_s2mm_awready S01_AXI_awready bresp m_axi_s2mm_bresp S01_AXI_bresp
 bvalid m_axi_s2mm_bvalid S01_AXI_bvalid bready m_axi_s2mm_bready S01_AXI_bready
 araddr m_axi_mm2s_araddr S00_AXI_araddr arvalid m_axi_mm2s_arvalid S00_AXI_arvalid
 arready m_axi_mm2s_arready S00_AXI_arready
} {
 connect_bd_net [get_bd_pins display_vdma/$vpin] [get_bd_pins display_memory/$mpin] [get_bd_pins display_guard/$guardpin]
}
