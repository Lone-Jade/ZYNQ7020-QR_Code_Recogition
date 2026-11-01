if {$argc != 2} {error "usage: xsct build_qr_fsbl.tcl INPUT.xsa OUTPUT.elf"}
set xsa [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
if {![file exists $xsa]} {error "XSA not found: $xsa"}

set workspace [file normalize [file join [file dirname $output] fsbl-work]]
# Legacy XSCT launches an Eclipse command service. Keep its configuration in
# this fresh build directory, rather than requiring writes to ~/.Xilinx.
set ::ac_eclipse_configuration [file join [file dirname $output] eclipse-configuration]
rename ::xsdb::get_eclipseargs ::xsdb::ac_original_eclipseargs
proc ::xsdb::get_eclipseargs {} {
    return [concat [::xsdb::ac_original_eclipseargs] [list -configuration $::ac_eclipse_configuration]]
}
if {[file exists $workspace]} {error "Use a fresh output directory: $workspace"}
file mkdir $workspace
setws $workspace
app create -name qr_fsbl -hw $xsa -proc ps7_cortexa9_0 -os standalone \
    -template {Zynq FSBL}
app build -name qr_fsbl
set elf [file join $workspace qr_fsbl Debug qr_fsbl.elf]
if {![file exists $elf]} {error "FSBL build did not produce $elf"}
file copy -force $elf $output
puts "QR_FSBL=$output"
exit 0
