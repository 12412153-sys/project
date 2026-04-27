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
// 描述: 售货机管理模式控制，包含8-bit密码校验（Bonus）、连续错误报警、数据修改指令下发。
// 注意: 所有的 btn 输入默认已经被消抖并且提取了单脉冲（上升沿有效）。

module admin_mode(
    input clk,
    input rst_n,
    input admin_en,             // 从主状态机来的使能信号：1表示当前在管理模式
    
    // 交互输入
    input [7:0] switch_in,      // 8个拨码开关:输入密码/输入新价格/输入库存增量
    input btn_confirm,          // 确认按键(单脉冲)
    input btn_next,             // 切换按键(单脉冲)用于切换饮料编号
    
    // 给数据存储模块 (成员C) 的输出
    output reg [7:0] update_data, // 发送给存储模块的具体数值
    output reg [2:0] drink_id,   // 发送给存储模块的地址（哪种饮料）
    output reg write_en,        // 写使能脉冲，1个时钟周期
    
    // 给外设驱动的输出
    output reg alarm_trigger,   // 触发蜂鸣器报警
    output reg [3:0] error_code // 输出到数码管的错误码 (例如 4'hE 代表密码错)
);

    // --- 状态机定义 ---
    localparam S_IDLE     = 3'd0; // 闲置
    localparam S_AUTH     = 3'd1; // 密码校验
    localparam S_ALARM    = 3'd2; // 报警
    localparam S_SELECT   = 3'd3; // 选择要修改的饮料
    localparam S_MODIFY   = 3'd4; // 输入新数据
    localparam S_SAVE     = 3'd5; // 保存数据
    
    reg [2:0] current_state, next_state;
    
    reg [1:0] err_cnt;            // 密码错误计数器
    wire [7:0] CORRECT_PWD = 8'hA5; // 预设密码 10100101 (方便拨码开关测试)

    // 第一段：状态转移时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;  
        end else begin
            current_state <= next_state;
        end
    end

    // 第二段：状态转移组合逻辑
    always @(*) begin
        next_state = current_state; // 默认保持当前状态
        
        case(current_state)
            S_IDLE: begin
                if (admin_en) 
                    next_state = S_AUTH; // 开启管理模式，去验密码
            end
            
            S_AUTH: begin
                if (!admin_en) 
                    next_state = S_IDLE; // 中途退出
                else if (err_cnt >= 2'd3)
                    next_state = S_ALARM; // 错3次，报警
                else if (btn_confirm) begin
                    if (switch_in == CORRECT_PWD)
                        next_state = S_SELECT; // 密码正确，进入选择
                end
            end
            
            S_ALARM: begin
                if (!admin_en) next_state = S_IDLE; // 退出管理模式后解除报警
            end
            
            S_SELECT: begin
                if (!admin_en) next_state = S_IDLE;
                else if (btn_confirm) next_state = S_MODIFY;
            end
            
            S_MODIFY: begin
                if (!admin_en) next_state = S_IDLE;
                else if (btn_confirm) next_state = S_SAVE;
            end
            
            S_SAVE: begin
                next_state = S_SELECT; // 回到选择界面
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // 第三段：数据和控制信号输出 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位初始化所有输出
            err_cnt <= 2'd0;
            alarm_trigger <= 1'b0;
            error_code <= 4'h0;
            drink_id <= 3'd0;
            update_data <= 8'd0;
            write_en <= 1'b0;
        end else begin
            // 默认值清零，防止误写
            write_en <= 1'b0; 
            
            case(current_state)
                S_IDLE: begin
                    err_cnt <= 2'd0; // 退出管理模式时清空错误次数
                    alarm_trigger <= 1'b0;
                    error_code <= 4'h0;
                end
                
                S_AUTH: begin
                    if (btn_confirm && switch_in != CORRECT_PWD) begin
                        err_cnt <= err_cnt + 1'b1; // 计数错误次数
                        error_code <= 4'hE; // 数码管显示 E (Error)
                    end
                end
                
                S_ALARM: begin
                    alarm_trigger <= 1'b1; // 触发蜂鸣器
                    error_code <= 4'hA;    // 数码管显示 A (Alarm)
                end
                
                S_SELECT: begin
                    error_code <= 4'h0; // 清除错误码
                    // 按下 next 键循环切换饮料 ID (假设只有 4 种饮料)
                    if (btn_next) begin
                        if (drink_id == 3'd3) 
                            drink_id <= 3'd0;
                        else 
                            drink_id <= drink_id + 1'b1;
                    end
                end
                
                S_MODIFY: begin
                    // 读取此时拨码开关的值作为新价格/库存
                    update_data <= switch_in;
                end
                
                S_SAVE: begin
                    // 拉高写使能一个时钟周期，告诉 C 把 update_data 存到 drink_id 对应的寄存器里
                    write_en <= 1'b1; 
                end
            endcase
        end
    end

endmodule
