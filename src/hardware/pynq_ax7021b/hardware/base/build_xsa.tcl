set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $script_dir .. ..]]
set project_name ax7021b_linux_base
set qr_desktop [expr {[info exists ::env(AX7021B_QR)] && $::env(AX7021B_QR) eq "1"}]
if {[info exists ::env(AX7021B_DESKTOP)] && $::env(AX7021B_DESKTOP) eq "1"} {set project_name ax7021b_linux_desktop}
if {$qr_desktop} {set project_name ax7021b_linux_qr_desktop}
set project_dir [file join $project_root work vivado $project_name]
if {$qr_desktop && [info exists ::env(AX7021B_QR_WORK_ROOT)]} {
    set project_dir [file join $::env(AX7021B_QR_WORK_ROOT) $project_name]
}
set project_file [file join $project_dir ${project_name}.xpr]
set output_dir [file join $project_root boards AX7021B petalinux_bsp hardware_project]
if {$qr_desktop} {set output_dir [file join $project_root output qr-diag45 hardware]}
if {$qr_desktop && [info exists ::env(AX7021B_QR_OUTPUT)]} {set output_dir $::env(AX7021B_QR_OUTPUT)}
set with_pwm [expr {![info exists ::env(AX7021B_NO_PWM)] || $::env(AX7021B_NO_PWM) ne "1"}]
set xsa_file [file join $output_dir ${project_name}.xsa]

if {![file exists $project_file]} {
    error "Project not found: $project_file. Run create_project.tcl first."
}

open_project $project_file
set_param general.maxThreads 2
set thread_hook [file join $script_dir limit_threads.tcl]
add_files -fileset utils_1 -norecurse $thread_hook
if {[info exists ::env(AX7021B_IP_CACHE)]} {
    file mkdir $::env(AX7021B_IP_CACHE)
    config_ip_cache -use_cache_location $::env(AX7021B_IP_CACHE)
}
foreach run [get_runs -filter {IS_SYNTHESIS == 1}] {
    set_property STEPS.SYNTH_DESIGN.TCL.PRE $thread_hook $run
    if {[get_property NAME $run] ne "synth_1" && [get_property PROGRESS $run] ne "100%"} {reset_run $run}
}
set_property STEPS.OPT_DESIGN.TCL.PRE $thread_hook [get_runs impl_1]

set jobs 2
if {[info exists ::env(AX7021B_JOBS)]} {set jobs $::env(AX7021B_JOBS)}
if {![string is integer -strict $jobs] || $jobs < 1} {error "AX7021B_JOBS must be a positive integer"}
set verify_only [expr {[info exists ::env(AX7021B_VERIFY_ONLY)] && $::env(AX7021B_VERIFY_ONLY) eq "1"}]
set reuse_impl [expr {[info exists ::env(AX7021B_REUSE_IMPL)] && $::env(AX7021B_REUSE_IMPL) eq "1"}]
set reuse_synth [expr {[info exists ::env(AX7021B_REUSE_SYNTH)] && $::env(AX7021B_REUSE_SYNTH) eq "1"}]
if {!$verify_only && !$reuse_impl} {
    if {!$reuse_synth} {
        reset_run synth_1
        launch_runs synth_1 -jobs $jobs
        wait_on_run synth_1
    }
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "Synthesis did not complete"
    }

    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "Implementation/bitstream did not complete"
    }
}
if {$reuse_impl} {
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Reusable implementation is incomplete"}
    set bit_top [expr {$qr_desktop ? "qr_desktop_top" : "system_wrapper"}]
    set implemented_bit [file join $project_dir ${project_name}.runs impl_1 ${bit_top}.bit]
    if {![file exists $implemented_bit]} {error "Reusable implementation has no bitstream"}
}

file mkdir $output_dir
open_run impl_1
# The union datapath keeps the original clocks; close any small routed setup
# deficit with physical optimization before exporting a deployable handoff.
if {$qr_desktop && [info exists ::env(AX7021B_ROI_PROFILE)] &&
    $::env(AX7021B_ROI_PROFILE) eq "b3a-145-union" &&
    [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {
    source [file join $project_root hardware qr_desktop roi_selection optimize_union_postroute.tcl]
}
report_timing_summary -file [file join $project_dir timing_summary.txt]
report_utilization -file [file join $project_dir utilization.txt]
report_bus_skew -file [file join $project_dir bus_skew.txt]
set bus_report [open [file join $project_dir bus_skew.txt] r]
set bus_text [read $bus_report];close $bus_report
if {[regexp {Slack\s+\(VIOLATED\)} $bus_text]} {error "Bus skew timing failed"}
report_drc -file [file join $project_dir drc.txt]
if {[llength [get_drc_violations -filter {SEVERITY == Error}]]} {error "DRC errors remain"}
report_io -file [file join $project_dir io.txt]
report_clock_networks -file [file join $project_dir clocks.txt]
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {error "Setup timing failed"}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {error "Hold timing failed"}
if {$project_name in {ax7021b_linux_desktop ax7021b_linux_qr_desktop}} {
    if {[llength [get_clocks hdmi_forwarded]] != 1} {error "HDMI sampling clock not constrained"}
    open_bd_design [file join $project_dir ${project_name}.srcs sources_1 bd system system.bd]
    foreach {property expected} {PCW_USB0_PERIPHERAL_ENABLE 1 PCW_USB0_USB0_IO {MIO 28 .. 39} PCW_USB0_RESET_IO {MIO 8} PCW_USE_S_AXI_HP0 1} {
        if {[get_property CONFIG.$property [get_bd_cells ps7]] ne $expected} {error "PS configuration mismatch: $property"}
    }
    foreach pin {display_vdma/mm2s_introut hdmi_iic/iic2intc_irpt ps7/IRQ_F2P ps7/S_AXI_HP0_ACLK} {
        if {[llength [get_bd_nets -of_objects [get_bd_pins $pin]]] != 1} {error "Disconnected hardware pin: $pin"}
    }
    if {$with_pwm} {
    if {[llength [get_bd_cells pwm_axi_v1_0_0]] != 1} {error "PWM IP is missing from desktop design"}
    if {[llength [get_bd_nets -of_objects [get_bd_pins pwm_axi_v1_0_0/pwm_led_n]]] != 1} {
        error "PWM LED output is disconnected"
    }
    set pwm_seg [get_bd_addr_segs -quiet -filter {NAME =~ *SEG_pwm_axi_v1_0_0_reg0}]
    if {[llength $pwm_seg] != 1} {error "Expected one assigned PWM address segment"}
    set pwm_offset [string toupper [get_property OFFSET $pwm_seg]]
    set pwm_range [string toupper [get_property RANGE $pwm_seg]]
    if {$pwm_offset ne "0X43C10000" || $pwm_range ni {64K 0X00010000}} {
        error "PWM address mapping mismatch"
    }
    } elseif {[llength [get_bd_cells -quiet pwm_axi_v1_0_0]] != 0} {error "Unexpected PWM in no-PWM profile"}
    write_bd_tcl -force [file join $project_dir validated_system.tcl]
}
if {$qr_desktop} {
    open_bd_design [file join $project_dir ${project_name}.srcs sources_1 bd system system.bd]
    set audit [open [file join $output_dir qr_address_interrupt_audit.txt] w]
    set audit_addresses {
        display_vdma 0x43000000
        qr_capture_vdma 0x43010000
        qr_preprocess_0 0x43C00000
        camera_iic 0x41600000
        hdmi_iic 0x41610000
        camera_reset 0x41210000
        camera_arm 0x41220000
        capture_timing 0x43C20000
    }
    if {[info exists ::env(AX7021B_FITNESS_IP)]} {lappend audit_addresses fitness 0x43C10000 fitness_reset 0x41230000}
    if {$with_pwm} {lappend audit_addresses pwm_axi_v1_0_0 0x43C10000}
    foreach {cell expected} $audit_addresses {
        set matches [get_bd_addr_segs -quiet -filter "NAME =~ *${cell}* && OFFSET == ${expected}"]
        if {[llength $matches] != 1} {error "QR address audit failed for $cell at $expected"}
        puts $audit "$cell $expected [get_property RANGE $matches]"
    }
    foreach pin {ps7/S_AXI_HP1_ACLK qr_capture_vdma/s2mm_introut qr_preprocess_0/irq camera_iic/iic2intc_irpt} {
        if {[llength [get_bd_nets -of_objects [get_bd_pins $pin]]] != 1} {error "Disconnected QR hardware pin: $pin"}
    }
    foreach {cell expected pin} {
        qr_reset_locked 1 qr_reset/dcm_locked
        qr_aux_reset_inactive 1 qr_reset/aux_reset_in
        qr_debug_reset_inactive 0 qr_reset/mb_debug_sys_rst
    } {
        if {[llength [get_bd_cells $cell]] != 1 ||
            [get_property CONFIG.CONST_VAL [get_bd_cells $cell]] ne $expected} {
            error "QR reset constant mismatch: $cell must be $expected"
        }
        set constant_net [get_bd_nets -of_objects [get_bd_pins ${cell}/dout]]
        if {[get_bd_nets -of_objects [get_bd_pins $pin]] ne $constant_net} {
            error "QR reset connection mismatch: $cell -> $pin"
        }
    }
    if {[get_bd_nets -of_objects [get_bd_pins capture_timing/aclk]] ne [get_bd_nets -of_objects [get_bd_pins ps7/FCLK_CLK0]]} {error "Capture timing clock mismatch"}
    set expected_irqs 5
    if {[info exists ::env(AX7021B_FITNESS_IP)]} {set expected_irqs 7}
    if {[get_property CONFIG.NUM_PORTS [get_bd_cells interrupts]] ne $expected_irqs} {error "QR interrupt count mismatch"}
    if {[get_property CONFIG.PCW_USE_S_AXI_HP1 [get_bd_cells ps7]] ne "1"} {error "QR capture HP1 is disabled"}
    if {[get_property CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ [get_bd_cells ps7]] ne "76.923080"} {
        error "QR FCLK1 must resolve to 76.923080 MHz"
    }
    if {[info exists ::env(AX7021B_FITNESS_IP)]} {
        if {[get_property CONFIG.PCW_USE_S_AXI_HP2 [get_bd_cells ps7]] ne "1"} {error "Fitness HP2 disabled"}
        if {[get_bd_nets -of_objects [get_bd_pins fitness/interrupt]] ne [get_bd_nets -of_objects [get_bd_pins interrupts/In5]]} {error "Fitness IRQ mismatch"}
        foreach pin {fitness/ap_clk ps7/S_AXI_HP2_ACLK} {
            if {[get_bd_nets -of_objects [get_bd_pins $pin]] ne [get_bd_nets -of_objects [get_bd_pins ps7/FCLK_CLK0]]} {error "Fitness clock mismatch: $pin"}
        }
        puts $audit "fitness=0x43C10000 reset=0x41230000 memory=HP2 interrupt=In5/SPI34 clock=FCLK0@100MHz"
    }
    set qr_clock_net [get_bd_nets -of_objects [get_bd_pins ps7/FCLK_CLK1]]
    foreach pin {qr_preprocess_0/aclk qr_camera_cdc/m_axis_aclk qr_capture_cdc/s_axis_aclk} {
        if {[get_bd_nets -of_objects [get_bd_pins $pin]] ne $qr_clock_net} {
            error "QR compute clock mismatch on $pin"
        }
    }
    puts $audit "interrupts In0=display_vdma In1=hdmi_iic In2=qr_capture_vdma In3=qr_preprocess In4=camera_iic"
    puts $audit "memory display=HP0 qr_capture=HP1"
    puts $audit "clocks desktop=FCLK0@100MHz qr_compute=FCLK1@76.923080MHz"
    close $audit
}
if {!$verify_only} {
    foreach report {timing_summary.txt drc.txt io.txt clocks.txt bus_skew.txt validated_system.tcl utilization.txt} {
        set source [file join $project_dir $report]
        if {[file exists $source]} {file copy -force $source [file join $output_dir $report]}
    }
    write_hw_platform -fixed -include_bit -force -file $xsa_file
}
puts "AX7021B_LINUX_BASE_XSA=$xsa_file"
