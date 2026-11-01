set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $script_dir .. ..]]
set repo_root [file normalize [file join $project_root ..]]
set source_root [file join $repo_root qr_diag45_20261018 qr_video_replay rtl]
set package_project [file join $project_root work vivado qr_camera_ip_package]
set out_dir [file join $project_root work ip qr_preprocess_camera]

if {[info exists ::env(AX7021B_QR_WORK_ROOT)]} {
    set package_project [file join $::env(AX7021B_QR_WORK_ROOT) ip_package]
    set out_dir [file join $::env(AX7021B_QR_WORK_ROOT) ip qr_preprocess_camera]
}
set derived [file join $script_dir roi_selection rtl]
set use_derived [info exists ::env(AX7021B_ROI_PROFILE)]
foreach p [list $package_project $out_dir] {
 if {![info exists ::env(AX7021B_QR_WORK_ROOT)] || ![string match "[file normalize $::env(AX7021B_QR_WORK_ROOT)]/*" [file normalize $p]]} {error "Package output escapes isolated work root"}
 if {[file exists $p]} {error "Use a fresh build directory: $p"}
}
create_project qr_camera_ip_package $package_project -part xc7z020clg484-2 -force
set_property target_language Verilog [current_project]
foreach name {
    qr_preprocess_camera_optimized.v
    qr_capture_row_pack.v
    qr_preprocess_camera_legacy.v
    qr_pl_roi_stream.v
    qr_threshold_interp.v
    qr_otsu_grid.v
    qr_otsu_grid_solver.v
    qr_otsu_threshold.v
    qr_otsu_five.v
    qr_sample_windows.v
    qr_otsu_sampled.v
    qr_finder_diag_stream.v
    qr_finder_stream.v
    qr_finder_roi.v
} {
    set source [file join $source_root $name]
    if {$use_derived && [file exists [file join $derived $name]]} {set source [file join $derived $name]}
    if {![file exists $source]} {error "Missing QR RTL source: $source"}
    add_files -norecurse $source
}
if {$use_derived} {add_files -norecurse [file join $derived qr_roi_selector.v]}
set_property top qr_preprocess_top [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $out_dir -vendor user.org -library user -taxonomy /UserIP -import_files -force
set core [ipx::current_core]
set_property name qr_preprocess $core
set_property version 1.0 $core
set_property display_name {QR Camera Preprocess} $core
set_property description {Mainline Gray8/Otsu/ROI30 camera preprocessing for static Linux-PYNQ} $core
set_property vendor_display_name {XIWEI} $core
foreach bi [ipx::get_bus_interfaces * -of_objects $core] {
    set name [get_property NAME $bi]
    if {$name in {S_AXI s_axi}} {set_property NAME S_AXI_CTRL $bi}
    if {$name in {S_AXIS_VIDEO s_axis_video}} {set_property NAME S_AXIS_VIDEO $bi}
    if {$name in {M_AXIS_IMAGE m_axis_image}} {set_property NAME M_AXIS_IMAGE $bi}
}
set clock [ipx::get_bus_interfaces aclk -of_objects $core]
if {[llength $clock] == 1} {
    set parameter [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clock]
    if {[llength $parameter] == 0} {set parameter [ipx::add_bus_parameter ASSOCIATED_BUSIF $clock]}
    set_property value {M_AXIS_IMAGE:S_AXIS_VIDEO:S_AXI_CTRL} $parameter
    set frequency [ipx::get_bus_parameters FREQ_HZ -of_objects $clock]
    if {[llength $frequency] == 0} {set frequency [ipx::add_bus_parameter FREQ_HZ $clock]}
    # PS7's requested 80 MHz FCLK1 resolves to the timing-qualified 76.923080 MHz.
    set_property value 76923080 $frequency
}
ipx::save_core $core
ipx::check_integrity $core
puts "QR_CAMERA_IP_PACKAGE=$out_dir"
