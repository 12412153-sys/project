`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/28 11:36:25
// Design Name: 
// Module Name: admin_mode_tb
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

module admin_mode_tb;

    // 输入端口定义
    reg clk;
    reg rst_n;
    reg admin_en;
    reg sw_modify;
    reg [7:0] password_in;
    reg [3:0] kbd_data;
    reg kbd_valid;
    reg btn_confirm;
    reg btn_next_attr;
    reg btn_prev_attr;
    reg btn_id_inc;
    reg btn_id_dec;
    reg [7:0] current_stock;
    reg [7:0] current_price;
    reg [3:0] sold_out_mask;
    reg [15:0] total_revenue;

    // 输出端口
    wire [31:0] view_data;
    wire write_en;
    wire [1:0] update_type_out;
    wire [7:0] update_data;
    wire [2:0] drink_id;
    wire alarm_trigger;
    wire exit_to_main;

    // 实例化模块
    admin_mode u_admin (
        .clk(clk), .rst_n(rst_n), .admin_en(admin_en), .sw_modify(sw_modify),
        .password_in(password_in), .kbd_data(kbd_data), .kbd_valid(kbd_valid),
        .btn_confirm(btn_confirm), .btn_next_attr(btn_next_attr),
        .btn_prev_attr(btn_prev_attr), .btn_id_inc(btn_id_inc), .btn_id_dec(btn_id_dec),
        .current_stock(current_stock), .current_price(current_price),
        .sold_out_mask(sold_out_mask), .total_revenue(total_revenue),
        .view_data(view_data), .write_en(write_en), .update_type_out(update_type_out),
        .update_data(update_data), .drink_id(drink_id), .alarm_trigger(alarm_trigger),
        .exit_to_main(exit_to_main)
    );

    // 产生时钟 (100MHz)
    always #5 clk = ~clk;

    // 任务：模拟按键脉冲
    task pulse_btn(input reg [31:0] btn_target);
        begin
            #10 btn_target = 1; #10 btn_target = 0;
        end
    endtask

    // 任务：模拟键盘输入
    task input_kbd(input [3:0] val);
        begin
            #10 kbd_data = val; kbd_valid = 1; #10 kbd_valid = 0;
        end
    endtask

    initial begin
        // 初始化信号
        clk = 0; rst_n = 0; admin_en = 0; sw_modify = 0;
        password_in = 8'hA5; // 预设密码 A5
        current_stock = 10; current_price = 5; sold_out_mask = 4'b0000; total_revenue = 100;
        
        #20 rst_n = 1;
        
        // 1. 测试错误密码报警
        admin_en = 1;
        input_kbd(4'h1); input_kbd(4'h2); pulse_btn(btn_confirm); // 错
        input_kbd(4'h3); input_kbd(4'h4); pulse_btn(btn_confirm); // 错
        input_kbd(4'h5); input_kbd(4'h6); pulse_btn(btn_confirm); // 错，触发报警
        #50 pulse_btn(btn_confirm); // 报警恢复
        
        // 2. 测试正确登录与遍历
        admin_en = 0; #20 admin_en = 1;
        input_kbd(4'hA); input_kbd(4'h5); pulse_btn(btn_confirm); // 正确进入
        
        repeat(5) pulse_btn(btn_next_attr); // 遍历属性
        
        // 3. 测试修改模式
        sw_modify = 1;
        input_kbd(4'h9); input_kbd(4'h9); pulse_btn(btn_confirm); // 修改为 99
        #20 sw_modify = 0;
        
        // 4. 测试边界退出
        repeat(10) pulse_btn(btn_prev_attr); // 退回到起点并触发 exit_to_main
        
        #100 $finish;
    end

endmodule