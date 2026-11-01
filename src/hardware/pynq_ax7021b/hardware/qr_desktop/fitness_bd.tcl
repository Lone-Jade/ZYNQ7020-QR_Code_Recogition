if {![info exists ::env(AX7021B_FITNESS_IP)]} {error "AX7021B_FITNESS_IP required"}
set_property ip_repo_paths [concat [get_property ip_repo_paths [current_project]] [list $::env(AX7021B_FITNESS_IP)]] [current_project]
update_ip_catalog
set_property CONFIG.PCW_USE_S_AXI_HP2 {1} [get_bd_cells ps7]
set fitness_vlnv xiwei.org:qr:qr_fitness:1.0
if {[info exists ::env(AX7021B_FITNESS_VLNV)]} {set fitness_vlnv $::env(AX7021B_FITNESS_VLNV)}
create_bd_cell -type ip -vlnv $fitness_vlnv fitness
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 fitness_reset
set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {1} CONFIG.C_DOUT_DEFAULT {0x00000000}] [get_bd_cells fitness_reset]
foreach pin {fitness/s_axi_control fitness_reset/S_AXI} {
 apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk_xbar "Auto"} [get_bd_intf_pins $pin]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 fitness_reset_and
set_property -dict [list CONFIG.C_OPERATION {and} CONFIG.C_SIZE {1}] [get_bd_cells fitness_reset_and]
# Override automatic reset connection for this IP only.
set auto_reset [get_bd_nets -of_objects [get_bd_pins fitness/ap_rst_n]]
if {[llength $auto_reset]} {disconnect_bd_net $auto_reset [get_bd_pins fitness/ap_rst_n]}
connect_bd_net $base_reset_pin [get_bd_pins fitness_reset_and/Op1]
connect_bd_net [get_bd_pins fitness_reset/gpio_io_o] [get_bd_pins fitness_reset_and/Op2]
connect_bd_net [get_bd_pins fitness_reset_and/Res] [get_bd_pins fitness/ap_rst_n]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 fitness_memory
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells fitness_memory]
connect_bd_intf_net [get_bd_intf_pins fitness/m_axi_memory] [get_bd_intf_pins fitness_memory/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins fitness_memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP2]
foreach pin {fitness_memory/ACLK fitness_memory/S00_ACLK fitness_memory/M00_ACLK ps7/S_AXI_HP2_ACLK} {connect_bd_net $base_fclk [get_bd_pins $pin]}
foreach pin {fitness_memory/ARESETN fitness_memory/S00_ARESETN fitness_memory/M00_ARESETN} {connect_bd_net $base_reset_pin [get_bd_pins $pin]}
set_property CONFIG.NUM_PORTS {6} [get_bd_cells interrupts]
connect_bd_net [get_bd_pins fitness/interrupt] [get_bd_pins interrupts/In5]
assign_bd_address
assign_bd_address -offset 0x43C10000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins fitness/s_axi_control]] -force
assign_bd_address -offset 0x41230000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs fitness_reset/S_AXI/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces fitness/Data_m_axi_memory] [get_bd_addr_segs ps7/S_AXI_HP2/HP2_DDR_LOWOCM] -force

# Passive scoreboard; no signal from it controls fitness, DMA or capture.
add_files -norecurse [file join $qr_repo_root qr_diag45_20261018 qr_video_replay rtl qr_fitness_timing.v]
create_bd_cell -type module -reference qr_fitness_timing fitness_timing
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk_xbar "Auto"} [get_bd_intf_pins fitness_timing/S_AXI]
set fitness_master [get_bd_intf_pins -of_objects [get_bd_intf_nets -of_objects [get_bd_intf_pins fitness/s_axi_control]] -filter {MODE == Master}]
if {[llength $fitness_master] != 1} {error "Fitness AXI master not unique"}
# Input-to-input nets do not tap an interface. Connect to its real master
# outputs, and use HLS slave outputs only for READY and completion/reset.
foreach {tap suffix} {tap_awaddr awaddr tap_awvalid awvalid tap_wdata wdata tap_wstrb wstrb tap_wvalid wvalid} {
 set driver [get_bd_pins -quiet ${fitness_master}_${suffix}]
 if {![llength $driver]} {set driver [get_bd_pins ${fitness_master}_[string toupper $suffix]]}
 connect_bd_net $driver [get_bd_pins fitness/s_axi_control_[string toupper $suffix]] [get_bd_pins fitness_timing/$tap]
}
foreach {tap suffix} {tap_awready awready tap_wready wready} {
 set receiver [get_bd_pins -quiet ${fitness_master}_${suffix}]
 if {![llength $receiver]} {set receiver [get_bd_pins ${fitness_master}_[string toupper $suffix]]}
 connect_bd_net [get_bd_pins fitness/s_axi_control_[string toupper $suffix]] $receiver [get_bd_pins fitness_timing/$tap]
}
foreach {tap pin} {tap_irq interrupt tap_resetn ap_rst_n} {connect_bd_net [get_bd_pins fitness/$pin] [get_bd_pins fitness_timing/$tap]}
assign_bd_address -offset 0x43C30000 -range 0x10000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins fitness_timing/S_AXI]] -force
