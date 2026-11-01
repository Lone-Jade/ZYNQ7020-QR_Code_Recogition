set qr_dir [file normalize [file dirname [info script]]]
set qr_project_root [file normalize [file join $qr_dir .. ..]]
set qr_repo_root [file normalize [file join $qr_project_root ..]]
set qr_ip_dir [file join $qr_project_root work ip qr_preprocess_camera]
if {[info exists ::env(AX7021B_QR_WORK_ROOT)]} {set qr_ip_dir [file join $::env(AX7021B_QR_WORK_ROOT) ip qr_preprocess_camera]}
if {![file exists [file join $qr_ip_dir component.xml]]} {error "Run package_qr_ip.tcl first: $qr_ip_dir"}

set_property ip_repo_paths [concat [get_property ip_repo_paths [current_project]] [list $qr_ip_dir]] [current_project]
update_ip_catalog
add_files -norecurse [file join $qr_repo_root qr_mainline_20261015 ov5640_Ethernet 800x600_48fps rtl ov5640_axis_capture.v]
add_files -norecurse [file join $qr_repo_root qr_diag45_20261018 qr_video_replay rtl qr_camera_frame_gate.v]
if {[info exists ::env(AX7021B_NO_PWM)] && $::env(AX7021B_NO_PWM) eq "1"} {
    add_files -norecurse [file join $qr_dir roi_selection rtl qr_desktop_top_no_pwm.v]
} else {add_files -norecurse [file join $qr_dir qr_desktop_top.v]}
add_files -norecurse [file join $qr_repo_root qr_diag45_20261018 qr_video_replay rtl qr_capture_timing.v]
add_files -fileset constrs_1 [file join $qr_dir camera.xdc]
set r4_cdc_file [file join $qr_dir r4_cdc.xdc]
add_files -fileset constrs_1 $r4_cdc_file
set_property USED_IN_SYNTHESIS false [get_files $r4_cdc_file]
set_property PROCESSING_ORDER LATE [get_files $r4_cdc_file]

set_property -dict [list CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_EN_RST1_PORT {1} \
    CONFIG.PCW_FPGA_FCLK1_ENABLE {1} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {80.000000} \
    CONFIG.PCW_FCLK_CLK1_BUF {TRUE}] [get_bd_cells ps7]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 camera_iic
foreach name {camera_reset camera_arm} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $name
    set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {1}] [get_bd_cells $name]
}
# Linebuffer depth is in AXIS words: 1024 * 4 bytes preserves the previous
# 4096-byte budget and covers one 3840-byte RGB565+Gray8 physical row.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 qr_capture_vdma
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_num_fstores {3} \
    CONFIG.c_include_mm2s {0} CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_s2mm_dre {0} CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_linebuffer_depth {1024} CONFIG.c_s2mm_max_burst_length {64}] \
    [get_bd_cells qr_capture_vdma]
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 qr_camera_cdc
set_property CONFIG.TUSER_WIDTH {65} [get_bd_cells qr_camera_cdc]
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 qr_capture_cdc
set_property CONFIG.TDATA_NUM_BYTES {4} [get_bd_cells qr_capture_cdc]
create_bd_cell -type ip -vlnv user.org:user:qr_preprocess:1.0 qr_preprocess_0
set capture_rgb 0
if {[info exists ::env(AX7021B_CAPTURE_LAYOUT)]} {
    switch -- $::env(AX7021B_CAPTURE_LAYOUT) {
        gray {set capture_rgb 0}
        color {set capture_rgb 1}
        default {error "AX7021B_CAPTURE_LAYOUT must be gray or color"}
    }
}
set payload_bram 0
if {[info exists ::env(AX7021B_PAYLOAD_BRAM)]} {
    if {$::env(AX7021B_PAYLOAD_BRAM) ni {0 1}} {error "AX7021B_PAYLOAD_BRAM must be 0 or 1"}
    set payload_bram $::env(AX7021B_PAYLOAD_BRAM)
}
set_property -dict [list CONFIG.GRAY_OUTPUT_DIVISOR {1} CONFIG.PL_ROI_ENABLE {1} \
    CONFIG.RGB_OUTPUT $capture_rgb CONFIG.PAYLOAD_BRAM $payload_bram] [get_bd_cells qr_preprocess_0]
if {[info exists ::env(AX7021B_ROI_PROFILE)]} {
    set profile $::env(AX7021B_ROI_PROFILE)
    set score 0;set finder 1;set iou 1;set union 0
    switch -- $profile {
        b1 {set iou 0}
        b2-0 {}
        b3a-145 {set score 145}
        b3b-150 {set score 150}
        b3a-145-union {set score 145;set union 1}
        default {error "Unknown ROI profile: $profile"}
    }
    set_property -dict [list CONFIG.ROI_SCORE_MIN $score CONFIG.ROI_FINDER_DEDUP $finder CONFIG.ROI_IOU_DEDUP $iou CONFIG.ROI_IOU_UNION $union] [get_bd_cells qr_preprocess_0]
}


# Keep the validated desktop, PWM and display memory path on FCLK0=100 MHz.
# The imported QR pipeline is timing-qualified at 80 MHz, so give it a
# dedicated static PS fabric clock and cross AXIS at both subsystem edges.
set qr_fclk [get_bd_pins ps7/FCLK_CLK1]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 qr_reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 qr_reset_locked
set_property CONFIG.CONST_VAL {1} [get_bd_cells qr_reset_locked]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 qr_aux_reset_inactive
set_property CONFIG.CONST_VAL {1} [get_bd_cells qr_aux_reset_inactive]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 qr_debug_reset_inactive
set_property CONFIG.CONST_VAL {0} [get_bd_cells qr_debug_reset_inactive]
connect_bd_net $qr_fclk [get_bd_pins qr_reset/slowest_sync_clk] [get_bd_pins qr_preprocess_0/aclk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET1_N] [get_bd_pins qr_reset/ext_reset_in]
connect_bd_net [get_bd_pins qr_reset_locked/dout] [get_bd_pins qr_reset/dcm_locked]
# proc_sys_reset's AUX input is active-low while MB debug reset is active-high.
# A shared zero constant therefore held the complete QR clock domain in reset
# and made every GP0 read of the QR AXI slave wait forever.
connect_bd_net [get_bd_pins qr_aux_reset_inactive/dout] [get_bd_pins qr_reset/aux_reset_in]
connect_bd_net [get_bd_pins qr_debug_reset_inactive/dout] [get_bd_pins qr_reset/mb_debug_sys_rst]
set qr_reset_pin [get_bd_pins qr_reset/peripheral_aresetn]
connect_bd_net $qr_reset_pin [get_bd_pins qr_preprocess_0/aresetn]

foreach port {camera_iic/S_AXI camera_reset/S_AXI camera_arm/S_AXI qr_capture_vdma/S_AXI_LITE qr_preprocess_0/S_AXI_CTRL} {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config {Master "/ps7/M_AXI_GP0" Clk_xbar "Auto"} [get_bd_intf_pins $port]
}

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 qr_memory
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells qr_memory]
connect_bd_intf_net [get_bd_intf_pins qr_capture_vdma/M_AXI_S2MM] [get_bd_intf_pins qr_memory/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins qr_memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP1]
connect_bd_intf_net [get_bd_intf_pins qr_camera_cdc/M_AXIS] [get_bd_intf_pins qr_preprocess_0/S_AXIS_VIDEO]
connect_bd_intf_net [get_bd_intf_pins qr_preprocess_0/M_AXIS_IMAGE] [get_bd_intf_pins qr_capture_cdc/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins qr_capture_cdc/M_AXIS] [get_bd_intf_pins qr_capture_vdma/S_AXIS_S2MM]

set base_fclk [get_bd_pins ps7/FCLK_CLK0]
set base_reset_cell [get_bd_cells -filter {VLNV =~ xilinx.com:ip:proc_sys_reset:* && NAME != pixel_reset && NAME != qr_reset}]
if {[llength $base_reset_cell] != 1} {error "Expected one desktop PS/FCLK reset controller: $base_reset_cell"}
set base_reset_pin [get_bd_pins ${base_reset_cell}/peripheral_aresetn]
set base_reset_net [get_bd_nets -quiet -of_objects $base_reset_pin]
foreach pin {qr_capture_vdma/s_axi_lite_aclk qr_capture_vdma/m_axi_s2mm_aclk qr_capture_vdma/s_axis_s2mm_aclk qr_capture_cdc/m_axis_aclk ps7/S_AXI_HP1_ACLK qr_memory/ACLK qr_memory/S00_ACLK qr_memory/M00_ACLK} {
    set endpoint [get_bd_pins $pin]
    set existing [get_bd_nets -quiet -of_objects $endpoint]
    if {[llength $existing] == 0} {
        connect_bd_net $base_fclk $endpoint
    } elseif {$existing ne [get_bd_nets -of_objects $base_fclk]} {
        error "Unexpected FCLK0 clock on $pin: $existing"
    }
}
foreach pin {qr_capture_vdma/axi_resetn qr_capture_cdc/m_axis_aresetn qr_memory/ARESETN qr_memory/S00_ARESETN qr_memory/M00_ARESETN} {
    set endpoint [get_bd_pins $pin]
    set existing [get_bd_nets -quiet -of_objects $endpoint]
    if {[llength $existing] == 0} {
        connect_bd_net $base_reset_pin $endpoint
    } elseif {$existing ne $base_reset_net} {
        error "Unexpected FCLK0 reset on $pin: $existing"
    }
}
connect_bd_net $qr_fclk [get_bd_pins qr_camera_cdc/m_axis_aclk] [get_bd_pins qr_capture_cdc/s_axis_aclk]
connect_bd_net $qr_reset_pin [get_bd_pins qr_camera_cdc/m_axis_aresetn] [get_bd_pins qr_capture_cdc/s_axis_aresetn]

create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 qr_video_in
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TUSER_WIDTH {65}] [get_bd_intf_ports qr_video_in]
connect_bd_intf_net [get_bd_intf_ports qr_video_in] [get_bd_intf_pins qr_camera_cdc/S_AXIS]
create_bd_port -dir I -type clk -freq_hz 100000000 qr_video_in_aclk
set_property CONFIG.ASSOCIATED_BUSIF {qr_video_in} [get_bd_ports qr_video_in_aclk]
connect_bd_net [get_bd_ports qr_video_in_aclk] [get_bd_pins qr_camera_cdc/s_axis_aclk]
create_bd_port -dir I -type rst qr_video_in_aresetn
set_property CONFIG.POLARITY {ACTIVE_LOW} [get_bd_ports qr_video_in_aresetn]
connect_bd_net [get_bd_ports qr_video_in_aresetn] [get_bd_pins qr_camera_cdc/s_axis_aresetn]

make_bd_intf_pins_external [get_bd_intf_pins camera_iic/IIC]
set_property name camera_iic [get_bd_intf_ports IIC_0]
foreach {port cell} {camera_reset_ctrl camera_reset camera_arm_ctrl camera_arm} {
    create_bd_port -dir O -from 0 -to 0 $port
    connect_bd_net [get_bd_ports $port] [get_bd_pins $cell/gpio_io_o]
}
create_bd_port -dir O pl_resetn
connect_bd_net $base_reset_pin [get_bd_ports pl_resetn]

set_property CONFIG.NUM_PORTS {5} [get_bd_cells interrupts]
connect_bd_net [get_bd_pins qr_capture_vdma/s2mm_introut] [get_bd_pins interrupts/In2]
connect_bd_net [get_bd_pins qr_preprocess_0/irq] [get_bd_pins interrupts/In3]
connect_bd_net [get_bd_pins camera_iic/iic2intc_irpt] [get_bd_pins interrupts/In4]

assign_bd_address
foreach {cell interface offset} {
    camera_iic S_AXI 0x41600000
    camera_reset S_AXI 0x41210000
    camera_arm S_AXI 0x41220000
    qr_capture_vdma S_AXI_LITE 0x43010000
} {
    set segment [get_bd_addr_segs ${cell}/${interface}/Reg]
    assign_bd_address -offset $offset -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] $segment -force
}
set qr_reg [get_bd_addr_segs -of_objects [get_bd_intf_pins qr_preprocess_0/S_AXI_CTRL]]
assign_bd_address -offset 0x43C00000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] $qr_reg -force
assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces qr_capture_vdma/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_HP1/HP1_DDR_LOWOCM] -force

# Passive capture event timestamps, independent ABI/address from C04 core.
create_bd_cell -type module -reference qr_capture_timing capture_timing
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk_xbar "Auto"} [get_bd_intf_pins capture_timing/S_AXI]
foreach {name type width} {cam_clk clk 1 cam_resetn rst 1 cam_vsync data 1 source_sof data 1 accepted_sof data 1 eof_toggle data 1 arm data 1 gate_state data 2} {
    if {$width == 1} {create_bd_port -dir I diag_$name} else {create_bd_port -dir I -from 1 -to 0 diag_$name}
    connect_bd_net [get_bd_ports diag_$name] [get_bd_pins capture_timing/$name]
}
assign_bd_address -offset 0x43C20000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins capture_timing/S_AXI]] -force


if {[info exists ::env(AX7021B_FITNESS_IP)]} {source [file join $qr_dir fitness_bd.tcl]}

source [file join $qr_dir .. desktop r4_display_bd.tcl]
