set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $script_dir .. ..]]
set project_name ax7021b_linux_base
set qr_desktop [expr {[info exists ::env(AX7021B_QR)] && $::env(AX7021B_QR) eq "1"}]
set desktop [expr {$qr_desktop || ([info exists ::env(AX7021B_DESKTOP)] && $::env(AX7021B_DESKTOP) eq "1")}]
if {$desktop} {set project_name ax7021b_linux_desktop}
if {$qr_desktop} {set project_name ax7021b_linux_qr_desktop}
set project_dir [file join $project_root work vivado $project_name]
if {$qr_desktop && [info exists ::env(AX7021B_QR_WORK_ROOT)]} {
    set project_dir [file join $::env(AX7021B_QR_WORK_ROOT) $project_name]
}
set part xc7z020clg484-2

file mkdir [file dirname $project_dir]
create_project $project_name $project_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
if {$qr_desktop && [info exists ::env(AX7021B_ROI_PROFILE)]} {
    set roi_ip_cache [file join $project_root work roi-selection ip-cache]
    file mkdir $roi_ip_cache
    config_ip_cache -use_cache_location $roi_ip_cache
}


create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7

# AX7021B processing-system configuration, consolidated from the board manual,
# the known-working local UART/Ethernet designs, and the original SD card DT.
# MIO GPIO must be enabled as in historical Ethernet_Test (70807f9), or
# ps7_init omits both the MIO7 configuration and the ENET0 reset sequence.
set ps_cfg [list \
    CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {0} \
    CONFIG.PCW_EN_UART1 {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 12 .. 13} \
    CONFIG.PCW_UART1_BAUD_RATE {115200} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_ENET0_RESET_ENABLE {1} \
    CONFIG.PCW_ENET0_RESET_IO {MIO 7} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO 7} \
    CONFIG.PCW_MIO_7_PULLUP {enabled} \
    CONFIG.PCW_MIO_7_SLEW {fast} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 10} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {50}]

foreach mio {16 17 18 19 20 21 22 23 24 25 26 27} {
    lappend ps_cfg CONFIG.PCW_MIO_${mio}_SLEW {fast}
}
foreach mio {10 40 41 42 43 44 45} {
    lappend ps_cfg CONFIG.PCW_MIO_${mio}_PULLUP {enabled}
    lappend ps_cfg CONFIG.PCW_MIO_${mio}_SLEW {slow}
}
set_property -dict $ps_cfg [get_bd_cells ps7]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR"} [get_bd_cells ps7]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]

if {$desktop} {source [file join $script_dir .. desktop display_bd.tcl]}
if {$qr_desktop} {source [file join $script_dir .. qr_desktop qr_bd.tcl]}

validate_bd_design
save_bd_design

set bd_file [get_files [file join $project_dir ${project_name}.srcs sources_1 bd system system.bd]]
generate_target all $bd_file
make_wrapper -files $bd_file -top
add_files -norecurse [file join $project_dir ${project_name}.gen sources_1 bd system hdl system_wrapper.v]
set_property top system_wrapper [current_fileset]
if {$qr_desktop} {set_property top qr_desktop_top [current_fileset]}
update_compile_order -fileset sources_1

puts "Created AX7021B Linux base project at $project_dir"
