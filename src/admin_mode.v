`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: admin_mode
// Description:
//   售货机管理模式控制：8-bit 密码校验、连续错误报警、数据修改指令下发。
//   目前为 4 种饮料 (COLA / SODA / TEA / H2O)。
//
//   显示输出 view_data 采用 40-bit 字符 ID 格式 (8 × 5-bit)，与 seg7_mux / sales_v3
//   完全一致：{id7, id6, id5, id4, id3, id2, id1, id0}，id7 为最左侧数码管。
//   （旧版本使用 32-bit 半字节编码，无法表示 H/L/O/S/t 等字母，导致 COLA/H2O 显示
//    错误，现已修正。）
//
//   字符 ID 编码：0-9=数字，10=A 11=b 12=C 13=d 14=E 15=F 16=H 17=L 18=O 19=P
//                20=S 21=t 22=r 23=空白 24=- 25=U 26=n 27=I 28=Y
//
// 注意: 所有的 btn 输入默认已经被消抖并且提取了单脉冲（上升沿有效）。
//////////////////////////////////////////////////////////////////////////////////

module admin_mode #(
    // 单次密码错误时数码管显示 "FAIL" 的保持时间（时钟周期数）。
    // 100 MHz 下 5 秒 = 500_000_000。仿真可在实例化时覆盖为较小值。
    parameter [29:0] FAIL_HOLD = 30'd500_000_000
)(
    input clk,
    input rst_n,
    input admin_en,             // SW[0]@顶层: 1 则进入管理/密码模式
    input sw_modify,            // SW[1]: 1 则进入修改模式

    // 键盘接口
    input [3:0] kbd_data,       // 0-9 数字
    input kbd_valid,            // 键盘按下脉冲

    // 按键输入
    input btn_confirm,          // 确认/保存/报警返回
    input btn_next_attr,        // 右翻页
    input btn_prev_attr,        // 左翻页
    input btn_id_inc,           // 编号+1
    input btn_id_dec,           // 编号-1

    // 寄存器数据
    input [7:0] current_stock,
    input [7:0] current_price,
    input [3:0] sold_out_mask,  // 顶层传入 enabled_mask: bit=1 表示在售
    input [15:0] total_revenue,
    input [7:0] password_in,    // 对齐顶层模块连接的正确密码输入

    // 输出
    output reg [39:0] view_data,    // 8 × 5-bit 字符 ID
    output reg write_en,
    output reg [1:0]  update_type_out,
    output reg [7:0]  update_data,
    output reg [2:0]  drink_id,
    output reg alarm_trigger,
    output reg exit_to_main,

    // 状态导出 (供 VGA 显示使用)
    output [1:0] attr_sel_out,    // 当前查看/修改的属性 0:库存 1:单价 2:状态
    output       show_total_out,  // 1:正在显示累计销售额
    output [2:0] state_out        // 当前 FSM 状态
);

    // 状态定义
    localparam S_IDLE   = 3'd0;
    localparam S_AUTH   = 3'd1;
    localparam S_VIEW   = 3'd2;
    localparam S_MODIFY = 3'd3;
    localparam S_SAVE   = 3'd4;
    localparam S_ALARM  = 3'd5;
    localparam S_FAIL   = 3'd6;   // 单次密码错误：显示 FAIL 保持 FAIL_HOLD 周期后回 S_AUTH

    // 字符 ID 常量（与 seg7_mux 编码一致）
    localparam [4:0] C_0=5'd0,  C_1=5'd1,  C_2=5'd2,  C_3=5'd3,  C_4=5'd4;
    localparam [4:0] C_5=5'd5,  C_6=5'd6,  C_7=5'd7,  C_8=5'd8,  C_9=5'd9;
    localparam [4:0] C_A=5'd10, C_b=5'd11, C_C=5'd12, C_d=5'd13, C_E=5'd14;
    localparam [4:0] C_F=5'd15, C_H=5'd16, C_L=5'd17, C_O=5'd18, C_P=5'd19;
    localparam [4:0] C_S=5'd20, C_t=5'd21, C_r=5'd22, C_BLK=5'd23, C_dash=5'd24;
    localparam [4:0] C_U=5'd25, C_n=5'd26, C_I=5'd27, C_Y=5'd28;

    reg [2:0] state, next_state;
    reg [7:0] pwd_buffer;
    reg [7:0] kbd_buffer;
    reg [1:0] error_cnt;
    reg [1:0] attr_sel;         // 0:库存, 1:单价, 2:状态
    reg       show_total;       // 1则显示累计实收金额
    reg [29:0] fail_timer;      // S_FAIL 状态下的倒计时计数器
    wire fail_done = (fail_timer >= FAIL_HOLD - 1'b1);

    // 状态导出
    assign attr_sel_out   = attr_sel;
    assign show_total_out = show_total;
    assign state_out      = state;

    // 内部十进制解算
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

    // 数字 -> 字符 ID
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

    // 8 个字符 ID 打包成 40-bit
    function [39:0] pack8;
        input [4:0] d7,d6,d5,d4,d3,d2,d1,d0;
        begin
            pack8 = {d7,d6,d5,d4,d3,d2,d1,d0};
        end
    endfunction

    // 根据 drink_id 计算饮料名称的 4 个字符 ID
    reg [4:0] name3, name2, name1, name0;
    always @(*) begin
        case (drink_id[1:0])
            2'd0: begin name3=C_C; name2=C_O; name1=C_L; name0=C_A;   end // COLA
            2'd1: begin name3=C_S; name2=C_O; name1=C_d; name0=C_A;   end // SODA
            2'd2: begin name3=C_t; name2=C_E; name1=C_A; name0=C_BLK; end // TEA
            default: begin name3=C_H; name2=C_2; name1=C_O; name0=C_BLK; end // H2O
        endcase
    end

    // 饮料编号 (1~4) 字符
    wire [4:0] drink_num = num(drink_id[1:0] + 1'b1);
    // 当前饮料在售/停售标志 (1=在售)
    wire enabled_bit = sold_out_mask[drink_id[1:0]];

    // 时序逻辑：状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // 组合逻辑：状态转移
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (admin_en) next_state = S_AUTH;
            end
            S_AUTH: begin
                if (!admin_en) next_state = S_IDLE;
                else if (btn_confirm) begin
                    if (pwd_buffer == password_in) next_state = S_VIEW; // 对齐顶层密码总线
                    else if (error_cnt >= 2'd2) next_state = S_ALARM;   // 连续第3次错误 -> 报警
                    else next_state = S_FAIL;                            // 单次错误 -> 显示 FAIL 5秒
                end
            end
            S_FAIL: begin
                if (!admin_en) next_state = S_IDLE;
                else if (fail_done) next_state = S_AUTH;  // 保持结束后回到密码输入
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

    // 时序逻辑：输入缓冲区
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwd_buffer <= 8'h0;
            kbd_buffer <= 8'h0;
        end else if (kbd_valid) begin
            // 密码沿用 BCD 半字节移位（与 8'h61 形式的 password_in 匹配）
            if (state == S_AUTH) pwd_buffer <= {pwd_buffer[3:0], kbd_data};
            // 修改值用真正的十进制累加（不是 BCD 拼接），否则 "12" 会被当成
            // 0x12=18 显示/存储（即旧版 +6 的 bug）。上限 99（两位库存）。
            else if (state == S_MODIFY)
                kbd_buffer <= (kbd_buffer * 8'd10 + {4'd0, kbd_data} > 8'd99)
                              ? 8'd99
                              : (kbd_buffer * 8'd10 + {4'd0, kbd_data});
        end else if (state == S_IDLE || state == S_SAVE) begin
            kbd_buffer <= 8'h0;
            if (state == S_IDLE) pwd_buffer <= 8'h0;
        end
    end

    // 时序逻辑：内部计数器、控制信号、显示输出
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
            // S_FAIL 倒计时：进入该状态时从 0 开始累加，离开即清零
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
                    // "COdE" + 已输入的两位密码 (BCD)
                    view_data <= pack8(C_C, C_O, C_d, C_E, C_BLK, C_BLK,
                                       num(pwd_buffer[7:4]), num(pwd_buffer[3:0]));
                    if (btn_confirm && pwd_buffer != password_in) error_cnt <= error_cnt + 1;
                end

                S_ALARM: begin
                    // "FAIL" 报警（蜂鸣器持续，直到确认）
                    view_data <= pack8(C_F, C_A, C_I, C_L, C_BLK, C_BLK, C_BLK, C_BLK);
                    alarm_trigger <= 1'b1;
                    if (btn_confirm) exit_to_main <= 1'b1;
                end

                S_FAIL: begin
                    // 单次密码错误：数码管显示 "FAIL" 保持 5 秒，无蜂鸣器
                    view_data <= pack8(C_F, C_A, C_I, C_L, C_BLK, C_BLK, C_BLK, C_BLK);
                    alarm_trigger <= 1'b0;
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
                    // 左翻页
                    if (btn_prev_attr) begin
                        if (show_total) begin
                            show_total <= 1'b0;
                            drink_id <= 3;
                            attr_sel <= 2;
                        end
                        else if (drink_id == 3'd0 && attr_sel == 2'd0) begin
                            // 在第一项的第一种属性时按下，保持不变
                        end
                        else if (attr_sel > 0)
                            attr_sel <= attr_sel - 1;
                        else if (drink_id > 0) begin
                            drink_id <= drink_id - 1;
                            attr_sel <= 2;
                        end
                    end
                    // ID 切换
                    if (btn_id_inc && !show_total && drink_id < 3) drink_id <= drink_id + 1;
                    if (btn_id_dec && !show_total && drink_id > 0) drink_id <= drink_id - 1;

                    // 键盘快速跳转：输入 1-4 直接选中对应编号饮料；输入 5 查看总销售额
                    if (kbd_valid) begin
                        if (kbd_data >= 4'd1 && kbd_data <= 4'd4) begin
                            drink_id   <= {1'b0, kbd_data[1:0]} - 1'b1;
                            show_total <= 1'b0;
                        end else if (kbd_data == 4'd5) begin
                            show_total <= 1'b1;
                        end
                    end

                    // 显示输出
                    if (show_total)
                        // "t" 标记 + 5 位累计实收金额 (右对齐)
                        view_data <= pack8(C_t, C_BLK, C_BLK,
                                           num(rev_ten_thousands), num(rev_thousands),
                                           num(rev_hundreds), num(rev_tens), num(rev_ones));
                    else begin
                        case (attr_sel)
                            // 库存：编号 + 名称 + 两位库存
                            2'd0: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, num(stock_tens), num(stock_ones));
                            // 单价：编号 + 名称 + 'P' + 单价
                            2'd1: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, C_P, num(price_ones));
                            // 状态：编号 + 名称 + 在售(1)/停售(0)
                            2'd2: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, C_BLK, num({3'b0, enabled_bit}));
                            default: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                        C_BLK, num(stock_tens), num(stock_ones));
                        endcase
                    end
                end

                S_MODIFY: begin
                    // 修改模式：编号 + 名称 + 键盘十进制缓冲区数据
                    view_data <= pack8(drink_num, name3, name2, name1, name0,
                                       C_BLK, num(kbd_tens), num(kbd_ones));
                    if (btn_confirm) begin
                        update_data <= kbd_buffer;
                        case (attr_sel)
                            2'd0: update_type_out <= 2'b10; // 补货
                            2'd1: update_type_out <= 2'b01; // 改价
                            2'd2: update_type_out <= 2'b11; // 切换状态
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
