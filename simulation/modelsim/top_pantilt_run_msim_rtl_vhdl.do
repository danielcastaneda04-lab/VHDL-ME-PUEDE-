transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/pwm_servo.vhd}
vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/top_pantilt.vhd}
vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/bcd_7seg.vhd}
vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/hex7seg.vhd}
vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/UART_RX.vhd}
vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/parser_cmd.vhd}

vcom -93 -work work {C:/altera/13.0sp1/Electro_DigII/LAB_I_2/tb_top_pantilt.vhd}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L cycloneii -L rtl_work -L work -voptargs="+acc"  tb_top_pantilt

add wave *
view structure
view signals
run -all
