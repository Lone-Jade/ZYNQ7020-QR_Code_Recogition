# Optional closure for the union profile; no clock/exception changes.
set before_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
set after_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set after_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
file mkdir $output_dir
set record [open [file join $output_dir POSTROUTE-OPTIMIZATION.txt] w]
puts $record "profile=b3a-145-union"
puts $record "before_setup_ns=$before_setup"
puts $record "phys_opt_design=-directive AggressiveExplore"
puts $record "route_design=-directive Explore"
puts $record "after_setup_ns=$after_setup"
puts $record "after_hold_ns=$after_hold"
close $record
if {$after_setup < 0 || $after_hold < 0} {error "Union post-route timing closure failed"}
set run_dir [file join $project_dir ${project_name}.runs impl_1]
write_checkpoint -force [file join $run_dir qr_desktop_top_routed.dcp]
write_bitstream -force [file join $run_dir qr_desktop_top.bit]
report_bus_skew -file [file join $run_dir qr_desktop_top_bus_skew_routed.rpt]
