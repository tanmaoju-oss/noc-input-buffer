# Transcribed from E:\Codex-Project\cc-work\Daily\photo1.jpg and photo2.jpg, Michael Tan, 20260803
# Source filename shown in the photos: soc_dcpu_j2.xdc
# The photos end at the DDR heading; no unseen DDR constraints are reproduced here.

## Reset
set_property IOSTANDARD LVCMOS18 [get_ports l_pad_rst_b]
set_property PACKAGE_PIN R12 [get_ports l_pad_rst_b]

## Clock
set_property IOSTANDARD DIFF_SSTL12 [get_ports l_pad_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports l_pad_clk_n]
set_property PACKAGE_PIN AT49 [get_ports l_pad_clk_p]
set_property PACKAGE_PIN AU49 [get_ports l_pad_clk_n]
create_clock -period 10.000 [get_ports l_pad_clk_p]

################JTAG-J2################

#set_property PACKAGE_PIN F14 [get_ports l_pad_jtg_tclk]
#set_property PACKAGE_PIN M15 [get_ports l_pad_jtg_tdi]
#set_property PACKAGE_PIN M16 [get_ports l_pad_jtg_tms]
#set_property PACKAGE_PIN E16 [get_ports l_pad_jtg_trst_b]
#set_property PACKAGE_PIN F12 [get_ports o_pad_jtg_tdo]
#set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_tclk]
#set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_tdi]
#set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_tms]
#set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_trst_b]
#set_property IOSTANDARD LVCMOS18 [get_ports o_pad_jtg_tdo]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets l_pad_jtg_tclk_IBUF_inst/O]

################JTAG-J4################
set_property PACKAGE_PIN D51 [get_ports l_pad_jtg_tclk]
set_property PACKAGE_PIN F48 [get_ports l_pad_jtg_tdi]
set_property PACKAGE_PIN F47 [get_ports l_pad_jtg_tms]
set_property PACKAGE_PIN D53 [get_ports l_pad_jtg_trst_b]
set_property PACKAGE_PIN A50 [get_ports o_pad_jtg_tdo]
set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_tclk]
set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_tdi]
set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_tms]
set_property IOSTANDARD LVCMOS18 [get_ports l_pad_jtg_trst_b]
set_property IOSTANDARD LVCMOS18 [get_ports o_pad_jtg_tdo]

#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets l_pad_jtg_j4_tclk_IBUF_inst/O]

################SPI-SD-J2################
#set_property IOSTANDARD LVCMOS18 [get_ports spi_mosi]
#set_property IOSTANDARD LVCMOS18 [get_ports spi_miso]
#set_property IOSTANDARD LVCMOS18 [get_ports spi_ss]
#set_property IOSTANDARD LVCMOS18 [get_ports spi_clk_o]
#set_property PACKAGE_PIN F14 [get_ports spi_mosi]
#set_property PACKAGE_PIN J24 [get_ports spi_miso]
#set_property PACKAGE_PIN H24 [get_ports spi_ss]
#set_property PACKAGE_PIN G24 [get_ports spi_clk_o]

################SPI-SD-J4################
set_property IOSTANDARD LVCMOS18 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS18 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS18 [get_ports spi_ss]
set_property IOSTANDARD LVCMOS18 [get_ports spi_clk_o]
set_property PACKAGE_PIN U42 [get_ports spi_mosi]
set_property PACKAGE_PIN T44 [get_ports spi_miso]
set_property PACKAGE_PIN T45 [get_ports spi_ss]
set_property PACKAGE_PIN V42 [get_ports spi_clk_o]

set_property IOSTANDARD LVCMOS18 [get_ports o_ddr_init_led]
set_property PACKAGE_PIN R32 [get_ports o_ddr_init_led]
#set_property IOSTANDARD LVCMOS18 [get_ports owarning]
#set_property PACKAGE_PIN T30 [get_ports owarning]

################uart-subJ2################
#set_property IOSTANDARD LVCMOS18 [get_ports o_pad_uart0_sout]
#set_property IOSTANDARD LVCMOS18 [get_ports l_pad_uart0_sin]
#set_property PACKAGE_PIN P23 [get_ports o_pad_uart0_sout]
#set_property PACKAGE_PIN M24 [get_ports l_pad_uart0_sin]

################uart-subJ4################
set_property IOSTANDARD LVCMOS18 [get_ports o_pad_uart0_sout]
set_property IOSTANDARD LVCMOS18 [get_ports l_pad_uart0_sin]
set_property PACKAGE_PIN V49 [get_ports o_pad_uart0_sout]
set_property PACKAGE_PIN V51 [get_ports l_pad_uart0_sin]

################uart-master################
#set_property IOSTANDARD LVCMOS18 [get_ports uart_cpu1_out]
#set_property IOSTANDARD LVCMOS18 [get_ports uart_cpu1_in]
#set_property PACKAGE_PIN BM26 [get_ports uart_cpu1_out]
#set_property PACKAGE_PIN BK25 [get_ports uart_cpu1_in]

################DDR################
# The supplied photo stops here. Obtain the original XDC before using DDR.
