vlib work
vmap work work 

#compilation order is important!
vcom -work work core_pack.vhd
vcom -work work op_pack.vhd

vcom -work work -2008 jmpu.vhd
