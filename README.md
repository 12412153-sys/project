# 存储子模块说明文档 — register_file.v

> 供学习使用，对照 `project_sub/register_file.v` 阅读

---

## 1. 模块定位

`register_file.v` 是整个售货机系统的**唯一数据仓库**。所有饮料参数（价格、库存、在售状态）和系统状态（累计营收、管理员密码）都存在这里。

**设计原则**：集中存储、并发读、两口写。销售和管理模块只负责"申请写"，由本模块统一执行，保证数据一致性。

```
  admin_mode ──写口──┐
                     ▼
               register_file  ──读口──→ admin_mode（价格/库存/密码/营收）
                     ▲         ──读口──→ sales_v3（价格/库存/使能掩码）
  sales_v3   ──写口──┘         ──读口──→ vga_display（价格/库存/营收/使能）
```

---

## 2. 存储内容与初始值

| 内部寄存器 | 位宽 | 存放内容 | 初始值 |
|----------|------|---------|--------|
| `r_price[0..3]` | `[7:0]` 各 | 4 种饮料单价（有效范围 1–9，存为二进制） | 4, 5, 3, 2（COLA/SODA/TEA/H2O） |
| `r_stock[0..3]` | `[7:0]` 各 | 4 种饮料库存（0–99，两位数） | 5, 6, 8, 9 |
| `r_enabled` | `[3:0]` | 在售掩码，`bit[i]=1` 表示第 i 种饮料在售 | `4'b1111`（全部在售） |
| `r_revenue` | `[15:0]` | 系统累计实收金额（二进制，最大 65535） | `0` |
| `r_password` | `[7:0]` | 管理员密码（BCD：高 nibble=第一位数字，低 nibble=第二位数字） | `8'h61`（键盘先按"6"再按"1"） |

### 初始值如何生效？——`initial` 块与 FPGA 的关系

```verilog
initial begin
    r_price[0] = 8'd4;  r_stock[0] = 8'd5;   // COLA
    ...
    r_password = 8'h61;
end
```

- 在仿真里，`initial` 块在时间 0 执行，寄存器立刻有初始值。
- 在 FPGA 里，Vivado 把 `initial` 块编译为寄存器的 **INIT 属性**，写入比特流。上电加载比特流时，这些值被硬件直接加载到寄存器——不需要任何 reset 信号。
- **按 S5（PROG_B）重新加载比特流 = 恢复出厂值**。因为整个 FPGA 重新配置，所有寄存器重新从比特流里读取 INIT 值。
- **按 S6（P15）软退出不会恢复初始值**，只是让顶层 FSM 回到主菜单，register_file 的数据完全保留。

---

## 3. 接口信号

### 3.1 管理员写口

| 信号 | 位宽 | 说明 |
|------|------|------|
| `admin_we` | 1 | 写使能，高电平有效，持续 1 个时钟周期 |
| `admin_upd_type[1:0]` | 2 | 操作类型（见下表） |
| `admin_upd_data[7:0]` | 8 | 新值（十进制二进制数，管理员键盘输入后存的结果） |
| `admin_drink_id[1:0]` | 2 | 目标饮料编号（0=COLA，1=SODA，2=TEA，3=H2O） |

| `admin_upd_type` | 操作 | 有效范围 |
|:---:|---|---|
| `2'b01` | **设置单价**：`price[id] ← upd_data`（超过 9 自动截为 9） | 1–9 |
| `2'b10` | **设置库存**：`stock[id] ← upd_data`（超过 99 自动截为 99） | 0–99 |
| `2'b11` | **切换在售**：`enabled[id] ← ~enabled[id]`（忽略 upd_data） | — |

> **与旧版本的重要区别**：`upd_data` 是直接的十进制二进制数（例如库存 15 就传 `8'd15`），不是 BCD 半字节拼接。管理员键盘输入在 `admin_mode.v` 里用 `kbd_buffer * 10 + kbd_data` 累加成真正的十进制数再写过来。

### 3.2 销售写口

| 信号 | 位宽 | 说明 |
|------|------|------|
| `sale_we` | 1 | 写使能，每卖出一瓶触发一次，持续 1 个时钟周期 |
| `sale_idx[1:0]` | 2 | 被售出的饮料编号 |
| `sale_amount[7:0]` | 8 | 该瓶的售价（用于累加营收） |

`sale_we` 触发时执行：
1. `stock[idx] -= 1`（若库存 > 0，否则不减）
2. `revenue += sale_amount`（16-bit 二进制累加）

> **出货机制**：`sales_v3` 在 `ST_COMMIT` 状态下按购物车内容**逐瓶**发 `sale_we`。例如购物车有 2 瓶 COLA + 3 瓶 TEA，就依次发 5 个脉冲：COLA, COLA, TEA, TEA, TEA。每个脉冲只扣 1 瓶库存 + 加 1 次售价，register_file 不需要批量处理。

### 3.3 写优先级

```verilog
if (admin_we) begin
    // 管理员写
end else if (sale_we) begin
    // 销售写
end
```

`admin_we` 优先于 `sale_we`。正常运营时不会同时拉高，优先级只是保险机制。

### 3.4 读口（纯组合输出）

| 信号 | 位宽 | 说明 |
|------|------|------|
| `price0~price3` | `[7:0]` | 4 种饮料单价（同一周期并发读出） |
| `stock0~stock3` | `[7:0]` | 4 种饮料库存（0–99） |
| `enabled_mask` | `[3:0]` | 在售掩码（`bit[i]=1` 表示第 i 种在售） |
| `total_revenue` | `[15:0]` | 累计营收 |
| `password` | `[7:0]` | 管理员密码 |

所有读口是纯组合逻辑（`assign`），无延迟，任何时刻读到的都是当前寄存器的值。

---

## 4. 完整写入逻辑（代码对照）

```verilog
always @(posedge clk) begin
    if (admin_we) begin
        case (admin_upd_type)
            2'b01:  // 改价：截断到 9
                r_price[admin_drink_id] <= (admin_upd_data > 8'd9) ? 8'd9 : admin_upd_data;
            2'b10:  // 改库存：截断到 99
                r_stock[admin_drink_id] <= (admin_upd_data > 8'd99) ? 8'd99 : admin_upd_data;
            2'b11:  // 切换在售
                r_enabled[admin_drink_id] <= ~r_enabled[admin_drink_id];
            default: ;
        endcase
    end else if (sale_we) begin
        if (r_stock[sale_idx] > 0)
            r_stock[sale_idx] <= r_stock[sale_idx] - 1'b1;  // 每次扣 1 瓶
        r_revenue <= r_revenue + {8'h00, sale_amount};       // 累加售价
    end
end
```

注意：没有 `rst_n` 分支。这个模块没有运行时复位，初始值完全由 `initial` 块（→ 比特流 INIT 属性）决定。

---

## 5. 与顶层模块的交互

顶层 `drink_vending_top.v` 中：

```verilog
// 按当前管理员选中的饮料 ID，把对应的 price/stock 多路选出来送给 admin_mode
always @(*) begin
    case (admin_drink_id_raw[1:0])
        2'd0: begin admin_cur_stock = rf_stock0; admin_cur_price = rf_price0; end
        2'd1: begin admin_cur_stock = rf_stock1; admin_cur_price = rf_price1; end
        ...
    endcase
end
```

`register_file` 把所有 4 种饮料的 price/stock 并行输出，顶层根据 `drink_id` 做一个多路选择器，再把结果送给 `admin_mode` 的 `current_price`/`current_stock` 端口。`sales_v3` 则直接接收全部 4 路，自己在内部根据 `drink_id` 选。

---

## 6. 常见问题

**Q：价格能设 0 吗？**  
A：register_file 本身允许，但 `sales_v3` 的 `ST_CHECK` 会检测 `current_price == 0` → 报 `ERR_PRICE`（错误码 4），不允许购买。

**Q：营收会溢出吗？**  
A：`r_revenue` 是 16-bit，最大 65535 元。按最高单价 9 元计算，需要卖出约 7282 瓶才溢出，正常使用不会发生。

**Q：库存扣到负数怎么办？**  
A：有 `if (r_stock[sale_idx] > 0)` 的保护，库存为 0 时不执行扣减。但营收仍然会累加——这种情况在正常流程里不会发生，因为 `sales_v3` 在 `ST_CHECK` 时已经拒绝了库存为 0 的饮料。
