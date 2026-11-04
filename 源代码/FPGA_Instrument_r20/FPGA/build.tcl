set src [file normalize src]
create_project -name mega60k_j18_natural32_pressure_tjc -dir . -pn GW5AT-LV60PG484AC1/I0 -device_version B -force
foreach path [glob $src/*.mem $src/*.vh] {file copy -force $path [file tail $path]}
foreach path [glob $src/*.v] {add_file $path}
add_file $src/mega60k_j18_natural32_pressure_tjc.cst
add_file $src/timing.sdc
set_option -top_module top_j18_natural32_pressure_tjc
set_option -use_cpu_as_gpio 1
set_option -oreg_in_iob 0
set_option -place_option 1
run all
