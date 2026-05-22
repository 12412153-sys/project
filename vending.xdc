# ============================================================
# EGO1 (xc7a35tcsg324-1) Constraint File
# Drink Vending Machine project
# ============================================================

# ------------------------------------------------------------
# System clock (100 MHz)
# ------------------------------------------------------------
set_property PACKAGE_PIN P17 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# ------------------------------------------------------------
# Global reset (CPU_RESETN, active-low, S6)
# ------------------------------------------------------------
set_property PACKAGE_PIN P15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ------------------------------------------------------------
# General-purpose buttons (active-high when pressed)
# S0=R11  S1=R17  S2=R15  S3=V1  S4=U4
# ------------------------------------------------------------
set_property PACKAGE_PIN R11 [get_ports {btn[0]}]
set_property PACKAGE_PIN R17 [get_ports {btn[1]}]
set_property PACKAGE_PIN R15 [get_ports {btn[2]}]
set_property PACKAGE_PIN V1  [get_ports {btn[3]}]
set_property PACKAGE_PIN U4  [get_ports {btn[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[*]}]

# ------------------------------------------------------------
# DIP switches (SW0-SW7, active-high when on)
# ------------------------------------------------------------
set_property PACKAGE_PIN R1  [get_ports {sw[0]}]
set_property PACKAGE_PIN N4  [get_ports {sw[1]}]
set_property PACKAGE_PIN M4  [get_ports {sw[2]}]
set_property PACKAGE_PIN R2  [get_ports {sw[3]}]
set_property PACKAGE_PIN P2  [get_ports {sw[4]}]
set_property PACKAGE_PIN P3  [get_ports {sw[5]}]
set_property PACKAGE_PIN P4  [get_ports {sw[6]}]
set_property PACKAGE_PIN P5  [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

# ------------------------------------------------------------
# PS/2 keyboard (USB-to-PS2 via on-board PIC24FJ128)
# ------------------------------------------------------------
set_property PACKAGE_PIN K5 [get_ports ps2_clk]
set_property PACKAGE_PIN L4 [get_ports ps2_data]
set_property IOSTANDARD LVCMOS33 [get_ports ps2_clk]
set_property IOSTANDARD LVCMOS33 [get_ports ps2_data]

# ------------------------------------------------------------
# 7-segment display  -- active-high, common-cathode
# DN0 (right 4 digits): segment lines seg0[7:0] = {dp,g,f,e,d,c,b,a}
# DN1 (left  4 digits): segment lines seg1[7:0] = {dp,g,f,e,d,c,b,a}
# Position select (AN) active-high: an[0]=rightmost(BIT1) .. an[7]=leftmost(BIT8)
# ------------------------------------------------------------
# seg0: DN0 segments
set_property PACKAGE_PIN B4 [get_ports {seg0[0]}]
set_property PACKAGE_PIN A4 [get_ports {seg0[1]}]
set_property PACKAGE_PIN A3 [get_ports {seg0[2]}]
set_property PACKAGE_PIN B1 [get_ports {seg0[3]}]
set_property PACKAGE_PIN A1 [get_ports {seg0[4]}]
set_property PACKAGE_PIN B3 [get_ports {seg0[5]}]
set_property PACKAGE_PIN B2 [get_ports {seg0[6]}]
set_property PACKAGE_PIN D5 [get_ports {seg0[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[*]}]

# seg1: DN1 segments
set_property PACKAGE_PIN D4 [get_ports {seg1[0]}]
set_property PACKAGE_PIN E3 [get_ports {seg1[1]}]
set_property PACKAGE_PIN D3 [get_ports {seg1[2]}]
set_property PACKAGE_PIN F4 [get_ports {seg1[3]}]
set_property PACKAGE_PIN F3 [get_ports {seg1[4]}]
set_property PACKAGE_PIN E2 [get_ports {seg1[5]}]
set_property PACKAGE_PIN D2 [get_ports {seg1[6]}]
set_property PACKAGE_PIN H2 [get_ports {seg1[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[*]}]

# Position select: BIT1(G2)=an[0] rightmost .. BIT8(G6)=an[7] leftmost
set_property PACKAGE_PIN G2 [get_ports {an[0]}]
set_property PACKAGE_PIN C2 [get_ports {an[1]}]
set_property PACKAGE_PIN C1 [get_ports {an[2]}]
set_property PACKAGE_PIN H1 [get_ports {an[3]}]
set_property PACKAGE_PIN G1 [get_ports {an[4]}]
set_property PACKAGE_PIN F1 [get_ports {an[5]}]
set_property PACKAGE_PIN E1 [get_ports {an[6]}]
set_property PACKAGE_PIN G6 [get_ports {an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

# ------------------------------------------------------------
# LEDs  (active-high)
# D1 group (LED[7:0]): K3 M1 L1 K6 J5 H5 H6 K1
# D2 group (LED[15:8]): K2 J2 J3 H4 J4 G3 G4 F6
# ------------------------------------------------------------
set_property PACKAGE_PIN K3 [get_ports {led[0]}]
set_property PACKAGE_PIN M1 [get_ports {led[1]}]
set_property PACKAGE_PIN L1 [get_ports {led[2]}]
set_property PACKAGE_PIN K6 [get_ports {led[3]}]
set_property PACKAGE_PIN J5 [get_ports {led[4]}]
set_property PACKAGE_PIN H5 [get_ports {led[5]}]
set_property PACKAGE_PIN H6 [get_ports {led[6]}]
set_property PACKAGE_PIN K1 [get_ports {led[7]}]
set_property PACKAGE_PIN K2 [get_ports {led[8]}]
set_property PACKAGE_PIN J2 [get_ports {led[9]}]
set_property PACKAGE_PIN J3 [get_ports {led[10]}]
set_property PACKAGE_PIN H4 [get_ports {led[11]}]
set_property PACKAGE_PIN J4 [get_ports {led[12]}]
set_property PACKAGE_PIN G3 [get_ports {led[13]}]
set_property PACKAGE_PIN G4 [get_ports {led[14]}]
set_property PACKAGE_PIN F6 [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ------------------------------------------------------------
# Audio (buzzer via on-board low-pass filter)
# ------------------------------------------------------------
set_property PACKAGE_PIN T1 [get_ports aud_pwm]
set_property PACKAGE_PIN M6 [get_ports aud_sd]
set_property IOSTANDARD LVCMOS33 [get_ports aud_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports aud_sd]

# ------------------------------------------------------------
# VGA (Bonus -- pins pre-assigned, leave unconnected if unused)
# ------------------------------------------------------------
#set_property PACKAGE_PIN F5 [get_ports {VGA_R[0]}]
#set_property PACKAGE_PIN C6 [get_ports {VGA_R[1]}]
#set_property PACKAGE_PIN C5 [get_ports {VGA_R[2]}]
#set_property PACKAGE_PIN B7 [get_ports {VGA_R[3]}]
#set_property PACKAGE_PIN B6 [get_ports {VGA_G[0]}]
#set_property PACKAGE_PIN A6 [get_ports {VGA_G[1]}]
#set_property PACKAGE_PIN A5 [get_ports {VGA_G[2]}]
#set_property PACKAGE_PIN D8 [get_ports {VGA_G[3]}]
#set_property PACKAGE_PIN C7 [get_ports {VGA_B[0]}]
#set_property PACKAGE_PIN E6 [get_ports {VGA_B[1]}]
#set_property PACKAGE_PIN E5 [get_ports {VGA_B[2]}]
#set_property PACKAGE_PIN E7 [get_ports {VGA_B[3]}]
#set_property PACKAGE_PIN D7 [get_ports VGA_HS]
#set_property PACKAGE_PIN C4 [get_ports VGA_VS]
#set_property IOSTANDARD LVCMOS33 [get_ports {VGA_R[*]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {VGA_G[*]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {VGA_B[*]}]
#set_property IOSTANDARD LVCMOS33 [get_ports VGA_HS]
#set_property IOSTANDARD LVCMOS33 [get_ports VGA_VS]
