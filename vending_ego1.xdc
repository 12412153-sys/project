## =============================================================================
##  File        : vending_ego1.xdc
##  Project     : FPGA 饮料售货机
##  Board       : EGO1 (XC7A35T-1CSG324C)
##  Author      : Member C
##
##  所有信号名与 drink_vending_top.v 顶层端口一一对应。
##
##  硬件特性说明（与信号驱动方式相关）：
##    数码管：共阴极，SEG0/SEG1/AN 均高电平有效
##    音频：标准推挽，直接 0/1 驱动（无需 open-drain）
##    LED：高电平点亮
##    按键：按下=高电平，默认低电平
## =============================================================================

## ─────────────────────────────────────────────────────────────────────────────
## 1. 系统时钟  100 MHz → P17
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN P17  IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { CLK100MHZ }]

## ─────────────────────────────────────────────────────────────────────────────
## 2. 复位按键  S6 → P15，低有效
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN P15  IOSTANDARD LVCMOS33 } [get_ports { CPU_RESETN }]

## ─────────────────────────────────────────────────────────────────────────────
## 3. 五个通用按键（按下=高电平）
##    BTN[0]=S0=R11  确认/取货
##    BTN[1]=S1=R17  返回主菜单
##    BTN[2]=S2=R15  取消/下翻
##    BTN[3]=S3=V1   左
##    BTN[4]=S4=U4   右
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN R11  IOSTANDARD LVCMOS33 } [get_ports { BTN[0] }]
set_property -dict { PACKAGE_PIN R17  IOSTANDARD LVCMOS33 } [get_ports { BTN[1] }]
set_property -dict { PACKAGE_PIN R15  IOSTANDARD LVCMOS33 } [get_ports { BTN[2] }]
set_property -dict { PACKAGE_PIN V1   IOSTANDARD LVCMOS33 } [get_ports { BTN[3] }]
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports { BTN[4] }]

## ─────────────────────────────────────────────────────────────────────────────
## 4. 开关
##    SW[7:0]  → 拨码开关 SW0~SW7（R1 N4 M4 R2 P2 P3 P4 P5）  数值输入
##    SW[15:8] → DIP 开关 SW8[0~7]（T5 T3 R3 V4 V5 V2 U2 U3）  功能选择
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN R1   IOSTANDARD LVCMOS33 } [get_ports { SW[0]  }]
set_property -dict { PACKAGE_PIN N4   IOSTANDARD LVCMOS33 } [get_ports { SW[1]  }]
set_property -dict { PACKAGE_PIN M4   IOSTANDARD LVCMOS33 } [get_ports { SW[2]  }]
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports { SW[3]  }]
set_property -dict { PACKAGE_PIN P2   IOSTANDARD LVCMOS33 } [get_ports { SW[4]  }]
set_property -dict { PACKAGE_PIN P3   IOSTANDARD LVCMOS33 } [get_ports { SW[5]  }]
set_property -dict { PACKAGE_PIN P4   IOSTANDARD LVCMOS33 } [get_ports { SW[6]  }]
set_property -dict { PACKAGE_PIN P5   IOSTANDARD LVCMOS33 } [get_ports { SW[7]  }]

set_property -dict { PACKAGE_PIN T5   IOSTANDARD LVCMOS33 } [get_ports { SW[8]  }]
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports { SW[9]  }]
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports { SW[10] }]
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports { SW[11] }]
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports { SW[12] }]
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports { SW[13] }]
set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports { SW[14] }]
set_property -dict { PACKAGE_PIN U3   IOSTANDARD LVCMOS33 } [get_ports { SW[15] }]

## ─────────────────────────────────────────────────────────────────────────────
## 5. LED（高电平点亮）
##    LED[7:0]  → D1 组：D1_0~D1_7（K3 M1 L1 K6 J5 H5 H6 K1）
##    LED[15:8] → D2 组：D2_0~D2_7（K2 J2 J3 H4 J4 G3 G4 F6）
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN K3   IOSTANDARD LVCMOS33 } [get_ports { LED[0]  }]
set_property -dict { PACKAGE_PIN M1   IOSTANDARD LVCMOS33 } [get_ports { LED[1]  }]
set_property -dict { PACKAGE_PIN L1   IOSTANDARD LVCMOS33 } [get_ports { LED[2]  }]
set_property -dict { PACKAGE_PIN K6   IOSTANDARD LVCMOS33 } [get_ports { LED[3]  }]
set_property -dict { PACKAGE_PIN J5   IOSTANDARD LVCMOS33 } [get_ports { LED[4]  }]
set_property -dict { PACKAGE_PIN H5   IOSTANDARD LVCMOS33 } [get_ports { LED[5]  }]
set_property -dict { PACKAGE_PIN H6   IOSTANDARD LVCMOS33 } [get_ports { LED[6]  }]
set_property -dict { PACKAGE_PIN K1   IOSTANDARD LVCMOS33 } [get_ports { LED[7]  }]

set_property -dict { PACKAGE_PIN K2   IOSTANDARD LVCMOS33 } [get_ports { LED[8]  }]
set_property -dict { PACKAGE_PIN J2   IOSTANDARD LVCMOS33 } [get_ports { LED[9]  }]
set_property -dict { PACKAGE_PIN J3   IOSTANDARD LVCMOS33 } [get_ports { LED[10] }]
set_property -dict { PACKAGE_PIN H4   IOSTANDARD LVCMOS33 } [get_ports { LED[11] }]
set_property -dict { PACKAGE_PIN J4   IOSTANDARD LVCMOS33 } [get_ports { LED[12] }]
set_property -dict { PACKAGE_PIN G3   IOSTANDARD LVCMOS33 } [get_ports { LED[13] }]
set_property -dict { PACKAGE_PIN G4   IOSTANDARD LVCMOS33 } [get_ports { LED[14] }]
set_property -dict { PACKAGE_PIN F6   IOSTANDARD LVCMOS33 } [get_ports { LED[15] }]

## ─────────────────────────────────────────────────────────────────────────────
## 6. 七段数码管（共阴极，高电平有效）
##
##    DN0（右侧4位，位0~3）段线
##      SEG0[0]=CA0=A段  SEG0[1]=CB0=B段  SEG0[2]=CC0=C段  SEG0[3]=CD0=D段
##      SEG0[4]=CE0=E段  SEG0[5]=CF0=F段  SEG0[6]=CG0=G段
##
##    DN1（左侧4位，位4~7）段线
##      SEG1[0]=CA1=A段  SEG1[1]=CB1=B段  SEG1[2]=CC1=C段  SEG1[3]=CD1=D段
##      SEG1[4]=CE1=E段  SEG1[5]=CF1=F段  SEG1[6]=CG1=G段
##
##    位选 AN[0]=BIT1（DN0最右位）... AN[7]=BIT8（DN1最左位），高有效
## ─────────────────────────────────────────────────────────────────────────────

## DN0 段选
set_property -dict { PACKAGE_PIN B4   IOSTANDARD LVCMOS33 } [get_ports { SEG0[0] }]  ;# CA0
set_property -dict { PACKAGE_PIN A4   IOSTANDARD LVCMOS33 } [get_ports { SEG0[1] }]  ;# CB0
set_property -dict { PACKAGE_PIN A3   IOSTANDARD LVCMOS33 } [get_ports { SEG0[2] }]  ;# CC0
set_property -dict { PACKAGE_PIN B1   IOSTANDARD LVCMOS33 } [get_ports { SEG0[3] }]  ;# CD0
set_property -dict { PACKAGE_PIN A1   IOSTANDARD LVCMOS33 } [get_ports { SEG0[4] }]  ;# CE0
set_property -dict { PACKAGE_PIN B3   IOSTANDARD LVCMOS33 } [get_ports { SEG0[5] }]  ;# CF0
set_property -dict { PACKAGE_PIN B2   IOSTANDARD LVCMOS33 } [get_ports { SEG0[6] }]  ;# CG0

## DN0 小数点
set_property -dict { PACKAGE_PIN D5   IOSTANDARD LVCMOS33 } [get_ports { DP0 }]

## DN1 段选
set_property -dict { PACKAGE_PIN D4   IOSTANDARD LVCMOS33 } [get_ports { SEG1[0] }]  ;# CA1
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports { SEG1[1] }]  ;# CB1
set_property -dict { PACKAGE_PIN D3   IOSTANDARD LVCMOS33 } [get_ports { SEG1[2] }]  ;# CC1
set_property -dict { PACKAGE_PIN F4   IOSTANDARD LVCMOS33 } [get_ports { SEG1[3] }]  ;# CD1
set_property -dict { PACKAGE_PIN F3   IOSTANDARD LVCMOS33 } [get_ports { SEG1[4] }]  ;# CE1
set_property -dict { PACKAGE_PIN E2   IOSTANDARD LVCMOS33 } [get_ports { SEG1[5] }]  ;# CF1
set_property -dict { PACKAGE_PIN D2   IOSTANDARD LVCMOS33 } [get_ports { SEG1[6] }]  ;# CG1

## DN1 小数点
set_property -dict { PACKAGE_PIN H2   IOSTANDARD LVCMOS33 } [get_ports { DP1 }]

## 位选（高有效）
##   AN[0]=BIT1=G2  DN0最右位
##   AN[1]=BIT2=C2
##   AN[2]=BIT3=C1
##   AN[3]=BIT4=H1  DN0最左位
##   AN[4]=BIT5=G1  DN1最右位
##   AN[5]=BIT6=F1
##   AN[6]=BIT7=E1
##   AN[7]=BIT8=G6  DN1最左位
set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 } [get_ports { AN[0] }]
set_property -dict { PACKAGE_PIN C2   IOSTANDARD LVCMOS33 } [get_ports { AN[1] }]
set_property -dict { PACKAGE_PIN C1   IOSTANDARD LVCMOS33 } [get_ports { AN[2] }]
set_property -dict { PACKAGE_PIN H1   IOSTANDARD LVCMOS33 } [get_ports { AN[3] }]
set_property -dict { PACKAGE_PIN G1   IOSTANDARD LVCMOS33 } [get_ports { AN[4] }]
set_property -dict { PACKAGE_PIN F1   IOSTANDARD LVCMOS33 } [get_ports { AN[5] }]
set_property -dict { PACKAGE_PIN E1   IOSTANDARD LVCMOS33 } [get_ports { AN[6] }]
set_property -dict { PACKAGE_PIN G6   IOSTANDARD LVCMOS33 } [get_ports { AN[7] }]

## ─────────────────────────────────────────────────────────────────────────────
## 7. 音频（标准推挽输出，直接赋 0/1）
##    AUD_SD# = M6，正常使用时输出 1（使能功放）
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN T1   IOSTANDARD LVCMOS33 } [get_ports { AUD_PWM }]
set_property -dict { PACKAGE_PIN M6   IOSTANDARD LVCMOS33 } [get_ports { AUD_SD  }]

## ─────────────────────────────────────────────────────────────────────────────
## 8. PS/2 键盘（USB 转 PS/2，通过板载 PIC24FJ128 转换）
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN K5   IOSTANDARD LVCMOS33 } [get_ports { PS2_CLK  }]
set_property -dict { PACKAGE_PIN L4   IOSTANDARD LVCMOS33 } [get_ports { PS2_DATA }]

## ─────────────────────────────────────────────────────────────────────────────
## 9. VGA（12-bit，4R4G4B + HSYNC + VSYNC）
## ─────────────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN F5   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[0] }]
set_property -dict { PACKAGE_PIN C6   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[1] }]
set_property -dict { PACKAGE_PIN C5   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[2] }]
set_property -dict { PACKAGE_PIN B7   IOSTANDARD LVCMOS33 } [get_ports { VGA_R[3] }]

set_property -dict { PACKAGE_PIN B6   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[0] }]
set_property -dict { PACKAGE_PIN A6   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[1] }]
set_property -dict { PACKAGE_PIN A5   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[2] }]
set_property -dict { PACKAGE_PIN D8   IOSTANDARD LVCMOS33 } [get_ports { VGA_G[3] }]

set_property -dict { PACKAGE_PIN C7   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[0] }]
set_property -dict { PACKAGE_PIN E6   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[1] }]
set_property -dict { PACKAGE_PIN E5   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[2] }]
set_property -dict { PACKAGE_PIN E7   IOSTANDARD LVCMOS33 } [get_ports { VGA_B[3] }]

set_property -dict { PACKAGE_PIN D7   IOSTANDARD LVCMOS33 } [get_ports { VGA_HS }]
set_property -dict { PACKAGE_PIN C4   IOSTANDARD LVCMOS33 } [get_ports { VGA_VS }]

## ─────────────────────────────────────────────────────────────────────────────
## 10. 全局配置（EGO1 使用 3.3V IO）
## ─────────────────────────────────────────────────────────────────────────────
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
