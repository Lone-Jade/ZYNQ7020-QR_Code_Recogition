## AX7021B AN5642 CMOS1 on J16; HDMI constraints remain owned by desktop/hdmi.xdc.
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_d[*]}]
set_property PACKAGE_PIN AA6 [get_ports {cam1_d[9]}]
set_property PACKAGE_PIN AA7 [get_ports {cam1_d[8]}]
set_property PACKAGE_PIN AB2 [get_ports {cam1_d[0]}]
set_property PACKAGE_PIN AA4 [get_ports {cam1_d[1]}]
set_property PACKAGE_PIN AB10 [get_ports {cam1_d[2]}]
set_property PACKAGE_PIN AB4 [get_ports {cam1_d[3]}]
set_property PACKAGE_PIN AB5 [get_ports {cam1_d[4]}]
set_property PACKAGE_PIN AB11 [get_ports {cam1_d[5]}]
set_property PACKAGE_PIN AB1 [get_ports {cam1_d[6]}]
set_property PACKAGE_PIN Y4 [get_ports {cam1_d[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam1_pclk cam1_href cam1_vsync cam1_reset_n cam1_sda cam1_scl}]
set_property PACKAGE_PIN AB9 [get_ports cam1_pclk]
set_property PACKAGE_PIN AA9 [get_ports cam1_href]
set_property PACKAGE_PIN AA8 [get_ports cam1_vsync]
set_property PACKAGE_PIN AB7 [get_ports cam1_reset_n]
set_property PACKAGE_PIN V8 [get_ports cam1_sda]
set_property PACKAGE_PIN AA11 [get_ports cam1_scl]
set_property PULLUP true [get_ports {cam1_sda cam1_scl}]
create_clock -name cam1_pclk -period 9.700 [get_ports cam1_pclk]
# AB9 is the fixed AN5642 connector PCLK pin and is not a clock-capable IO.
# Preserve the board routing used by the validated bare-metal design while
# retaining cam1_pclk as a timed clock domain.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam1_pclk_IBUF]
set_false_path -to [get_pins -hier -filter {REF_PIN_NAME == CLR && NAME =~ *camera_reset_sync_reg*}]
set_false_path -to [get_pins {gate_i/arm_sync_reg[0]/D}]

# Only the first stages of passive toggle/state synchronizers cross clocks.
set_false_path -to [get_pins -hier -filter {NAME =~ *capture_timing*sync0_reg*/D || NAME =~ *capture_timing*state0_reg*/D}]
