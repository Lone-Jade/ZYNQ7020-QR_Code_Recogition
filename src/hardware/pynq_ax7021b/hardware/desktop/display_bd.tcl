set display_dir [file normalize [file join $script_dir .. desktop]]
set with_pwm [expr {![info exists ::env(AX7021B_NO_PWM)] || $::env(AX7021B_NO_PWM) ne "1"}]
if {$with_pwm} {
    set pwm_ip_dir [file normalize [file join $project_root .. history_demo pwm_IP ip pwm_axi_v1_0]]
    if {![file exists [file join $pwm_ip_dir component.xml]]} {error "Packaged PWM IP not found: $pwm_ip_dir"}
    set_property ip_repo_paths [concat [get_property ip_repo_paths [current_project]] [list $pwm_ip_dir]] [current_project]
    update_ip_catalog
}
add_files [file join $display_dir hdmi_desktop.v]
add_files -fileset constrs_1 [file join $display_dir hdmi.xdc]
if {$with_pwm} {add_files -fileset constrs_1 [file join $display_dir pwm_led.xdc]}
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} CONFIG.PCW_USB0_RESET_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_IO {MIO 8}] [get_bd_cells ps7]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 hdmi_iic
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 hdmi_reset
set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {1}] [get_bd_cells hdmi_reset]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 display_vdma
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} CONFIG.c_num_fstores {3} CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_m_axis_mm2s_tdata_width {16} \
    CONFIG.c_mm2s_max_burst_length {64} CONFIG.c_include_internal_genlock {1} \
    CONFIG.c_s2mm_genlock_mode {2} CONFIG.c_mm2s_genlock_mode {3} \
    CONFIG.c_include_s2mm_dre {0} CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_max_burst_length {64} \
    CONFIG.c_s2mm_linebuffer_depth {2048}] [get_bd_cells display_vdma]
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 pixel_clock
set_property -dict [list CONFIG.PRIM_IN_FREQ {100} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.25} \
    CONFIG.USE_RESET {false} CONFIG.USE_LOCKED {true}] [get_bd_cells pixel_clock]
create_bd_cell -type module -reference hdmi_desktop video_timing
if {$with_pwm} {
create_bd_cell -type ip -vlnv xiwei.com:user:pwm_axi_v1_0:1.0 pwm_axi_v1_0_0
set_property -dict [list CONFIG.C_S00_AXI_DATA_WIDTH {32} CONFIG.C_S00_AXI_ADDR_WIDTH {5}] [get_bd_cells pwm_axi_v1_0_0]
}
set display_control_ports {hdmi_iic/S_AXI hdmi_reset/S_AXI display_vdma/S_AXI_LITE}
if {$with_pwm} {lappend display_control_ports pwm_axi_v1_0_0/S00_AXI}
foreach port $display_control_ports {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config {Master "/ps7/M_AXI_GP0" Clk_xbar "Auto"} [get_bd_intf_pins $port]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 display_memory
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells display_memory]
connect_bd_intf_net [get_bd_intf_pins display_vdma/M_AXI_MM2S] [get_bd_intf_pins display_memory/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins display_vdma/M_AXI_S2MM] [get_bd_intf_pins display_memory/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins display_memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
set fclk [get_bd_pins ps7/FCLK_CLK0]
foreach pin {pixel_clock/clk_in1 display_vdma/m_axi_mm2s_aclk ps7/S_AXI_HP0_ACLK display_memory/ACLK display_memory/S00_ACLK display_memory/S01_ACLK display_vdma/m_axi_s2mm_aclk display_vdma/s_axis_s2mm_aclk display_memory/M00_ACLK} {
    connect_bd_net $fclk [get_bd_pins $pin]
}
set reset_cell [get_bd_cells -filter {VLNV =~ xilinx.com:ip:proc_sys_reset:*}]
set rst [get_bd_pins ${reset_cell}/peripheral_aresetn]
connect_bd_net $rst [get_bd_pins display_vdma/axi_resetn] [get_bd_pins display_memory/ARESETN] [get_bd_pins display_memory/S00_ARESETN] [get_bd_pins display_memory/S01_ARESETN] [get_bd_pins display_memory/M00_ARESETN]
connect_bd_net [get_bd_pins pixel_clock/clk_out1] [get_bd_pins video_timing/pixel_clk] [get_bd_pins display_vdma/m_axis_mm2s_aclk]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pixel_reset
connect_bd_net [get_bd_pins pixel_clock/clk_out1] [get_bd_pins pixel_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins pixel_clock/locked] [get_bd_pins pixel_reset/dcm_locked]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins pixel_reset/ext_reset_in]
connect_bd_net [get_bd_pins pixel_reset/peripheral_aresetn] [get_bd_pins video_timing/resetn]
connect_bd_intf_net [get_bd_intf_pins display_vdma/M_AXIS_MM2S] [get_bd_intf_pins video_timing/s_axis]
if {$with_pwm} {
create_bd_port -dir O -from 1 -to 0 pwm_led_n
connect_bd_net [get_bd_pins pwm_axi_v1_0_0/pwm_led_n] [get_bd_ports pwm_led_n]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 interrupts
set_property CONFIG.NUM_PORTS {2} [get_bd_cells interrupts]
connect_bd_net [get_bd_pins display_vdma/mm2s_introut] [get_bd_pins interrupts/In0]
connect_bd_net [get_bd_pins hdmi_iic/iic2intc_irpt] [get_bd_pins interrupts/In1]
connect_bd_net [get_bd_pins interrupts/dout] [get_bd_pins ps7/IRQ_F2P]
make_bd_intf_pins_external [get_bd_intf_pins hdmi_iic/IIC]
set_property name hdmi_iic [get_bd_intf_ports IIC_0]
create_bd_port -dir O hdmi_reset_n
connect_bd_net [get_bd_pins hdmi_reset/gpio_io_o] [get_bd_ports hdmi_reset_n]
foreach pin {hdmi_clk} {
    make_bd_pins_external [get_bd_pins video_timing/$pin]
    set_property name $pin [get_bd_ports ${pin}_0]
}
assign_bd_address
foreach {cell interface offset} {hdmi_iic S_AXI 0x41610000 hdmi_reset S_AXI 0x41200000 display_vdma S_AXI_LITE 0x43000000} {
    set seg [get_bd_addr_segs ${cell}/${interface}/Reg]
    assign_bd_address -offset $offset -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] $seg -force
}
if {$with_pwm} {
set pwm_reg_seg [get_bd_addr_segs -of_objects [get_bd_intf_pins pwm_axi_v1_0_0/S00_AXI]]
assign_bd_address -offset 0x43C10000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps7/Data] $pwm_reg_seg -force

}
