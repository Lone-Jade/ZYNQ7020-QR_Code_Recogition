
################################################################
# This is a generated script based on design: system
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source system_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# hdmi_desktop, qr_capture_timing, qr_fitness_timing, r4_display_osd, r4_hdmi_rgb, r4_display_memory_guard, r4_scan_identity

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg484-2
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name system

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
xilinx.com:ip:axi_iic:2.1\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:axi_vdma:6.3\
xilinx.com:ip:clk_wiz:6.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:xlconcat:2.1\
xilinx.com:ip:axis_clock_converter:1.1\
user.org:user:qr_preprocess:1.0\
xilinx.com:ip:xlconstant:1.1\
xiwei.org:qr:qr_fitness:2.0\
xilinx.com:ip:util_vector_logic:2.0\
xilinx.com:ip:axis_subset_converter:1.1\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
hdmi_desktop\
qr_capture_timing\
qr_fitness_timing\
r4_display_osd\
r4_hdmi_rgb\
r4_display_memory_guard\
r4_scan_identity\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

  set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]

  set hdmi_iic [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 hdmi_iic ]

  set qr_video_in [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 qr_video_in ]
  set_property -dict [ list \
   CONFIG.HAS_TKEEP {1} \
   CONFIG.HAS_TLAST {1} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {2} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {65} \
   ] $qr_video_in

  set camera_iic [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 camera_iic ]

  set display_video [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 display_video ]
  set_property -dict [ list \
   CONFIG.HAS_TKEEP {1} \
   CONFIG.HAS_TLAST {1} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {2} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {65} \
   ] $display_video


  # Create ports
  set hdmi_reset_n [ create_bd_port -dir O -from 0 -to 0 hdmi_reset_n ]
  set hdmi_clk [ create_bd_port -dir O -type clk hdmi_clk ]
  set qr_video_in_aclk [ create_bd_port -dir I -type clk -freq_hz 100000000 qr_video_in_aclk ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {qr_video_in} \
 ] $qr_video_in_aclk
  set qr_video_in_aresetn [ create_bd_port -dir I -type rst qr_video_in_aresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $qr_video_in_aresetn
  set camera_reset_ctrl [ create_bd_port -dir O -from 0 -to 0 camera_reset_ctrl ]
  set camera_arm_ctrl [ create_bd_port -dir O -from 0 -to 0 camera_arm_ctrl ]
  set pl_resetn [ create_bd_port -dir O -from 0 -to 0 pl_resetn ]
  set diag_cam_clk [ create_bd_port -dir I diag_cam_clk ]
  set diag_cam_resetn [ create_bd_port -dir I diag_cam_resetn ]
  set diag_cam_vsync [ create_bd_port -dir I diag_cam_vsync ]
  set diag_source_sof [ create_bd_port -dir I diag_source_sof ]
  set diag_accepted_sof [ create_bd_port -dir I diag_accepted_sof ]
  set diag_eof_toggle [ create_bd_port -dir I diag_eof_toggle ]
  set diag_arm [ create_bd_port -dir I diag_arm ]
  set diag_gate_state [ create_bd_port -dir I -from 1 -to 0 diag_gate_state ]
  set hdmi_d [ create_bd_port -dir O -from 23 -to 0 hdmi_d ]
  set hdmi_de [ create_bd_port -dir O hdmi_de ]
  set hdmi_hs [ create_bd_port -dir O hdmi_hs ]
  set hdmi_vs [ create_bd_port -dir O hdmi_vs ]
  set r4_display_enable [ create_bd_port -dir O r4_display_enable ]
  set r4_source_epoch [ create_bd_port -dir O -from 31 -to 0 r4_source_epoch ]
  set r4_display_clear [ create_bd_port -dir O r4_display_clear ]
  set r4_display_fault [ create_bd_port -dir I r4_display_fault ]
  set r4_source_frames [ create_bd_port -dir I -from 31 -to 0 r4_source_frames ]
  set r4_display_frames [ create_bd_port -dir I -from 31 -to 0 r4_display_frames ]
  set r4_display_drops [ create_bd_port -dir I -from 31 -to 0 r4_display_drops ]
  set r4_qr_drops [ create_bd_port -dir I -from 31 -to 0 r4_qr_drops ]
  set display_video_aclk [ create_bd_port -dir I -type clk -freq_hz 100000000 display_video_aclk ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {display_video} \
 ] $display_video_aclk
  set display_video_aresetn [ create_bd_port -dir I -type rst display_video_aresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $display_video_aresetn

  # Create instance: ps7, and set properties
  set ps7 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7 ]
  set_property -dict [list \
    CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666687} \
    CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158730} \
    CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {125.000000} \
    CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {76.923080} \
    CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_CLK1_FREQ {76923080} \
    CONFIG.PCW_CLK2_FREQ {10000000} \
    CONFIG.PCW_CLK3_FREQ {10000000} \
    CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
    CONFIG.PCW_ENET0_RESET_ENABLE {1} \
    CONFIG.PCW_ENET0_RESET_IO {MIO 7} \
    CONFIG.PCW_ENET_RESET_ENABLE {1} \
    CONFIG.PCW_ENET_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_EN_ENET0 {1} \
    CONFIG.PCW_EN_GPIO {1} \
    CONFIG.PCW_EN_RST1_PORT {1} \
    CONFIG.PCW_EN_SDIO0 {1} \
    CONFIG.PCW_EN_UART1 {1} \
    CONFIG.PCW_EN_USB0 {1} \
    CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
    CONFIG.PCW_FCLK_CLK1_BUF {TRUE} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {80.000000} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_FPGA_FCLK1_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO 7} \
    CONFIG.PCW_I2C_RESET_ENABLE {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_0_PULLUP {enabled} \
    CONFIG.PCW_MIO_0_SLEW {slow} \
    CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_10_PULLUP {enabled} \
    CONFIG.PCW_MIO_10_SLEW {slow} \
    CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_11_PULLUP {enabled} \
    CONFIG.PCW_MIO_11_SLEW {slow} \
    CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_12_PULLUP {enabled} \
    CONFIG.PCW_MIO_12_SLEW {slow} \
    CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_13_PULLUP {enabled} \
    CONFIG.PCW_MIO_13_SLEW {slow} \
    CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_14_PULLUP {enabled} \
    CONFIG.PCW_MIO_14_SLEW {slow} \
    CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_15_PULLUP {enabled} \
    CONFIG.PCW_MIO_15_SLEW {slow} \
    CONFIG.PCW_MIO_16_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_16_PULLUP {enabled} \
    CONFIG.PCW_MIO_16_SLEW {fast} \
    CONFIG.PCW_MIO_17_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_17_PULLUP {enabled} \
    CONFIG.PCW_MIO_17_SLEW {fast} \
    CONFIG.PCW_MIO_18_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_18_PULLUP {enabled} \
    CONFIG.PCW_MIO_18_SLEW {fast} \
    CONFIG.PCW_MIO_19_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_19_PULLUP {enabled} \
    CONFIG.PCW_MIO_19_SLEW {fast} \
    CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_1_PULLUP {enabled} \
    CONFIG.PCW_MIO_1_SLEW {slow} \
    CONFIG.PCW_MIO_20_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_20_PULLUP {enabled} \
    CONFIG.PCW_MIO_20_SLEW {fast} \
    CONFIG.PCW_MIO_21_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_21_PULLUP {enabled} \
    CONFIG.PCW_MIO_21_SLEW {fast} \
    CONFIG.PCW_MIO_22_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_22_PULLUP {enabled} \
    CONFIG.PCW_MIO_22_SLEW {fast} \
    CONFIG.PCW_MIO_23_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_23_PULLUP {enabled} \
    CONFIG.PCW_MIO_23_SLEW {fast} \
    CONFIG.PCW_MIO_24_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_24_PULLUP {enabled} \
    CONFIG.PCW_MIO_24_SLEW {fast} \
    CONFIG.PCW_MIO_25_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_25_PULLUP {enabled} \
    CONFIG.PCW_MIO_25_SLEW {fast} \
    CONFIG.PCW_MIO_26_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_26_PULLUP {enabled} \
    CONFIG.PCW_MIO_26_SLEW {fast} \
    CONFIG.PCW_MIO_27_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_27_PULLUP {enabled} \
    CONFIG.PCW_MIO_27_SLEW {fast} \
    CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_28_PULLUP {enabled} \
    CONFIG.PCW_MIO_28_SLEW {slow} \
    CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_29_PULLUP {enabled} \
    CONFIG.PCW_MIO_29_SLEW {slow} \
    CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_2_SLEW {slow} \
    CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_30_PULLUP {enabled} \
    CONFIG.PCW_MIO_30_SLEW {slow} \
    CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_31_PULLUP {enabled} \
    CONFIG.PCW_MIO_31_SLEW {slow} \
    CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_32_PULLUP {enabled} \
    CONFIG.PCW_MIO_32_SLEW {slow} \
    CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_33_PULLUP {enabled} \
    CONFIG.PCW_MIO_33_SLEW {slow} \
    CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_34_PULLUP {enabled} \
    CONFIG.PCW_MIO_34_SLEW {slow} \
    CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_35_PULLUP {enabled} \
    CONFIG.PCW_MIO_35_SLEW {slow} \
    CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_36_PULLUP {enabled} \
    CONFIG.PCW_MIO_36_SLEW {slow} \
    CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_37_PULLUP {enabled} \
    CONFIG.PCW_MIO_37_SLEW {slow} \
    CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_38_PULLUP {enabled} \
    CONFIG.PCW_MIO_38_SLEW {slow} \
    CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_39_PULLUP {enabled} \
    CONFIG.PCW_MIO_39_SLEW {slow} \
    CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_3_SLEW {slow} \
    CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_40_PULLUP {enabled} \
    CONFIG.PCW_MIO_40_SLEW {slow} \
    CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_41_PULLUP {enabled} \
    CONFIG.PCW_MIO_41_SLEW {slow} \
    CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_42_PULLUP {enabled} \
    CONFIG.PCW_MIO_42_SLEW {slow} \
    CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_43_PULLUP {enabled} \
    CONFIG.PCW_MIO_43_SLEW {slow} \
    CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_44_PULLUP {enabled} \
    CONFIG.PCW_MIO_44_SLEW {slow} \
    CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_45_PULLUP {enabled} \
    CONFIG.PCW_MIO_45_SLEW {slow} \
    CONFIG.PCW_MIO_46_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_46_PULLUP {enabled} \
    CONFIG.PCW_MIO_46_SLEW {slow} \
    CONFIG.PCW_MIO_47_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_47_PULLUP {enabled} \
    CONFIG.PCW_MIO_47_SLEW {slow} \
    CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_48_PULLUP {enabled} \
    CONFIG.PCW_MIO_48_SLEW {slow} \
    CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_49_PULLUP {enabled} \
    CONFIG.PCW_MIO_49_SLEW {slow} \
    CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_4_SLEW {slow} \
    CONFIG.PCW_MIO_50_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_50_PULLUP {enabled} \
    CONFIG.PCW_MIO_50_SLEW {slow} \
    CONFIG.PCW_MIO_51_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_51_PULLUP {enabled} \
    CONFIG.PCW_MIO_51_SLEW {slow} \
    CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_52_PULLUP {enabled} \
    CONFIG.PCW_MIO_52_SLEW {slow} \
    CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_53_PULLUP {enabled} \
    CONFIG.PCW_MIO_53_SLEW {slow} \
    CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_5_SLEW {slow} \
    CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_6_SLEW {slow} \
    CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_7_SLEW {fast} \
    CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_8_SLEW {slow} \
    CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_9_PULLUP {enabled} \
    CONFIG.PCW_MIO_9_SLEW {slow} \
    CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#ENET Reset#USB Reset#GPIO#SD 0#GPIO#UART 1#UART 1#GPIO#GPIO#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet\
0#Enet 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#Enet 0#Enet 0} \
    CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#gpio[1]#gpio[2]#gpio[3]#gpio[4]#gpio[5]#gpio[6]#reset#reset#gpio[9]#cd#gpio[11]#tx#rx#gpio[14]#gpio[15]#tx_clk#txd[0]#txd[1]#txd[2]#txd[3]#tx_ctl#rx_clk#rxd[0]#rxd[1]#rxd[2]#rxd[3]#rx_ctl#data[4]#dir#stp#nxt#data[0]#data[1]#data[2]#data[3]#clk#data[5]#data[6]#data[7]#clk#cmd#data[0]#data[1]#data[2]#data[3]#gpio[46]#gpio[47]#gpio[48]#gpio[49]#gpio[50]#gpio[51]#mdc#mdio}\
\
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 10} \
    CONFIG.PCW_SD0_GRP_POW_ENABLE {0} \
    CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UART1_BAUD_RATE {115200} \
    CONFIG.PCW_UART1_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 12 .. 13} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_IO {MIO 8} \
    CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
    CONFIG.PCW_USB_RESET_ENABLE {1} \
    CONFIG.PCW_USB_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_USE_S_AXI_HP2 {1} \
  ] $ps7


  # Create instance: hdmi_iic, and set properties
  set hdmi_iic [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 hdmi_iic ]

  # Create instance: hdmi_reset, and set properties
  set hdmi_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 hdmi_reset ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO_WIDTH {1} \
  ] $hdmi_reset


  # Create instance: display_vdma, and set properties
  set display_vdma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 display_vdma ]
  set_property -dict [list \
    CONFIG.c_include_internal_genlock {1} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_s2mm_dre {0} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {16} \
    CONFIG.c_mm2s_genlock_mode {3} \
    CONFIG.c_mm2s_max_burst_length {64} \
    CONFIG.c_num_fstores {3} \
    CONFIG.c_s2mm_genlock_mode {2} \
    CONFIG.c_s2mm_linebuffer_depth {2048} \
    CONFIG.c_s2mm_max_burst_length {64} \
  ] $display_vdma


  # Create instance: pixel_clock, and set properties
  set pixel_clock [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 pixel_clock ]
  set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.25} \
    CONFIG.PRIM_IN_FREQ {100} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {false} \
  ] $pixel_clock


  # Create instance: video_timing, and set properties
  set block_name hdmi_desktop
  set block_cell_name video_timing
  if { [catch {set video_timing [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $video_timing eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: ps7_axi_periph, and set properties
  set ps7_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps7_axi_periph ]
  set_property CONFIG.NUM_MI {13} $ps7_axi_periph


  # Create instance: rst_ps7_100M, and set properties
  set rst_ps7_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_100M ]

  # Create instance: display_memory, and set properties
  set display_memory [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 display_memory ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {2} \
  ] $display_memory


  # Create instance: pixel_reset, and set properties
  set pixel_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pixel_reset ]

  # Create instance: interrupts, and set properties
  set interrupts [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 interrupts ]
  set_property CONFIG.NUM_PORTS {7} $interrupts


  # Create instance: camera_iic, and set properties
  set camera_iic [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 camera_iic ]

  # Create instance: camera_reset, and set properties
  set camera_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 camera_reset ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO_WIDTH {1} \
  ] $camera_reset


  # Create instance: camera_arm, and set properties
  set camera_arm [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 camera_arm ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO_WIDTH {1} \
  ] $camera_arm


  # Create instance: qr_capture_vdma, and set properties
  set qr_capture_vdma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 qr_capture_vdma ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_s2mm_dre {0} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_num_fstores {3} \
    CONFIG.c_s2mm_linebuffer_depth {1024} \
    CONFIG.c_s2mm_max_burst_length {64} \
  ] $qr_capture_vdma


  # Create instance: qr_camera_cdc, and set properties
  set qr_camera_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 qr_camera_cdc ]
  set_property CONFIG.TUSER_WIDTH {65} $qr_camera_cdc


  # Create instance: qr_capture_cdc, and set properties
  set qr_capture_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 qr_capture_cdc ]
  set_property CONFIG.TDATA_NUM_BYTES {4} $qr_capture_cdc


  # Create instance: qr_preprocess_0, and set properties
  set qr_preprocess_0 [ create_bd_cell -type ip -vlnv user.org:user:qr_preprocess:1.0 qr_preprocess_0 ]
  set_property -dict [list \
    CONFIG.GRAY_OUTPUT_DIVISOR {1} \
    CONFIG.PAYLOAD_BRAM {1} \
    CONFIG.PL_ROI_ENABLE {1} \
    CONFIG.RGB_OUTPUT {0} \
    CONFIG.ROI_FINDER_DEDUP {1} \
    CONFIG.ROI_IOU_DEDUP {1} \
    CONFIG.ROI_IOU_UNION {1} \
    CONFIG.ROI_SCORE_MIN {145} \
  ] $qr_preprocess_0


  # Create instance: qr_reset, and set properties
  set qr_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 qr_reset ]

  # Create instance: qr_reset_locked, and set properties
  set qr_reset_locked [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 qr_reset_locked ]
  set_property CONFIG.CONST_VAL {1} $qr_reset_locked


  # Create instance: qr_aux_reset_inactive, and set properties
  set qr_aux_reset_inactive [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 qr_aux_reset_inactive ]
  set_property CONFIG.CONST_VAL {1} $qr_aux_reset_inactive


  # Create instance: qr_debug_reset_inactive, and set properties
  set qr_debug_reset_inactive [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 qr_debug_reset_inactive ]
  set_property CONFIG.CONST_VAL {0} $qr_debug_reset_inactive


  # Create instance: qr_memory, and set properties
  set qr_memory [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 qr_memory ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $qr_memory


  # Create instance: capture_timing, and set properties
  set block_name qr_capture_timing
  set block_cell_name capture_timing
  if { [catch {set capture_timing [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $capture_timing eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: fitness, and set properties
  set fitness [ create_bd_cell -type ip -vlnv xiwei.org:qr:qr_fitness:2.0 fitness ]

  # Create instance: fitness_reset, and set properties
  set fitness_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 fitness_reset ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} \
    CONFIG.C_GPIO_WIDTH {1} \
  ] $fitness_reset


  # Create instance: fitness_reset_and, and set properties
  set fitness_reset_and [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 fitness_reset_and ]
  set_property -dict [list \
    CONFIG.C_OPERATION {and} \
    CONFIG.C_SIZE {1} \
  ] $fitness_reset_and


  # Create instance: fitness_memory, and set properties
  set fitness_memory [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 fitness_memory ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $fitness_memory


  # Create instance: fitness_timing, and set properties
  set block_name qr_fitness_timing
  set block_cell_name fitness_timing
  if { [catch {set fitness_timing [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $fitness_timing eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: display_osd, and set properties
  set block_name r4_display_osd
  set block_cell_name display_osd
  if { [catch {set display_osd [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $display_osd eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: display_rgb, and set properties
  set block_name r4_hdmi_rgb
  set block_cell_name display_rgb
  if { [catch {set display_rgb [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $display_rgb eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: display_camera_cdc, and set properties
  set display_camera_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 display_camera_cdc ]
  set_property -dict [list \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.TDATA_NUM_BYTES {2} \
    CONFIG.TUSER_WIDTH {65} \
  ] $display_camera_cdc


  # Create instance: display_sof, and set properties
  set display_sof [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 display_sof ]
  set_property -dict [list \
    CONFIG.M_HAS_TKEEP {1} \
    CONFIG.M_HAS_TLAST {1} \
    CONFIG.M_HAS_TREADY {1} \
    CONFIG.M_HAS_TSTRB {0} \
    CONFIG.M_TDATA_NUM_BYTES {2} \
    CONFIG.M_TDEST_WIDTH {0} \
    CONFIG.M_TID_WIDTH {0} \
    CONFIG.M_TUSER_WIDTH {1} \
    CONFIG.S_HAS_TKEEP {1} \
    CONFIG.S_HAS_TLAST {1} \
    CONFIG.S_HAS_TREADY {1} \
    CONFIG.S_HAS_TSTRB {0} \
    CONFIG.S_TDATA_NUM_BYTES {2} \
    CONFIG.S_TDEST_WIDTH {0} \
    CONFIG.S_TID_WIDTH {0} \
    CONFIG.S_TUSER_WIDTH {65} \
    CONFIG.TUSER_REMAP {tuser[0:0]} \
  ] $display_sof

  set_property -dict [list \
    CONFIG.M_HAS_TREADY.VALUE_MODE {auto} \
    CONFIG.M_HAS_TSTRB.VALUE_MODE {auto} \
    CONFIG.M_TDEST_WIDTH.VALUE_MODE {auto} \
    CONFIG.M_TID_WIDTH.VALUE_MODE {auto} \
    CONFIG.S_HAS_TREADY.VALUE_MODE {auto} \
    CONFIG.S_HAS_TSTRB.VALUE_MODE {auto} \
    CONFIG.S_TDEST_WIDTH.VALUE_MODE {auto} \
    CONFIG.S_TID_WIDTH.VALUE_MODE {auto} \
  ] $display_sof


  # Create instance: display_guard, and set properties
  set block_name r4_display_memory_guard
  set block_cell_name display_guard
  if { [catch {set display_guard [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $display_guard eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: display_identity, and set properties
  set block_name r4_scan_identity
  set block_cell_name display_identity
  if { [catch {set display_identity [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $display_identity eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: display_fault_or, and set properties
  set display_fault_or [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 display_fault_or ]
  set_property -dict [list \
    CONFIG.C_OPERATION {or} \
    CONFIG.C_SIZE {1} \
  ] $display_fault_or


  # Create interface connections
  connect_bd_intf_net -intf_net camera_iic_IIC [get_bd_intf_ports camera_iic] [get_bd_intf_pins camera_iic/IIC]
  connect_bd_intf_net -intf_net display_camera_cdc_M_AXIS [get_bd_intf_pins display_camera_cdc/M_AXIS] [get_bd_intf_pins display_sof/S_AXIS]
  connect_bd_intf_net -intf_net display_memory_M00_AXI [get_bd_intf_pins display_memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
  connect_bd_intf_net -intf_net display_sof_M_AXIS [get_bd_intf_pins display_sof/M_AXIS] [get_bd_intf_pins display_vdma/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net display_vdma_M_AXIS_MM2S [get_bd_intf_pins display_vdma/M_AXIS_MM2S] [get_bd_intf_pins video_timing/s_axis]
  connect_bd_intf_net -intf_net display_vdma_M_AXI_MM2S [get_bd_intf_pins display_vdma/M_AXI_MM2S] [get_bd_intf_pins display_memory/S00_AXI]
  connect_bd_intf_net -intf_net display_vdma_M_AXI_S2MM [get_bd_intf_pins display_vdma/M_AXI_S2MM] [get_bd_intf_pins display_memory/S01_AXI]
  connect_bd_intf_net -intf_net display_video_1 [get_bd_intf_ports display_video] [get_bd_intf_pins display_camera_cdc/S_AXIS]
  connect_bd_intf_net -intf_net fitness_m_axi_memory [get_bd_intf_pins fitness/m_axi_memory] [get_bd_intf_pins fitness_memory/S00_AXI]
  connect_bd_intf_net -intf_net fitness_memory_M00_AXI [get_bd_intf_pins fitness_memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP2]
  connect_bd_intf_net -intf_net hdmi_iic_IIC [get_bd_intf_ports hdmi_iic] [get_bd_intf_pins hdmi_iic/IIC]
  connect_bd_intf_net -intf_net ps7_DDR [get_bd_intf_ports DDR] [get_bd_intf_pins ps7/DDR]
  connect_bd_intf_net -intf_net ps7_FIXED_IO [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]
  connect_bd_intf_net -intf_net ps7_M_AXI_GP0 [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins ps7_axi_periph/S00_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M00_AXI [get_bd_intf_pins ps7_axi_periph/M00_AXI] [get_bd_intf_pins hdmi_iic/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M01_AXI [get_bd_intf_pins ps7_axi_periph/M01_AXI] [get_bd_intf_pins hdmi_reset/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M02_AXI [get_bd_intf_pins ps7_axi_periph/M02_AXI] [get_bd_intf_pins display_vdma/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_axi_periph_M03_AXI [get_bd_intf_pins ps7_axi_periph/M03_AXI] [get_bd_intf_pins camera_iic/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M04_AXI [get_bd_intf_pins ps7_axi_periph/M04_AXI] [get_bd_intf_pins camera_reset/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M05_AXI [get_bd_intf_pins ps7_axi_periph/M05_AXI] [get_bd_intf_pins camera_arm/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M06_AXI [get_bd_intf_pins ps7_axi_periph/M06_AXI] [get_bd_intf_pins qr_capture_vdma/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_axi_periph_M07_AXI [get_bd_intf_pins ps7_axi_periph/M07_AXI] [get_bd_intf_pins qr_preprocess_0/S_AXI_CTRL]
  connect_bd_intf_net -intf_net ps7_axi_periph_M08_AXI [get_bd_intf_pins ps7_axi_periph/M08_AXI] [get_bd_intf_pins capture_timing/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M09_AXI [get_bd_intf_pins ps7_axi_periph/M09_AXI] [get_bd_intf_pins fitness/s_axi_control]
  connect_bd_intf_net -intf_net ps7_axi_periph_M10_AXI [get_bd_intf_pins ps7_axi_periph/M10_AXI] [get_bd_intf_pins fitness_reset/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M11_AXI [get_bd_intf_pins ps7_axi_periph/M11_AXI] [get_bd_intf_pins fitness_timing/S_AXI]
  connect_bd_intf_net -intf_net ps7_axi_periph_M12_AXI [get_bd_intf_pins ps7_axi_periph/M12_AXI] [get_bd_intf_pins display_osd/S_AXI]
  connect_bd_intf_net -intf_net qr_camera_cdc_M_AXIS [get_bd_intf_pins qr_camera_cdc/M_AXIS] [get_bd_intf_pins qr_preprocess_0/S_AXIS_VIDEO]
  connect_bd_intf_net -intf_net qr_capture_cdc_M_AXIS [get_bd_intf_pins qr_capture_cdc/M_AXIS] [get_bd_intf_pins qr_capture_vdma/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net qr_capture_vdma_M_AXI_S2MM [get_bd_intf_pins qr_capture_vdma/M_AXI_S2MM] [get_bd_intf_pins qr_memory/S00_AXI]
  connect_bd_intf_net -intf_net qr_memory_M00_AXI [get_bd_intf_pins qr_memory/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP1]
  connect_bd_intf_net -intf_net qr_preprocess_0_M_AXIS_IMAGE [get_bd_intf_pins qr_preprocess_0/M_AXIS_IMAGE] [get_bd_intf_pins qr_capture_cdc/S_AXIS]
  connect_bd_intf_net -intf_net qr_video_in_1 [get_bd_intf_ports qr_video_in] [get_bd_intf_pins qr_camera_cdc/S_AXIS]

  # Create port connections
  connect_bd_net -net camera_arm_gpio_io_o  [get_bd_pins camera_arm/gpio_io_o] \
  [get_bd_ports camera_arm_ctrl]
  connect_bd_net -net camera_iic_iic2intc_irpt  [get_bd_pins camera_iic/iic2intc_irpt] \
  [get_bd_pins interrupts/In4]
  connect_bd_net -net camera_reset_gpio_io_o  [get_bd_pins camera_reset/gpio_io_o] \
  [get_bd_ports camera_reset_ctrl]
  connect_bd_net -net diag_accepted_sof_1  [get_bd_ports diag_accepted_sof] \
  [get_bd_pins capture_timing/accepted_sof]
  connect_bd_net -net diag_arm_1  [get_bd_ports diag_arm] \
  [get_bd_pins capture_timing/arm]
  connect_bd_net -net diag_cam_clk_1  [get_bd_ports diag_cam_clk] \
  [get_bd_pins capture_timing/cam_clk]
  connect_bd_net -net diag_cam_resetn_1  [get_bd_ports diag_cam_resetn] \
  [get_bd_pins capture_timing/cam_resetn]
  connect_bd_net -net diag_cam_vsync_1  [get_bd_ports diag_cam_vsync] \
  [get_bd_pins capture_timing/cam_vsync]
  connect_bd_net -net diag_eof_toggle_1  [get_bd_ports diag_eof_toggle] \
  [get_bd_pins capture_timing/eof_toggle]
  connect_bd_net -net diag_gate_state_1  [get_bd_ports diag_gate_state] \
  [get_bd_pins capture_timing/gate_state]
  connect_bd_net -net diag_source_sof_1  [get_bd_ports diag_source_sof] \
  [get_bd_pins capture_timing/source_sof]
  connect_bd_net -net display_camera_cdc_m_axis_tuser  [get_bd_pins display_camera_cdc/m_axis_tuser] \
  [get_bd_pins display_sof/s_axis_tuser] \
  [get_bd_pins display_guard/stream_user]
  connect_bd_net -net display_camera_cdc_m_axis_tvalid  [get_bd_pins display_camera_cdc/m_axis_tvalid] \
  [get_bd_pins display_sof/s_axis_tvalid] \
  [get_bd_pins display_guard/stream_valid]
  connect_bd_net -net display_fault_or_Res  [get_bd_pins display_fault_or/Res] \
  [get_bd_pins display_osd/memory_fault]
  connect_bd_net -net display_guard_completed_frames  [get_bd_pins display_guard/completed_frames] \
  [get_bd_pins display_osd/committed_frames]
  connect_bd_net -net display_guard_errors  [get_bd_pins display_guard/errors] \
  [get_bd_pins display_osd/memory_errors]
  connect_bd_net -net display_guard_fault  [get_bd_pins display_guard/fault] \
  [get_bd_pins display_fault_or/Op1]
  connect_bd_net -net display_guard_read_tag_push  [get_bd_pins display_guard/read_tag_push] \
  [get_bd_pins display_identity/push]
  connect_bd_net -net display_guard_safe_video  [get_bd_pins display_guard/safe_video] \
  [get_bd_pins display_osd/safe_video]
  connect_bd_net -net display_guard_scan_tag  [get_bd_pins display_guard/scan_tag] \
  [get_bd_pins display_identity/fetched_tag]
  connect_bd_net -net display_guard_tag0  [get_bd_pins display_guard/tag0] \
  [get_bd_pins display_osd/tag0]
  connect_bd_net -net display_guard_tag1  [get_bd_pins display_guard/tag1] \
  [get_bd_pins display_osd/tag1]
  connect_bd_net -net display_guard_tag2  [get_bd_pins display_guard/tag2] \
  [get_bd_pins display_osd/tag2]
  connect_bd_net -net display_guard_valid_slots  [get_bd_pins display_guard/valid_slots] \
  [get_bd_pins display_osd/valid_slots]
  connect_bd_net -net display_identity_fault  [get_bd_pins display_identity/fault] \
  [get_bd_pins display_fault_or/Op2]
  connect_bd_net -net display_identity_scan_tag  [get_bd_pins display_identity/scan_tag] \
  [get_bd_pins display_osd/scan_tag]
  connect_bd_net -net display_identity_unique_frames  [get_bd_pins display_identity/unique_frames] \
  [get_bd_pins display_osd/unique_frames]
  connect_bd_net -net display_memory_S00_AXI_arready  [get_bd_pins display_memory/S00_AXI_arready] \
  [get_bd_pins display_vdma/m_axi_mm2s_arready] \
  [get_bd_pins display_guard/arready]
  connect_bd_net -net display_memory_S01_AXI_awready  [get_bd_pins display_memory/S01_AXI_awready] \
  [get_bd_pins display_vdma/m_axi_s2mm_awready] \
  [get_bd_pins display_guard/awready]
  connect_bd_net -net display_memory_S01_AXI_bresp  [get_bd_pins display_memory/S01_AXI_bresp] \
  [get_bd_pins display_vdma/m_axi_s2mm_bresp] \
  [get_bd_pins display_guard/bresp]
  connect_bd_net -net display_memory_S01_AXI_bvalid  [get_bd_pins display_memory/S01_AXI_bvalid] \
  [get_bd_pins display_vdma/m_axi_s2mm_bvalid] \
  [get_bd_pins display_guard/bvalid]
  connect_bd_net -net display_osd_base0  [get_bd_pins display_osd/base0] \
  [get_bd_pins display_guard/base0]
  connect_bd_net -net display_osd_base1  [get_bd_pins display_osd/base1] \
  [get_bd_pins display_guard/base1]
  connect_bd_net -net display_osd_base2  [get_bd_pins display_osd/base2] \
  [get_bd_pins display_guard/base2]
  connect_bd_net -net display_osd_capture_enable  [get_bd_pins display_osd/capture_enable] \
  [get_bd_ports r4_display_enable]
  connect_bd_net -net display_osd_clear_toggle  [get_bd_pins display_osd/clear_toggle] \
  [get_bd_ports r4_display_clear] \
  [get_bd_pins display_guard/clear] \
  [get_bd_pins display_identity/clear_toggle]
  connect_bd_net -net display_osd_out_de  [get_bd_pins display_osd/out_de] \
  [get_bd_pins display_rgb/de]
  connect_bd_net -net display_osd_out_hs  [get_bd_pins display_osd/out_hs] \
  [get_bd_pins display_rgb/hs]
  connect_bd_net -net display_osd_out_rgb  [get_bd_pins display_osd/out_rgb] \
  [get_bd_pins display_rgb/rgb]
  connect_bd_net -net display_osd_out_vs  [get_bd_pins display_osd/out_vs] \
  [get_bd_pins display_rgb/vs]
  connect_bd_net -net display_osd_source_epoch  [get_bd_pins display_osd/source_epoch] \
  [get_bd_ports r4_source_epoch]
  connect_bd_net -net display_rgb_hdmi_d  [get_bd_pins display_rgb/hdmi_d] \
  [get_bd_ports hdmi_d]
  connect_bd_net -net display_rgb_hdmi_de  [get_bd_pins display_rgb/hdmi_de] \
  [get_bd_ports hdmi_de]
  connect_bd_net -net display_rgb_hdmi_hs  [get_bd_pins display_rgb/hdmi_hs] \
  [get_bd_ports hdmi_hs]
  connect_bd_net -net display_rgb_hdmi_vs  [get_bd_pins display_rgb/hdmi_vs] \
  [get_bd_ports hdmi_vs]
  connect_bd_net -net display_sof_s_axis_tready  [get_bd_pins display_sof/s_axis_tready] \
  [get_bd_pins display_camera_cdc/m_axis_tready] \
  [get_bd_pins display_guard/stream_ready]
  connect_bd_net -net display_vdma_m_axi_mm2s_araddr  [get_bd_pins display_vdma/m_axi_mm2s_araddr] \
  [get_bd_pins display_memory/S00_AXI_araddr] \
  [get_bd_pins display_guard/araddr]
  connect_bd_net -net display_vdma_m_axi_mm2s_arvalid  [get_bd_pins display_vdma/m_axi_mm2s_arvalid] \
  [get_bd_pins display_memory/S00_AXI_arvalid] \
  [get_bd_pins display_guard/arvalid]
  connect_bd_net -net display_vdma_m_axi_s2mm_awaddr  [get_bd_pins display_vdma/m_axi_s2mm_awaddr] \
  [get_bd_pins display_memory/S01_AXI_awaddr] \
  [get_bd_pins display_guard/awaddr]
  connect_bd_net -net display_vdma_m_axi_s2mm_awlen  [get_bd_pins display_vdma/m_axi_s2mm_awlen] \
  [get_bd_pins display_memory/S01_AXI_awlen] \
  [get_bd_pins display_guard/awlen]
  connect_bd_net -net display_vdma_m_axi_s2mm_awsize  [get_bd_pins display_vdma/m_axi_s2mm_awsize] \
  [get_bd_pins display_memory/S01_AXI_awsize] \
  [get_bd_pins display_guard/awsize]
  connect_bd_net -net display_vdma_m_axi_s2mm_awvalid  [get_bd_pins display_vdma/m_axi_s2mm_awvalid] \
  [get_bd_pins display_memory/S01_AXI_awvalid] \
  [get_bd_pins display_guard/awvalid]
  connect_bd_net -net display_vdma_m_axi_s2mm_bready  [get_bd_pins display_vdma/m_axi_s2mm_bready] \
  [get_bd_pins display_memory/S01_AXI_bready] \
  [get_bd_pins display_guard/bready]
  connect_bd_net -net display_vdma_mm2s_introut  [get_bd_pins display_vdma/mm2s_introut] \
  [get_bd_pins interrupts/In0]
  connect_bd_net -net display_vdma_s2mm_introut  [get_bd_pins display_vdma/s2mm_introut] \
  [get_bd_pins interrupts/In6]
  connect_bd_net -net display_video_aclk_1  [get_bd_ports display_video_aclk] \
  [get_bd_pins display_camera_cdc/s_axis_aclk] \
  [get_bd_pins display_osd/cam_clk]
  connect_bd_net -net display_video_aresetn_1  [get_bd_ports display_video_aresetn] \
  [get_bd_pins display_camera_cdc/s_axis_aresetn] \
  [get_bd_pins display_osd/cam_resetn]
  connect_bd_net -net fitness_interrupt  [get_bd_pins fitness/interrupt] \
  [get_bd_pins interrupts/In5] \
  [get_bd_pins fitness_timing/tap_irq]
  connect_bd_net -net fitness_reset_and_Res  [get_bd_pins fitness_reset_and/Res] \
  [get_bd_pins fitness/ap_rst_n] \
  [get_bd_pins fitness_timing/tap_resetn]
  connect_bd_net -net fitness_reset_gpio_io_o  [get_bd_pins fitness_reset/gpio_io_o] \
  [get_bd_pins fitness_reset_and/Op2]
  connect_bd_net -net fitness_s_axi_control_AWREADY  [get_bd_pins fitness/s_axi_control_AWREADY] \
  [get_bd_pins ps7_axi_periph/M09_AXI_awready] \
  [get_bd_pins fitness_timing/tap_awready]
  connect_bd_net -net fitness_s_axi_control_WREADY  [get_bd_pins fitness/s_axi_control_WREADY] \
  [get_bd_pins ps7_axi_periph/M09_AXI_wready] \
  [get_bd_pins fitness_timing/tap_wready]
  connect_bd_net -net hdmi_iic_iic2intc_irpt  [get_bd_pins hdmi_iic/iic2intc_irpt] \
  [get_bd_pins interrupts/In1]
  connect_bd_net -net hdmi_reset_gpio_io_o  [get_bd_pins hdmi_reset/gpio_io_o] \
  [get_bd_ports hdmi_reset_n]
  connect_bd_net -net interrupts_dout  [get_bd_pins interrupts/dout] \
  [get_bd_pins ps7/IRQ_F2P]
  connect_bd_net -net pixel_clock_clk_out1  [get_bd_pins pixel_clock/clk_out1] \
  [get_bd_pins video_timing/pixel_clk] \
  [get_bd_pins display_vdma/m_axis_mm2s_aclk] \
  [get_bd_pins pixel_reset/slowest_sync_clk] \
  [get_bd_pins display_osd/pixel_clk] \
  [get_bd_pins display_identity/pixel_clk]
  connect_bd_net -net pixel_clock_locked  [get_bd_pins pixel_clock/locked] \
  [get_bd_pins pixel_reset/dcm_locked]
  connect_bd_net -net pixel_reset_peripheral_aresetn  [get_bd_pins pixel_reset/peripheral_aresetn] \
  [get_bd_pins video_timing/resetn] \
  [get_bd_pins display_osd/pixel_resetn] \
  [get_bd_pins display_identity/pixel_resetn]
  connect_bd_net -net ps7_FCLK_CLK0  [get_bd_pins ps7/FCLK_CLK0] \
  [get_bd_pins ps7/M_AXI_GP0_ACLK] \
  [get_bd_pins ps7_axi_periph/S00_ACLK] \
  [get_bd_pins rst_ps7_100M/slowest_sync_clk] \
  [get_bd_pins hdmi_iic/s_axi_aclk] \
  [get_bd_pins ps7_axi_periph/M00_ACLK] \
  [get_bd_pins ps7_axi_periph/ACLK] \
  [get_bd_pins hdmi_reset/s_axi_aclk] \
  [get_bd_pins ps7_axi_periph/M01_ACLK] \
  [get_bd_pins display_vdma/s_axi_lite_aclk] \
  [get_bd_pins ps7_axi_periph/M02_ACLK] \
  [get_bd_pins pixel_clock/clk_in1] \
  [get_bd_pins display_vdma/m_axi_mm2s_aclk] \
  [get_bd_pins ps7/S_AXI_HP0_ACLK] \
  [get_bd_pins display_memory/ACLK] \
  [get_bd_pins display_memory/S00_ACLK] \
  [get_bd_pins display_memory/S01_ACLK] \
  [get_bd_pins display_vdma/m_axi_s2mm_aclk] \
  [get_bd_pins display_vdma/s_axis_s2mm_aclk] \
  [get_bd_pins display_memory/M00_ACLK] \
  [get_bd_pins camera_iic/s_axi_aclk] \
  [get_bd_pins ps7_axi_periph/M03_ACLK] \
  [get_bd_pins camera_reset/s_axi_aclk] \
  [get_bd_pins ps7_axi_periph/M04_ACLK] \
  [get_bd_pins camera_arm/s_axi_aclk] \
  [get_bd_pins ps7_axi_periph/M05_ACLK] \
  [get_bd_pins qr_capture_vdma/s_axi_lite_aclk] \
  [get_bd_pins ps7_axi_periph/M06_ACLK] \
  [get_bd_pins qr_capture_vdma/m_axi_s2mm_aclk] \
  [get_bd_pins qr_capture_vdma/s_axis_s2mm_aclk] \
  [get_bd_pins qr_capture_cdc/m_axis_aclk] \
  [get_bd_pins ps7/S_AXI_HP1_ACLK] \
  [get_bd_pins qr_memory/ACLK] \
  [get_bd_pins qr_memory/S00_ACLK] \
  [get_bd_pins qr_memory/M00_ACLK] \
  [get_bd_pins capture_timing/aclk] \
  [get_bd_pins ps7_axi_periph/M08_ACLK] \
  [get_bd_pins fitness/ap_clk] \
  [get_bd_pins ps7_axi_periph/M09_ACLK] \
  [get_bd_pins fitness_reset/s_axi_aclk] \
  [get_bd_pins ps7_axi_periph/M10_ACLK] \
  [get_bd_pins fitness_memory/ACLK] \
  [get_bd_pins fitness_memory/S00_ACLK] \
  [get_bd_pins fitness_memory/M00_ACLK] \
  [get_bd_pins ps7/S_AXI_HP2_ACLK] \
  [get_bd_pins fitness_timing/aclk] \
  [get_bd_pins ps7_axi_periph/M11_ACLK] \
  [get_bd_pins display_osd/aclk] \
  [get_bd_pins ps7_axi_periph/M12_ACLK] \
  [get_bd_pins display_camera_cdc/m_axis_aclk] \
  [get_bd_pins display_sof/aclk] \
  [get_bd_pins display_guard/clk] \
  [get_bd_pins display_identity/aclk]
  connect_bd_net -net ps7_FCLK_CLK1  [get_bd_pins ps7/FCLK_CLK1] \
  [get_bd_pins qr_reset/slowest_sync_clk] \
  [get_bd_pins qr_preprocess_0/aclk] \
  [get_bd_pins ps7_axi_periph/M07_ACLK] \
  [get_bd_pins qr_camera_cdc/m_axis_aclk] \
  [get_bd_pins qr_capture_cdc/s_axis_aclk]
  connect_bd_net -net ps7_FCLK_RESET0_N  [get_bd_pins ps7/FCLK_RESET0_N] \
  [get_bd_pins rst_ps7_100M/ext_reset_in] \
  [get_bd_pins pixel_reset/ext_reset_in]
  connect_bd_net -net ps7_FCLK_RESET1_N  [get_bd_pins ps7/FCLK_RESET1_N] \
  [get_bd_pins qr_reset/ext_reset_in]
  connect_bd_net -net ps7_axi_periph_M09_AXI_awaddr  [get_bd_pins ps7_axi_periph/M09_AXI_awaddr] \
  [get_bd_pins fitness/s_axi_control_AWADDR] \
  [get_bd_pins fitness_timing/tap_awaddr]
  connect_bd_net -net ps7_axi_periph_M09_AXI_awvalid  [get_bd_pins ps7_axi_periph/M09_AXI_awvalid] \
  [get_bd_pins fitness/s_axi_control_AWVALID] \
  [get_bd_pins fitness_timing/tap_awvalid]
  connect_bd_net -net ps7_axi_periph_M09_AXI_wdata  [get_bd_pins ps7_axi_periph/M09_AXI_wdata] \
  [get_bd_pins fitness/s_axi_control_WDATA] \
  [get_bd_pins fitness_timing/tap_wdata]
  connect_bd_net -net ps7_axi_periph_M09_AXI_wstrb  [get_bd_pins ps7_axi_periph/M09_AXI_wstrb] \
  [get_bd_pins fitness/s_axi_control_WSTRB] \
  [get_bd_pins fitness_timing/tap_wstrb]
  connect_bd_net -net ps7_axi_periph_M09_AXI_wvalid  [get_bd_pins ps7_axi_periph/M09_AXI_wvalid] \
  [get_bd_pins fitness/s_axi_control_WVALID] \
  [get_bd_pins fitness_timing/tap_wvalid]
  connect_bd_net -net qr_aux_reset_inactive_dout  [get_bd_pins qr_aux_reset_inactive/dout] \
  [get_bd_pins qr_reset/aux_reset_in]
  connect_bd_net -net qr_capture_vdma_s2mm_introut  [get_bd_pins qr_capture_vdma/s2mm_introut] \
  [get_bd_pins interrupts/In2]
  connect_bd_net -net qr_debug_reset_inactive_dout  [get_bd_pins qr_debug_reset_inactive/dout] \
  [get_bd_pins qr_reset/mb_debug_sys_rst]
  connect_bd_net -net qr_preprocess_0_irq  [get_bd_pins qr_preprocess_0/irq] \
  [get_bd_pins interrupts/In3]
  connect_bd_net -net qr_reset_locked_dout  [get_bd_pins qr_reset_locked/dout] \
  [get_bd_pins qr_reset/dcm_locked]
  connect_bd_net -net qr_reset_peripheral_aresetn  [get_bd_pins qr_reset/peripheral_aresetn] \
  [get_bd_pins qr_preprocess_0/aresetn] \
  [get_bd_pins ps7_axi_periph/M07_ARESETN] \
  [get_bd_pins qr_camera_cdc/m_axis_aresetn] \
  [get_bd_pins qr_capture_cdc/s_axis_aresetn]
  connect_bd_net -net qr_video_in_aclk_1  [get_bd_ports qr_video_in_aclk] \
  [get_bd_pins qr_camera_cdc/s_axis_aclk]
  connect_bd_net -net qr_video_in_aresetn_1  [get_bd_ports qr_video_in_aresetn] \
  [get_bd_pins qr_camera_cdc/s_axis_aresetn]
  connect_bd_net -net r4_display_drops_1  [get_bd_ports r4_display_drops] \
  [get_bd_pins display_osd/display_drops]
  connect_bd_net -net r4_display_fault_1  [get_bd_ports r4_display_fault] \
  [get_bd_pins display_osd/display_fault]
  connect_bd_net -net r4_display_frames_1  [get_bd_ports r4_display_frames] \
  [get_bd_pins display_osd/display_frames]
  connect_bd_net -net r4_qr_drops_1  [get_bd_ports r4_qr_drops] \
  [get_bd_pins display_osd/qr_drops]
  connect_bd_net -net r4_source_frames_1  [get_bd_ports r4_source_frames] \
  [get_bd_pins display_osd/source_frames]
  connect_bd_net -net rst_ps7_100M_peripheral_aresetn  [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
  [get_bd_pins ps7_axi_periph/S00_ARESETN] \
  [get_bd_pins hdmi_iic/s_axi_aresetn] \
  [get_bd_pins ps7_axi_periph/M00_ARESETN] \
  [get_bd_pins ps7_axi_periph/ARESETN] \
  [get_bd_pins hdmi_reset/s_axi_aresetn] \
  [get_bd_pins ps7_axi_periph/M01_ARESETN] \
  [get_bd_pins display_vdma/axi_resetn] \
  [get_bd_pins ps7_axi_periph/M02_ARESETN] \
  [get_bd_pins display_memory/ARESETN] \
  [get_bd_pins display_memory/S00_ARESETN] \
  [get_bd_pins display_memory/S01_ARESETN] \
  [get_bd_pins display_memory/M00_ARESETN] \
  [get_bd_pins camera_iic/s_axi_aresetn] \
  [get_bd_pins ps7_axi_periph/M03_ARESETN] \
  [get_bd_pins camera_reset/s_axi_aresetn] \
  [get_bd_pins ps7_axi_periph/M04_ARESETN] \
  [get_bd_pins camera_arm/s_axi_aresetn] \
  [get_bd_pins ps7_axi_periph/M05_ARESETN] \
  [get_bd_pins qr_capture_vdma/axi_resetn] \
  [get_bd_pins ps7_axi_periph/M06_ARESETN] \
  [get_bd_pins qr_capture_cdc/m_axis_aresetn] \
  [get_bd_pins qr_memory/ARESETN] \
  [get_bd_pins qr_memory/S00_ARESETN] \
  [get_bd_pins qr_memory/M00_ARESETN] \
  [get_bd_ports pl_resetn] \
  [get_bd_pins capture_timing/aresetn] \
  [get_bd_pins ps7_axi_periph/M08_ARESETN] \
  [get_bd_pins ps7_axi_periph/M09_ARESETN] \
  [get_bd_pins fitness_reset/s_axi_aresetn] \
  [get_bd_pins ps7_axi_periph/M10_ARESETN] \
  [get_bd_pins fitness_reset_and/Op1] \
  [get_bd_pins fitness_memory/ARESETN] \
  [get_bd_pins fitness_memory/S00_ARESETN] \
  [get_bd_pins fitness_memory/M00_ARESETN] \
  [get_bd_pins fitness_timing/aresetn] \
  [get_bd_pins ps7_axi_periph/M11_ARESETN] \
  [get_bd_pins display_osd/aresetn] \
  [get_bd_pins ps7_axi_periph/M12_ARESETN] \
  [get_bd_pins display_camera_cdc/m_axis_aresetn] \
  [get_bd_pins display_sof/aresetn] \
  [get_bd_pins display_guard/resetn] \
  [get_bd_pins display_identity/aresetn]
  connect_bd_net -net video_timing_hdmi_clk  [get_bd_pins video_timing/hdmi_clk] \
  [get_bd_ports hdmi_clk]
  connect_bd_net -net video_timing_raw_de  [get_bd_pins video_timing/raw_de] \
  [get_bd_pins display_osd/pixel_de]
  connect_bd_net -net video_timing_raw_frame_start  [get_bd_pins video_timing/raw_frame_start] \
  [get_bd_pins display_identity/pixel_start]
  connect_bd_net -net video_timing_raw_hs  [get_bd_pins video_timing/raw_hs] \
  [get_bd_pins display_osd/pixel_hs]
  connect_bd_net -net video_timing_raw_rgb  [get_bd_pins video_timing/raw_rgb] \
  [get_bd_pins display_osd/pixel_rgb]
  connect_bd_net -net video_timing_raw_vs  [get_bd_pins video_timing/raw_vs] \
  [get_bd_pins display_osd/pixel_vs]
  connect_bd_net -net video_timing_raw_x  [get_bd_pins video_timing/raw_x] \
  [get_bd_pins display_osd/pixel_x]
  connect_bd_net -net video_timing_raw_y  [get_bd_pins video_timing/raw_y] \
  [get_bd_pins display_osd/pixel_y]

  # Create address segments
  assign_bd_address -offset 0x41220000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs camera_arm/S_AXI/Reg] -force
  assign_bd_address -offset 0x41600000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs camera_iic/S_AXI/Reg] -force
  assign_bd_address -offset 0x41210000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs camera_reset/S_AXI/Reg] -force
  assign_bd_address -offset 0x43C20000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs capture_timing/S_AXI/reg0] -force
  assign_bd_address -offset 0x43C40000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs display_osd/S_AXI/reg0] -force
  assign_bd_address -offset 0x43000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs display_vdma/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x43C10000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs fitness/s_axi_control/Reg] -force
  assign_bd_address -offset 0x41230000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs fitness_reset/S_AXI/Reg] -force
  assign_bd_address -offset 0x43C30000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs fitness_timing/S_AXI/reg0] -force
  assign_bd_address -offset 0x41610000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs hdmi_iic/S_AXI/Reg] -force
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs hdmi_reset/S_AXI/Reg] -force
  assign_bd_address -offset 0x43010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs qr_capture_vdma/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x43C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs qr_preprocess_0/s_axi/reg0] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces display_vdma/Data_MM2S] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces display_vdma/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces qr_capture_vdma/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces fitness/Data_m_axi_memory] [get_bd_addr_segs ps7/S_AXI_HP2/HP2_DDR_LOWOCM] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


