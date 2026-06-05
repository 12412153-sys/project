# VGA 显示模块说明文档 — vga_display.v

**模块文件**：`project_vga/vga_display.v`  
**适用板卡**：EGO1（xc7a35tcsg324-1）  
**版本**：v3.0（最新）

> 供学习使用，对照 `vga_display.v` 代码阅读

---

## 1. 功能概述

`vga_display` 模块通过 EGO1 板载 VGA 接口将售货机状态实时渲染到显示器，**独立于数码管**，信息量更丰富。

| 规格 | 参数 |
|------|------|
| 分辨率 | 640 × 480 |
| 刷新率 | 60 Hz（实际 59.94 Hz） |
| 像素时钟 | **25.175 MHz**（由板载 MMCM Clocking Wizard IP 精确生成） |
| 色深 | 12-bit（R/G/B 各 4 bit，即每通道 16 级亮度） |
| 同步极性 | HS/VS 均为**低有效** |
| 字符网格 | 40 列 × 30 行，每格 16×16 px |

---

## 2. 像素时钟原理（重要）

### 为什么需要精确的 25.175 MHz？

VGA 时序由以下等式绑定：

```
像素时钟 = 帧率 × 每帧总像素
25.175 MHz = 60 Hz × (800 像素/行 × 525 行/帧)
```

其中每行 800 像素（640 有效 + 160 消隐），每帧 525 行（480 有效 + 45 消隐）。  
**像素时钟直接决定行频和帧频**，偏差过大（> 0.5%），显示器的锁相环跟踪不上 → "No Signal"。

用 100 MHz ÷ 4 = 25.000 MHz 时，偏差 0.7%，部分显示器无法锁相。

### MMCM 如何生成 25.175 MHz？

Artix-7 芯片内置 MMCM（Mixed-Mode Clock Manager）硬件：

```
100 MHz (晶振)
    │
    ▼
  MMCM 内部
  VCO × 倍频系数 M ÷ 预分频 D → VCO 频率（需在 600~1200 MHz）
  输出 ÷ 分频系数 O → 25.175 MHz
    │
    ▼
  pclk（25.175 MHz）→ vga_display
```

具体 M/D/O 参数由 Vivado Clocking Wizard IP 自动计算，误差 < 0.01%。

### 模块中的两路时钟

`vga_display` 接收两路时钟，各司其职：

| 时钟 | 频率 | 用于 |
|------|------|------|
| `clk` | 100 MHz | BCD 数值预计算寄存器（慢变数据，需要快时钟算） |
| `pclk` | 25.175 MHz | 像素计数器（hc/vc）、流水线寄存器、RGB/HS/VS 输出 |

这样既保证输出节奏与像素精确同步，又充分利用 100 MHz 进行数值转换。

---

## 3. VGA 时序（640×480@60Hz）

```
一行（800 像素时钟周期）：
 ←—640 有效像素—→←16FP→←96 SYNC→←48BP→
  （RGB 输出有效）        HS 低脉冲

一帧（525 行）：
 ←—480 有效行——→←10FP→←2SYNC→←33BP→
  （画面内容）          VS 低脉冲
```

代码中的计数器：

```verilog
reg [9:0] hc, vc;   // hc: 0..799  vc: 0..524
always @(posedge pclk) begin  // 每个像素时钟递增一次
    if (hc == H_TOTAL-1) begin
        hc <= 0;
        vc <= (vc == V_TOTAL-1) ? 0 : vc + 1;
    end else hc <= hc + 1;
end
wire hs_comb = ~((hc >= 656) && (hc < 752));  // 低有效同步脉冲
wire vs_comb = ~((vc >= 490) && (vc < 492));
wire active  = (hc < 640) && (vc < 480);       // 有效像素区域
```

---

## 4. 字符网格与字体

屏幕分为 40×30 的字符网格，每格 16×16 px（8×8 字体 2 倍放大）：

```
ccol = hc[9:4]   列编号（0..39）   fcol = hc[3:1]  格内列（0..7）
crow = vc[8:4]   行编号（0..29）   frow = vc[3:1]  格内行（0..7）
```

字体 ROM `font[0:1023]` 存在 LUTRAM 中（无时钟延迟，组合读），按 `{ch[6:0], frow}` 寻址，已填充：
- 数字 0–9（ASCII 48–57）
- 大写字母 A–Z（ASCII 65–90）
- 符号 `$ - . / : > #` 和空格

### 渲染辅助函数

| 函数 | 作用 | 示例 |
|------|------|------|
| `sch(s, len, pos)` | 从字符串字面量取第 pos 个字符 | `sch("COLA",4,0)` → `'C'` |
| `dch(val, place)` | 取 16-bit 值第 place 位的十进制 ASCII 字符 | `dch(42, 0)` → `'2'`，`dch(42, 1)` → `'4'` |
| `namech(di, j)` | 饮料名第 j 个字符 | `namech(0,0)` → `'C'`（COLA） |

---

## 5. 三套界面布局

`sys_state` 决定整屏内容（`0`=主菜单，`1`=销售，`2`=管理）。

### 5.1 主菜单（MAIN MENU）

| 行 | 内容 |
|---:|------|
| 0 | 标题栏（蓝底） |
| 1 | `DRINK VENDING MACHINE` |
| 4 | `MAIN MENU` |
| 8 | `R1 DOWN : SALE MODE`（sw[0]=0 时绿色高亮） |
| 10 | `R1 UP   : ADMIN MODE`（sw[0]=1 时绿色高亮） |
| 13 | `PRESS S2 TO CONFIRM`（操作指引，浅蓝色） |

### 5.2 销售界面（SALE MODE）

| 区域 | 行列 | 内容 |
|------|------|------|
| 标题 | 行 0 | `SALE MODE`（青绿底） |
| 商品表头 | 行 2 | `# / NAME / STK / PR / SEL / ITEM / QTY / SUM` |
| 商品行 | 行 4–7 | 每行一种饮料；当前选中行绿色高亮 |
| 库存列 | — | 停售显示 `--`，在售显示 2 位数字 |
| 购物车汇总 | 行 9–11 | `TOTAL $ / PAID $ / NEED $` |
| 错误横幅 | 行 14 | **黄底红字**，仅在 `sale_error≠0` 时出现 |
| 操作指引 | 行 26–27 | 随 `sale_state` 动态变化 |

**错误码 → 显示文字：**

| 码 | 文字 | 触发条件 |
|:---:|---|---|
| 1 | `SOLD OUT` | 饮料已停售 |
| 2 | `OUT OF STOCK` | 库存不足（含输入数量 > 库存） |
| 3 | `PAY NOT ENOUGH` | 支付金额不足 |
| 4 | `PRICE ERROR` | 价格非法 |
| 5 | `TIME OUT` | 超时 |
| 6 | `INVALID CODE` | 键盘输入 0 或 5~9（无效编号） |

### 5.3 管理界面（ADMIN MODE）

| 区域 | 内容 |
|------|------|
| 副标题（行 1） | 随 admin_state 变化：`ENTER PASSWORD` / `WRONG PASSWORD !` / `MODIFY MODE` / `REVENUE VIEW` / `VIEW MODE` |
| **认证前** | 只显示标题和副标题，商品表全部隐藏（保护数据） |
| 商品表（行 3–8） | 认证后显示，格式与销售界面左侧相同 |
| 营收行（行 10） | `TOTAL REVENUE $xxxxx`，键盘按 5 时高亮 |
| 操作指引（行 26–28） | 翻页/修改/保存/退出操作提示 |

---

## 6. 颜色方案

### 模式背景色

| 模式 | 标题栏 `#RGB` | 内容区背景 `#RGB` |
|------|------|------|
| 主菜单 | `#02A` | `#002` |
| 销售 | `#075` | `#011` |
| 管理 | `#60A` | `#102` |

### 属性前景色（`cattr`）

| 属性常量 | 颜色 | 用途 |
|----------|------|------|
| `A_NORM` | 白 `#FFF` | 普通文本 |
| `A_TITLE` | 白 `#FFF` | 标题栏文字 |
| `A_HEAD` | 黄 `#FF2` | 表头列名 |
| `A_SEL` | 绿字 `#0F4` + 绿底 `#031` | 当前选中行 |
| `A_GUIDE` | 浅蓝 `#7DF` | 操作指引 |
| `A_ERR` | 红字 `#F00` + 黄底 `#FF0` | 错误横幅 |

---

## 7. 流水线与时序设计

### 问题：一个像素周期内路径太长

原始设计把 `(hc,vc) → 内容译码 → 字库查表 → 配色 → 输出寄存器` 全压在一个时钟周期（10 ns），路径约 12–15 ns，超时。

### 解决：两级流水线

```
时钟 n（pclk）：
  组合逻辑 → 内容译码（ch, cattr, err_band, fcol, frow, active...）
  ↓ posedge pclk 寄存 → p_ch, p_cattr, p_frow 等（pipeline stage 1）

时钟 n+1（pclk）：
  字库查表（font[{p_ch, p_frow}]）→ 配色 → 组合 → pr_r/g/b
  ↓ posedge pclk 寄存 → q_r/g/b/hs/vs（输出寄存器）

时钟 n+2：输出到显示器
```

整幅画面延后 2 个 pclk 周期（≈ 79 ns），HS/VS 同样延后，**相对时序完全一致**，显示器无感知。

### BCD 数值预计算（100 MHz 域）

购物车金额、营收等数值需要转成十进制显示，计算量大但变化慢，放在 100 MHz 时钟下分级计算：

- **Stage A**：单独计算每种饮料的 `cart × price` 乘积（各自独立）
- **Stage B**：把 4 个乘积相加得到购物车总额；同步做 qty×current_price
- **Stage C**：加上待确认数量的费用，得到 `add_raw`

16-bit 营收的 5 位十进制转换也拆成两级流水线（Stage 1 取高两位，Stage 2 取低三位），避免长组合路径。

### 跨时钟域处理

100 MHz 域的数据（购物车、状态等）流入 25.175 MHz 的像素域。两个时钟比值 3.97（非整数），Vivado 无法自动计算建立时间约束，会误报违例。  
解决：`vending.xdc` 加入：

```tcl
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks clk_out1_clk_wiz_0]
```

告知 Vivado 两个时钟域异步，不计算域间路径。**域内路径仍正常约束**。这样做是安全的，因为这些数据都是缓慢变化的控制信号（按键触发），跨域偶尔采到过渡值最多闪 1 帧（16 ms），肉眼完全看不出。

---

## 8. 接口信号

```verilog
module vga_display (
    input  wire        clk,      // 100 MHz：BCD 预计算域
    input  wire        pclk,     // 25.175 MHz：像素输出域（来自 clk_wiz_0）
    input  wire        rst_n,

    input  wire [1:0]  sys_state,     // 0=主菜单 1=销售 2=管理
    input  wire        sw_sel,        // sw[0]：主菜单高亮哪行

    // 寄存器堆数据（实时读，clk 域）
    input  wire [3:0]  price0..price3,  // 价格只用低4位，故收窄为[3:0]
    input  wire [7:0]  stock0..stock3,  // 0–99 两位库存
    input  wire [3:0]  enabled_mask,
    input  wire [15:0] total_revenue,

    // 销售模式数据
    input  wire [1:0]  sale_drink_id,   // 当前选中（高亮用）
    input  wire [3:0]  sale_state,      // 决定操作指引内容
    input  wire [3:0]  sale_error,      // 0=无错误，1–6=错误码
    input  wire [7:0]  cart0..cart3,    // 购物车数量
    input  wire [11:0] sale_total,      // 应付总额
    input  wire [11:0] sale_paid,       // 已付金额

    // 管理模式数据
    input  wire [1:0]  admin_drink_id,  // 当前选中（高亮用）
    input  wire        admin_show_total,// 1=营收页高亮
    input  wire [2:0]  admin_state,     // 决定副标题和商品表是否显示

    output wire [3:0]  vga_r, vga_g, vga_b,
    output wire        vga_hs, vga_vs   // 低有效
);
```

---

## 9. 硬件引脚（EGO1）

| 信号 | FPGA 引脚 |
|------|----------|
| `vga_r[3:0]` | F5 / C6 / C5 / B7 |
| `vga_g[3:0]` | B6 / A6 / A5 / D8 |
| `vga_b[3:0]` | C7 / E6 / E5 / E7 |
| `vga_hs` | D7 |
| `vga_vs` | C4 |

EGO1 板内置 R-2R DAC 电阻网络，无需额外电路，直接接 VGA 线缆即可。

---

## 10. 在 Vivado 中集成

1. **生成 Clocking Wizard IP**（只做一次）：IP Catalog → Clocking Wizard，设置 CLK_OUT1 = **25.175 MHz**，Component Name = `clk_wiz_0`，Enable `locked` 输出。
2. **从项目中移除** `sim_clk_wiz_0.v`（或设为 Simulation Only）——这是仿真桩，综合时用真 IP。
3. **加入约束**：`vending.xdc` 已包含 `set_clock_groups -asynchronous` 和 `CFGBVS/CONFIG_VOLTAGE`。
4. 正常 Synthesis → Implementation → Generate Bitstream。

---

## 11. 常见问题

**Q：显示器无信号**  
A：首先确认 Clocking Wizard IP 已生成且配置为 25.175 MHz；其次确认显示器支持 640×480@60Hz；最后确认 `set_clock_groups` 约束已在 XDC 中。

**Q：有的显示器能显示，有的不行**  
A：通常是像素时钟精度问题。若已用 MMCM 生成 25.175 MHz 但仍有问题，检查 `report_clocks` 确认生成时钟名字是否与 XDC 一致。

**Q：画面有彩色条纹或乱码**  
A：多半是时序违例未完全消除，运行 `report_timing_summary` 确认 WNS ≥ 0（尤其是 sys_clk 域内部路径）。

**Q：如何增加新的显示内容**  
A：在 `always @(*)` 内容解码块里，按 `(crow, ccol)` 坐标放置字符（`sch`/`dch`/`namech`），并从顶层添加输入端口传入所需数据。
