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

module admin_mode #(
    parameter [29:0] FAIL_HOLD = 30'd500_000_000 // 密码输错后锁定显示"FAIL"的时间（100MHz时钟下等于5秒）
)(
    input clk, rst_n,
    input admin_en,           // 管理员模式总开关（由拨码开关 SW[0] 控制）
    input sw_modify,          // 修改模式开关（由拨码开关 SW[1] 控制）

    // PS/2 键盘输入
    input [3:0] kbd_data,     // 键盘输入的数字 (0-9)
    input kbd_valid,          // 键盘按下有效脉冲（高电平持续一个周期）

    // 按键输入（均已消抖且转换为单周期脉冲）
    input btn_confirm,        // 确认 / 保存 / 解除报警
    input btn_next_attr,      // 切换到下一个属性
    input btn_prev_attr,      // 切换到上一个属性
    input btn_id_inc,         // 增加饮品ID
    input btn_id_dec,         // 减少饮品ID

    // 来自寄存器堆（RegFile）的数据
    input [7:0] current_stock,// 当前选定饮品的库存
    input [7:0] current_price,// 当前选定饮品的价格
    input [3:0] sold_out_mask,// 4种饮品的上架状态掩码（1为在售，0为下架）
    input [15:0] total_revenue, // 累计总营业额
    input [7:0] password_in,  // 正确的管理员密码（存储在系统寄存器中）

    // 输出信号
    output reg [39:0] view_data,    // 发送给数码管的40位数据（8个数码管 × 每管5位字符编码）
    output reg write_en,            // 写寄存器使能（保存修改时拉高）
    output reg [1:0] update_type_out,// 修改类型：01价格，10库存，11状态
    output reg [7:0] update_data,   // 要修改的写入数据
    output reg [2:0] drink_id,      // 当前选择的饮品ID (0=COLA, 1=SODA, 2=TEA, 3=H2O)
    output reg alarm_trigger,       // 报警触发信号（连蜂鸣器）
    output reg exit_to_main,        // 强行退出管理员模式返回主界面的信号

    // VGA 状态导出
    output [1:0] attr_sel_out,    // 当前属性选择 (0:库存, 1:价格, 2:状态)
    output       show_total_out,  // 是否在显示总营业额
    output [2:0] state_out        // 当前 FSM 状态码
);

    // 二进制状态定义
    localparam S_IDLE  = 3'd0; // 空闲
    localparam S_AUTH  = 3'd1; // 密码验证
    localparam S_VIEW  = 3'd2; // 数据查看
    localparam S_MODIFY = 3'd3;// 数据修改
    localparam S_SAVE   = 3'd4;// 保存写入
    localparam S_ALARM  = 3'd5;// 连续错3次，触发报警
    localparam S_FAIL   = 3'd6;// 输错1-2次，短锁定
    
    // 字符编码映射表（5位编码对应数码管字形）
    localparam [4:0] C_0=5'd0,  C_1=5'd1,  C_2=5'd2,  C_3=5'd3,  C_4=5'd4;
    localparam [4:0] C_5=5'd5,  C_6=5'd6,  C_7=5'd7,  C_8=5'd8,  C_9=5'd9;
    localparam [4:0] C_A=5'd10, C_b=5'd11, C_C=5'd12, C_d=5'd13, C_E=5'd14;
    localparam [4:0] C_F=5'd15, C_H=5'd16, C_L=5'd17, C_O=5'd18, C_P=5'd19;
    localparam [4:0] C_S=5'd20, C_t=5'd21, C_r=5'd22, C_BLK=5'd23, C_dash=5'd24;
    localparam [4:0] C_U=5'd25, C_n=5'd26, C_I=5'd27, C_Y=5'd28;

    reg [2:0] state, next_state;
    reg [7:0] pwd_buffer;    // 存储用户当前输入的密码
    reg [7:0] kbd_buffer;    // 存储修改数值时的十进制输入缓存
    reg [1:0] error_cnt;     // 密码错误计数器
    reg [1:0] attr_sel;      // 属性选择器 (0=库存, 1=价格, 2=状态)
    reg       show_total;    // 营业额显示标志位
    reg [29:0] fail_timer;   // 输错密码锁定计时器
    wire fail_done = (fail_timer >= FAIL_HOLD - 1'b1); // 5秒倒计时结束信号

    // state exports
    assign attr_sel_out   = attr_sel;
    assign show_total_out = show_total;
    assign state_out      = state;

    // decimal digit extraction for 7-segment display
    wire [3:0] stock_tens = (current_stock / 10) % 10;
    wire [3:0] stock_ones = current_stock % 10;
    wire [3:0] price_ones = current_price % 10;
    wire [3:0] kbd_tens   = (kbd_buffer / 10) % 10;
    wire [3:0] kbd_ones   = kbd_buffer % 10;
    wire [3:0] rev_ten_thousands = (total_revenue / 10000) % 10;
    wire [3:0] rev_thousands     = (total_revenue / 1000) % 10;
    wire [3:0] rev_hundreds      = (total_revenue / 100) % 10;
    wire [3:0] rev_tens          = (total_revenue / 10) % 10;
    wire [3:0] rev_ones          = total_revenue % 10;

    // 将4位纯数字(0-9)转换成对应的5位动态数码管字符ID编码
    function [4:0] num;
        input [3:0] x;
        begin
            case (x)
                4'd0: num=C_0; 4'd1: num=C_1; 4'd2: num=C_2; 4'd3: num=C_3; 4'd4: num=C_4;
                4'd5: num=C_5; 4'd6: num=C_6; 4'd7: num=C_7; 4'd8: num=C_8; 4'd9: num=C_9;
                default: num=C_BLK;
            endcase
        end
    endfunction

    /// 把8个5位的字符打包拼接成一个40位的数码管总线
    function [39:0] pack8;
        input [4:0] d7,d6,d5,d4,d3,d2,d1,d0;
        begin
            pack8 = {d7,d6,d5,d4,d3,d2,d1,d0};
        end
    endfunction

    // resolve 4-character drink name from drink_id
    reg [4:0] name3, name2, name1, name0;
    always @(*) begin
        case (drink_id[1:0])
            2'd0: begin name3=C_C; name2=C_O; name1=C_L; name0=C_A;   end // COLA
            2'd1: begin name3=C_S; name2=C_O; name1=C_d; name0=C_A;   end // SODA
            2'd2: begin name3=C_t; name2=C_E; name1=C_A; name0=C_BLK; end // TEA
            default: begin name3=C_H; name2=C_2; name1=C_O; name0=C_BLK; end // H2O
        endcase
    end

    // drink number (1-4) as char-ID for display
    wire [4:0] drink_num = num(drink_id[1:0] + 1'b1);
    // on-sale flag for current drink (1=on-sale)
    wire enabled_bit = sold_out_mask[drink_id[1:0]];

    // sequential: state register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // combinational: next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (admin_en) next_state = S_AUTH;
            end
            S_AUTH: begin
                if (!admin_en) next_state = S_IDLE;
                else if (btn_confirm) begin
                    if (pwd_buffer == password_in) next_state = S_VIEW; // correct password
                    else if (error_cnt >= 2'd2) next_state = S_ALARM;   // 3rd wrong attempt ： alarm
                    else next_state = S_FAIL;                            // 1st/2nd wrong ： show FAIL 5 s
                end
            end
            S_FAIL: begin
                if (!admin_en) next_state = S_IDLE;
                else if (fail_done) next_state = S_AUTH;  // hold expired; back to password entry
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

    // sequential: keyboard input buffers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwd_buffer <= 8'h0;
            kbd_buffer <= 8'h0;
        end else if (kbd_valid) begin
            // password uses BCD nibble-shift to match 8'h61 format of password_in
            if (state == S_AUTH) pwd_buffer <= {pwd_buffer[3:0], kbd_data};
            // modify value uses true decimal accumulation (not BCD concatenation);
            // e.g. typing "1","2" -> 12 (old BCD approach gave 0x12=18, the +6 bug). Cap at 99.
            else if (state == S_MODIFY)
                kbd_buffer <= (kbd_buffer * 8'd10 + {4'd0, kbd_data} > 8'd99)
                              ? 8'd99
                              : (kbd_buffer * 8'd10 + {4'd0, kbd_data});
        end else if (state == S_IDLE || state == S_SAVE) begin
            kbd_buffer <= 8'h0;
            if (state == S_IDLE) pwd_buffer <= 8'h0;
        end
    end

    // sequential: counters, control signals, display output
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
            view_data <= 40'd0;
            fail_timer <= 30'd0;
        end else begin
            write_en <= 1'b0;
            exit_to_main <= 1'b0;
            // S_FAIL hold counter: increment in S_FAIL, reset otherwise
            fail_timer <= (state == S_FAIL) ? (fail_timer + 1'b1) : 30'd0;

            case (state)
                S_IDLE: begin
                    alarm_trigger <= 1'b0;
                    show_total <= 1'b0;
                    attr_sel <= 2'd0;
                    drink_id <= 3'd0;
                    error_cnt <= (next_state == S_AUTH) ? error_cnt : 2'd0;
                end

                S_AUTH: begin
                    // "COdE" + the two BCD digits entered so far
                    view_data <= pack8(C_C, C_O, C_d, C_E, C_BLK, C_BLK,
                                       num(pwd_buffer[7:4]), num(pwd_buffer[3:0]));
                    if (btn_confirm && pwd_buffer != password_in) error_cnt <= error_cnt + 1;
                end

                S_ALARM: begin
                    // "FAIL" alarm (buzzer active until confirmed)
                    view_data <= pack8(C_F, C_A, C_I, C_L, C_BLK, C_BLK, C_BLK, C_BLK);
                    alarm_trigger <= 1'b1;
                    if (btn_confirm) exit_to_main <= 1'b1;
                end

                S_FAIL: begin
                    // single wrong password: show "FAIL" for 5 s, no buzzer
                    view_data <= pack8(C_F, C_A, C_I, C_L, C_BLK, C_BLK, C_BLK, C_BLK);
                    alarm_trigger <= 1'b0;
                end

                S_VIEW: begin
                    // step right (next attribute)
                    if (btn_next_attr) begin
                        if (!show_total) begin
                            if (attr_sel < 2) attr_sel <= attr_sel + 1;
                            else if (drink_id < 3) begin drink_id <= drink_id + 1; attr_sel <= 0; end
                            else show_total <= 1'b1;
                        end
                    end
                    // step left (previous attribute)
                    if (btn_prev_attr) begin
                        if (show_total) begin
                            show_total <= 1'b0;
                            drink_id <= 3;
                            attr_sel <= 2;
                        end
                        else if (drink_id == 3'd0 && attr_sel == 2'd0) begin
                            // at first item / first attribute: do nothing
                        end
                        else if (attr_sel > 0)
                            attr_sel <= attr_sel - 1;
                        else if (drink_id > 0) begin
                            drink_id <= drink_id - 1;
                            attr_sel <= 2;
                        end
                    end
                    // direct drink-ID jump via buttons
                    if (btn_id_inc && !show_total && drink_id < 3) drink_id <= drink_id + 1;
                    if (btn_id_dec && !show_total && drink_id > 0) drink_id <= drink_id - 1;

                    // keyboard quick-jump: 1-4 selects drink, 5 shows revenue
                    if (kbd_valid) begin
                        if (kbd_data >= 4'd1 && kbd_data <= 4'd4) begin
                            drink_id   <= {1'b0, kbd_data[1:0]} - 1'b1;
                            show_total <= 1'b0;
                        end else if (kbd_data == 4'd5) begin
                            show_total <= 1'b1;
                        end
                    end

                    // display output
                    if (show_total)
                        // "t" marker + 5-digit cumulative revenue (right-aligned)
                        view_data <= pack8(C_t, C_BLK, C_BLK,
                                           num(rev_ten_thousands), num(rev_thousands),
                                           num(rev_hundreds), num(rev_tens), num(rev_ones));
                    else begin
                        case (attr_sel)
                            // stock: number + name + 2-digit stock
                            2'd0: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, num(stock_tens), num(stock_ones));
                            // price: number + name + 'P' + price
                            2'd1: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, C_P, num(price_ones));
                            // status: number + name + 1 (on-sale) or 0 (off-sale)
                            2'd2: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, C_BLK, num({3'b0, enabled_bit}));
                            default: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                        C_BLK, num(stock_tens), num(stock_ones));
                        endcase
                    end
                end

                S_MODIFY: begin
                    // modify mode: number + name + current decimal input buffer
                    view_data <= pack8(drink_num, name3, name2, name1, name0,
                                       C_BLK, num(kbd_tens), num(kbd_ones));
                    if (btn_confirm) begin
                        update_data <= kbd_buffer;  // 当按下确认按键时，打包修改指令发送给寄存器堆（顶层总线）
                        case (attr_sel)
                            2'd0: update_type_out <= 2'b10; // restock
                            2'd1: update_type_out <= 2'b01; // reprice
                            2'd2: update_type_out <= 2'b11; // toggle enabled
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
