# 存储子模块说明文档

## 1. 模块概述

`register_file.v` 是整个售货机系统的**中央存储模块**，存储所有饮料参数及系统全局状态。它向 `admin_mode` 和 `sales_mode` 提供只读数据，并接收来自两者的写回请求。

---

## 2. 存储内容

| 变量 | 位宽 | 说明 | 复位初值 |
|------|------|------|---------|
| `r_price[0:3]` | `[7:0]` 各 | 4 种饮料单价（有效位为低 4 位，0-9） | 4, 5, 3, 2 |
| `r_stock[0:3]` | `[3:0]` 各 | 4 种饮料库存（0-9） | 5, 6, 8, 9 |
| `r_enabled` | `[3:0]` | 在售掩码，`bit[i]=1` 表示第 i 种饮料在售 | `4'b1111` |
| `r_revenue` | `[15:0]` | 系统累计实收金额（binary） | `0` |
| `r_password` | `[7:0]` | 管理员密码（BCD，高低各一位数字） | `8'h42`（"42"） |

**复位即初始化**：按下复位键（S6/P15）将所有数据恢复至上表默认值。

---

## 3. 接口说明

### 3.1 写端口

| 信号 | 来源 | 说明 |
|------|------|------|
| `admin_we` | `admin_mode` | 1 周期写脉冲 |
| `admin_upd_type[1:0]` | `admin_mode` | `01`=设价格 `10`=加库存 `11`=切换在售 |
| `admin_upd_data[7:0]` | `admin_mode` | 写入值（BCD，低 nibble 为有效数字） |
| `admin_drink_id[1:0]` | `admin_mode` | 目标饮料编号（0-3） |
| `sale_we` | `sales_mode` | 1 周期写脉冲（取货确认后触发） |
| `sale_idx[1:0]` | `sales_mode` | 售出的饮料编号 |
| `sale_amount[7:0]` | `sales_mode` | 本次应累加的金额 |

**写优先级**：`admin_we` 优先于 `sale_we`（两者正常不会同时拉高）。

### 3.2 读端口（纯组合输出）

| 信号 | 位宽 | 说明 |
|------|------|------|
| `price0~price3` | `[7:0]` | 4 种饮料价格 |
| `stock0~stock3` | `[3:0]` | 4 种饮料库存 |
| `enabled_mask` | `[3:0]` | 在售掩码（1=在售） |
| `total_revenue` | `[15:0]` | 累计实收 |
| `password` | `[7:0]` | 管理员密码 |

---

## 4. 写入语义

| `admin_upd_type` | 操作 |
|-----------------|------|
| `2'b01` | `price[id] ← {4'h0, upd_data[3:0]}`（直接设置新价格） |
| `2'b10` | `stock[id] ← min(stock[id] + upd_data[3:0], 9)`（补货，上限 9） |
| `2'b11` | `enabled[id] ← ~enabled[id]`（切换在售/停售，忽略 upd_data） |

`sale_we` 触发时：
- `stock[idx] -= 1`（若库存 > 0）
- `revenue += sale_amount`

---

## 5. 与其他模块的交互

```
                ┌──────────────────┐
  admin_mode ──►│  register_file   │◄── sales_mode
  (write port)  │                  │    (write port)
                │  price[0:3]      │───► admin_mode  (top mux)
                │  stock[0:3]      │───► admin_mode  (top mux)
                │  enabled_mask    │───► sales_mode
                │  total_revenue   │───► admin_mode
                │  password        │───► admin_mode
                └──────────────────┘
```

顶层模块（`drink_vending_top`）负责将 `price[drink_id]` / `stock[drink_id]` 多路选择后送给 `admin_mode` 的 `current_price` / `current_stock` 端口。
