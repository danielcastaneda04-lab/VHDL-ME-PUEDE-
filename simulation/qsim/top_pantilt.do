onerror {quit -f}
vlib work
vlog -work work top_pantilt.vo
vlog -work work top_pantilt.vt
vsim -novopt -c -t 1ps -L cycloneii_ver -L altera_ver -L altera_mf_ver -L 220model_ver -L sgate work.top_pantilt_vlg_vec_tst
vcd file -direction top_pantilt.msim.vcd
vcd add -internal top_pantilt_vlg_vec_tst/*
vcd add -internal top_pantilt_vlg_vec_tst/i1/*
add wave /*
run -all
