`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/26 21:04:41
// Design Name: 
// Module Name: admin_mode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// 模块名称: admin_mode
// 描述: 售货机管理模式控制，包含8-bit密码校验、连续错误报警、数据修改指令下发。
// 增强功能：支持 COLA/SODA/TEA/H2O 英文缩写对齐显示。

module admin_mode(
    input clk,
    input rst_n,
    input admin_en,             // SW[1]: 1则进入管理/密码模式
    input sw_modify,            // SW[2]: 1则进入修改模式
    
    // 键盘接口
    input [3:0] kbd_data,       // 0-9 数字
    input kbd_valid,            // 键盘按下脉冲
    
    // 按键输入
    input btn_confirm,          // 按键1: 确认/保存/报警返回
    input btn_next_attr,        // 按键2: 右翻页
    input btn_prev_attr,        // 按键3: 左翻页
    input btn_id_inc,           // 按键4: 编号+1
    input btn_id_dec,           // 按键5: 编号-1
    
    // 寄存器数据
    input [7:0] current_stock,
    input [7:0] current_price,
    input [3:0] sold_out_mask,
    input [15:0] total_revenue,
    
    // 输出
    output reg [31:0] view_data,
    output reg write_en,
    output reg [1:0]  update_type_out,
    output reg [7:0]  update_data,
    output reg [2:0]  drink_id,
    output reg alarm_trigger,
    output reg exit_to_main
);

    // 状态定义
    localparam S_IDLE   = 3'd0;
    localparam S_AUTH   = 3'd1; // 密码校验
    localparam S_VIEW   = 3'd2; // 查看模式
    localparam S_MODIFY = 3'd3; // 修改模式
    localparam S_SAVE   = 3'd4; // 触发写入
    localparam S_ALARM  = 3'd5; // 报警锁定

    reg [2:0] state, next_state;
    // 内部寄存器
    reg [7:0] pwd_buffer;
    reg [7:0] kbd_buffer;
    reg [1:0] error_cnt;
    reg [1:0] attr_sel;         // 0:库存, 1:单价, 2:状态
    reg       show_total;       // 1则显示累计实收金额

    // ─── 新增：库存与单价的十进制 BCD 拆解 ───
    wire [3:0] stock_tens = (current_stock / 10) % 10;
    wire [3:0] stock_ones = current_stock % 10;
    wire [3:0] price_tens = (current_price / 10) % 10;
    wire [3:0] price_ones = current_price % 10;

    // ─── 新增：键盘输入修改值的十进制拆解 ───
    wire [3:0] kbd_tens  = (kbd_buffer / 10) % 10;
    wire [3:0] kbd_ones  = kbd_buffer % 10;

    // ─── 新增：饮料缩写及字宽控制逻辑 ───
    reg [15:0] name_code; // 存储缩写的 4 个 Nibble
    reg        name_len;  // 0: 3位长 (TEA, H2O); 1: 4位长 (COLA, SODA)
    
    always @(*) begin
        case(drink_id)
            3'd0: begin name_code = {4'hC, 4'h0, 4'hD, 4'hA}; name_len = 1'b1; end // COLA (C0dA)
            3'd1: begin name_code = {4'h5, 4'h0, 4'hD, 4'hA}; name_len = 1'b1; end // SODA (50dA)
            3'd2: begin name_code = {4'h7, 4'hE, 4'hA, 4'hF}; name_len = 1'b0; end // TEA  (tEA_)
            3'd3: begin name_code = {4'hB, 4'h2, 4'h0, 4'hF}; name_len = 1'b0; end // H2O  (b20_)
            default: begin name_code = 16'hFFFF; name_len = 1'b0; end
        endcase
    end

    // ============================================================
    // 第一段：状态转移时序逻辑
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= S_IDLE;
        else 
            state <= next_state;
    end

    // ============================================================
    // 第二段：状态转移组合逻辑
    // ============================================================
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (admin_en) next_state = S_AUTH;
            end
            
            S_AUTH: begin
                if (!admin_en) next_state = S_IDLE;
                else if (btn_confirm) begin
                    if (pwd_buffer == 8'hA5) next_state = S_VIEW;
                    else if (error_cnt >= 2'd2) next_state = S_ALARM;
                    else next_state = S_AUTH;
                end
            end
            
            S_VIEW: begin
                if (!admin_en) next_state = S_IDLE;
                else if (sw_modify && !show_total) next_state = S_MODIFY;
            end
            
            S_MODIFY: begin
                if (!sw_modify) next_state = S_VIEW;
                else if (btn_confirm) next_state = S_SAVE;
            end
            
            S_SAVE: begin
                next_state = S_VIEW;
            end
            
            S_ALARM: begin
                if (btn_confirm) next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // ============================================================
    // 第三段：数据计算与控制信号输出
    // ============================================================
    
    // 3.1 键盘输入累加逻辑 (时序逻辑)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwd_buffer <= 8'h0;
            kbd_buffer <= 8'h0;
        end else if (kbd_valid) begin
            if (state == S_AUTH) pwd_buffer <= {pwd_buffer[3:0], kbd_data};
            // 键盘按键逻辑：支持修改输入的即时移位更新
            else if (state == S_MODIFY) kbd_buffer <= {kbd_buffer[3:0], kbd_data};
        end else if (state == S_IDLE || state == S_SAVE) begin
            kbd_buffer <= 8'h0;
            if (state == S_IDLE) pwd_buffer <= 8'h0;
        end
    end

    // 3.2 导航、显示与控制逻辑 (时序逻辑)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drink_id <= 3'd0;
            attr_sel <= 2'd0;
            show_total <= 1'b0;
            error_cnt <= 2'd0;
            alarm_trigger <= 1'b0;
            write_en <= 1'b0;
            exit_to_main <= 1'b0;
            update_type_out <= 2'b00;
            update_data <= 8'h00;
        end else begin
            write_en <= 1'b0;
            exit_to_main <= 1'b0;

            case (state)
                S_IDLE: begin
                    alarm_trigger <= 1'b0;
                    show_total <= 1'b0;
                    attr_sel <= 2'd0;
                    drink_id <= 3'd0;
                    error_cnt <= (next_state == S_AUTH) ? error_cnt : 2'd0;
                end

                S_AUTH: begin
                    view_data <= {16'hFFFF, 4'hC, 4'h0, 4'hD, 4'hE}; // 显示 "CODE"
                    if (btn_confirm && pwd_buffer != 8'hA5) error_cnt <= error_cnt + 1;
                end

                S_ALARM: begin
                    view_data <= 32'hAAAAAAAA;
                    alarm_trigger <= 1'b1;
                    if (btn_confirm) exit_to_main <= 1'b1;
                end

                S_VIEW: begin
                    // 右翻页
                    if (btn_next_attr) begin
                        if (!show_total) begin
                            if (attr_sel < 2) attr_sel <= attr_sel + 1;
                            else if (drink_id < 3) begin drink_id <= drink_id + 1; attr_sel <= 0; end
                            else show_total <= 1'b1;
                        end
                    end
                    // 左翻页（含卡死在边界防止溢出逻辑）
                    if (btn_prev_attr) begin
                        if (show_total) begin 
                            show_total <= 1'b0; drink_id <= 3; attr_sel <= 2; 
                        end
                        else if (drink_id == 3'd0 && attr_sel == 2'd0) begin
                            // 在第一项的第一种属性时，按下左翻页直接保持原样（不产生下溢出）
                        end
                        else if (attr_sel > 0) 
                            attr_sel <= attr_sel - 1;
                        else if (drink_id > 0) begin 
                            drink_id <= drink_id - 1; attr_sel <= 2; 
                        end
                    end
                    
                    // ID 快捷切换
                    if (btn_id_inc && !show_total && drink_id < 3) drink_id <= drink_id + 1;
                    if (btn_id_dec && !show_total && drink_id > 0) drink_id <= drink_id - 1;

                    // ─── 核心修改：动态自适应生成 view_data 显示内容 ───
                    if (show_total) begin
                        view_data <= {total_revenue, 16'hFFFF};
                    end else begin
                        case (attr_sel)
                            // 1. 库存显示 (十进制)
                            2'd0: begin
                                if (name_len) // 4位长名字: [N3][N2][N1][N0] [F][F] [十位][个位]
                                    view_data <= {name_code, 8'hFF, stock_tens, stock_ones};
                                else          // 3位长名字: [N3][N2][N1] [F][F][F] [十位][个位]
                                    view_data <= {name_code[15:4], 12'hFFF, stock_tens, stock_ones};
                            end
                            
                            // 2. 单价显示 (十进制)
                            2'd1: begin
                                if (name_len)
                                    view_data <= {name_code, 8'hFF, price_tens, price_ones};
                                else
                                    view_data <= {name_code[15:4], 12'hFFF, price_tens, price_ones};
                            end
                            
                            // 3. 停售状态显示 (最后一位显示 0 或 1，倒数第二位全灭)
                            2'd2: begin
                                if (name_len) // 4位长名字: [N3][N2][N1][N0] [F][F][F] [0/1]
                                    view_data <= {name_code, 12'hFFF, 3'b0, sold_out_mask[drink_id]};
                                else          // 3位长名字: [N3][N2][N1] [F][F][F][F] [0/1]
                                    view_data <= {name_code[15:4], 16'hFFFF, 3'b0, sold_out_mask[drink_id]};
                            end
                            default: view_data <= 32'hFFFFFFFF;
                        endcase
                    end
                end

                S_MODIFY: begin
                    // 修改动态界面：左侧依旧显示对应商品的名字缩写
                    if (name_len)
                        view_data <= {name_code, 8'hFF, kbd_tens, kbd_ones};
                    else
                        view_data <= {name_code[15:4], 12'hFFF, kbd_tens, kbd_ones};

                    if (btn_confirm) begin
                        update_data <= kbd_buffer;
                        case (attr_sel)
                            2'd0: update_type_out <= 2'b10; // 补货
                            2'd1: update_type_out <= 2'b01; // 改价
                            2'd2: update_type_out <= 2'b11; // 停售切换
                            default: update_type_out <= 2'b00;
                        endcase
                    end
                end

                S_SAVE: begin
                    write_en <= 1'b1;
                end
                
                default: ;
            endcase
        end
    end

endmodule