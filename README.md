# 基于 FPGA 的饮料售货机 —— 系统框架设计文档

## 1. 项目总览

本系统是一个基于 FPGA 的饮料售货机，支持**销售**与**管理**两种工作模式，通过 EGO1 板载外设完成人机交互。

目前支持
- 4种饮料: COLA、SODA、TEA、H2O（缩写）
- 库存个位数
- 整数价格 + <10
- 上电后开始累计营收额（初始化为0）且累计营收额只有S_SALES mode可以修改
- 密码8 bit（bcd code，所以键盘输入两位数字，如果输入多位但是最后两位是密码也可以通过）
- 一次售卖一个

两种模式数码管的显示demo
- admin 00FFF04: 编号00的饮料某个属性的值是04  
- sale COLA04S5: cola这种饮料04¥，stock 5

后续优化
- 目前管理模式支持键盘输入，销售模式不支持键盘输入（需修改销售模式内部模块--统一调用ps2得到的信号）
- 201 停售
- 库存2位
- rf_total_revenue--同步
- 声音大小
### 1.1 全局状态机

顶层 FSM 有三个状态，通过 `sys_state[1:0]` 寄存器维护：

| 状态 | 编码 | 描述 |
|------|------|------|
| `MAIN_MENU` | `2'd0` | 数码管显示 "r1-0S-1A"；SW[0]=0 选销售，SW[0]=1 选管理；S2 确认进入 |
| `SALE_MODE` | `2'd1` | 使能 `sales_mode`，数码管/LED 由销售模块驱动 |
| `ADMIN_MODE` | `2'd2` | 使能 `admin_mode`，数码管由管理模块驱动 |

状态转换：
```
MAIN_MENU --(S2, SW[0]=0)--> SALE_MODE  --(exit_to_main)--> MAIN_MENU
MAIN_MENU --(S2, SW[0]=1)--> ADMIN_MODE --(exit_to_main)--> MAIN_MENU
```

`sales_mode.exit_to_main` 在销售主页按 S3(cancel) 时拉高一周期。  
`admin_mode.exit_to_main` 在两种情况下拉高：(1) 在 S_VIEW 最开头位置按 S3(prev) 正常退出；(2) S_ALARM 状态按 S2 解除报警时退出。

---

## 2. EGO1 硬件资源分配

### 2.1 输入

| 物理外设 | 顶层端口 | 说明 |
|----------|----------|------|
| 100 MHz 时钟 (P17) | `clk` | 系统时钟 | 
| 复位按键 S6 (P15) | `rst_n` | 低有效全局复位 |                                 
| 按键 S2 (R15) | `btn[2]` | 确认/保存/报警解除返回 |
| 按键 S0 (R11) | `btn[0]` | 属性向后翻页（admin）/ 加金额（sale） |
| 按键 S3 (V1)  | `btn[3]` | 属性向前翻页/退出（admin）/ 取消订单（sale） |
| 按键 S4 (U4)  | `btn[4]` | 饮料ID+（admin）/ 上一个饮料（sale） |
| 按键 S1 (R17) | `btn[1]` | 饮料ID-（admin）/ 下一个饮料（sale） |
| PS2_CLK (K5) | `ps2_clk` | PS/2 键盘（Bonus） |
| PS2_DATA (L4) | `ps2_data` | PS/2 键盘（Bonus） |
| 拨码开关 SW0~SW7 (R1~P5) | `sw[7:0]` | - |

**拨码开关用途**

| 开关位 | 主菜单 | 销售模式 | 管理模式 |
|--------|--------|----------|---------|
| SW[0] (R1) | 模式选（0=销售,1=管理） | — | — |
| SW[1] (N4) | — | — | 修改开关（1=进入编辑子态） |
| SW[7:0] | — | 金额输入（PAY 状态） | — |

### 2.2 输出

| 物理外设 | 顶层端口 | 说明 |
|----------|----------|------|
| 数码管 DN0 段线 (B4,A4,A3,B1,A1,B3,B2,D5) | `seg0[7:0]` | 右侧4位 {dp,g,f,e,d,c,b,a}，**高有效** |
| 数码管 DN1 段线 (D4,E3,D3,F4,F3,E2,D2,H2) | `seg1[7:0]` | 左侧4位 {dp,g,f,e,d,c,b,a}，**高有效** |
| 位选 BIT1~BIT8 (G2,C2,C1,H1,G1,F1,E1,G6) | `an[7:0]` | 8位位选，**高有效**，an[0]=最右位 |
| 音频 PWM (T1) | `aud_pwm` | 蜂鸣器方波输出 |
| 音频 SD# (M6) | `aud_sd` | 音频使能，常输出 1 |
| LED D1 组 (K3,M1,L1,K6,J5,H5,H6,K1) | `led[7:0]` | 进度条/流水灯/状态 |
| LED D2 组 (K2,J2,J3,H4,J4,G3,G4,F6) | `led[15:8]` | 进度条/流水灯/状态 |

**（VGA 接口引脚已在 XDC 中注释备用，启用 Bonus 时取消注释即可）**

---

## 3. 模块层级总览

```
drink_vending_top
├── btn_debounce   × 5   (消抖，每个按键一个实例)
├── ps2_keyboard         (PS/2 → BCD digit + valid)
├── register_file        (中央存储，位于 project_sub/)
├── admin_mode           (管理模式 FSM，位于 project_admin/)
├── sales_mode           (销售模式 FSM，位于 project_sale/)
├── seg7_mux             (8 位数码管时分复用驱动)
└── buzzer_driver        (蜂鸣器报警音生成)
```

---

## 4. 子模块详细说明

### 4.1 `btn_debounce.v`

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `CNT_MAX` | 2,000,000 | 消抖时间 20ms（100MHz） |
| `CNT_WIDTH` | 25 | 计数器位宽 |

输出 `btn_out` 为**高有效单周期脉冲**：仅在按键持续按下 20ms 时输出一次高电平。已消除抖动，顶层直接使用。

### 4.2 `ps2_keyboard.v`

- 接收 PS/2 11-bit 帧（start + 8 data + parity + stop），数据 LSB 先至。
- 支持 break 码（0xF0 前缀）过滤：仅 make 码触发输出。
- 输出 `kbd_data[3:0]`（BCD 0-9）和 `kbd_valid`（1 周期脉冲）。
- 数字键扫描码（Set 2）：0=0x45，1=0x16，2=0x1E，3=0x26，4=0x25，5=0x2E，6=0x36，7=0x3D，8=0x3E，9=0x46。

### 4.3 `seg7_mux.v`

- 输入：`disp_data[39:0]` = 8 × 5-bit 字符 ID，打包格式 `{id7, id6, ..., id0}`（id7=最左位）。
- 字符 ID 与 `sales_mode.v` 中 `CH_*` localparams 一致（0-9=数字，10=A，11=b，...，23=blank，24=-）。
- 扫描频率：100MHz / (100MHz/800Hz) = 100Hz/digit，视觉稳定无闪烁。
- 输出 `an[7:0]`（高有效位选）、`seg0/seg1[7:0]`（高有效段码 `{dp,g,f,e,d,c,b,a}`）。
- 位选 0-3 对应 DN0（右组，驱动 seg0），位选 4-7 对应 DN1（左组，驱动 seg1）。

**Admin view_data 转换**（在顶层进行）：  
`admin_mode` 输出 32-bit（8 nibble）display，顶层用 `nib2id()` 函数将每个 nibble 转换为 5-bit 字符 ID：nibble 0x0-0xE → char ID 0-14，nibble 0xF → char ID 23（blank）。

### 4.4 `buzzer_driver.v`

- `alarm_trigger=1` 时生成双音交替报警音（880Hz / 440Hz，250ms 切换）。
- `aud_sd` 常高（使能板上音频放大器）。
- `alarm_trigger=0` 时 PWM 输出为低（静音）。
---

## 5. 顶层按键路由汇总

| 物理按键 | 端口 | MAIN_MENU | SALE_MODE | ADMIN_MODE |
|---------|------|-----------|-----------|------------|
| S2 (R15) | `btn[2]` | 确认进入模式 | confirm | confirm/save/解除报警 |
| S0 (R11) | `btn[0]` | — | 加金额(pay) | 属性下翻(next_attr) |
| S1 (R17) | `btn[1]` | — | 下一个饮料 | 饮料ID减(id_dec) |
| S3 (V1)  | `btn[3]` | — | 取消订单 | 属性上翻/退出(prev_attr) |
| S4 (U4)  | `btn[4]` | — | 上一个饮料 | 饮料ID加(id_inc) |
| S6 (P15) | `rst_n` | 全局复位（低有效） | ← | ← |

---

## 6. 数码管显示格式汇总

| 模式 | 典型显示 | 说明 |
|------|---------|------|
| 主菜单 | `r1-0S-1A` | SW[0]=0→销售(S)，SW[0]=1→管理(A) |
| 销售-选择 | `COLA04S5` | 饮料名+价格+S+库存 |
| 销售-支付 | `bAL04P04` | 已投金额+P+价格 |
| 销售-取货 | `PUSH   5` | 倒计时 5 秒 |
| 销售-完成 | `DONE    ` | 取货成功 |
| 销售-退款 | `rEFU xx ` | 退款金额 |
| 销售-错误 | `Err    x` | 错误码 1-5 |
| 管理-密码 | `----C0dE` | 等待键盘输入密码 |
| 管理-库存 | `00FFF005` | 饮料0，库存5 |
| 管理-价格 | `00FFF104` | 饮料0，价格4 |
| 管理-状态 | `00FFF201` | 饮料0，在售(1)/停售(0) |
| 管理-营收 | `FFFF0014` | 累计实收0x0014=20 |
| 管理-报警 | `AAAAAAAA` | 密码连续输错3次 |
