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
`timescale 1ns / 1ps

module admin_mode_tb();

    // 信号定义
    reg clk;
    reg rst_n;
    reg admin_en;
    reg sw_modify;
    reg [3:0] kbd_data;
    reg kbd_valid;
    reg btn_confirm, btn_next_attr, btn_prev_attr, btn_id_inc, btn_id_dec;
    
    wire [31:0] view_data;
    wire write_en;
    wire [1:0] update_type_out;
    wire [7:0] update_data;
    wire [2:0] drink_id;
    wire alarm_trigger;
    wire exit_to_main;

    // 实例化被测模块 (DUT)
    admin_mode dut (
        .clk(clk),
        .rst_n(rst_n),
        .admin_en(admin_en),
        .sw_modify(sw_modify),
        .kbd_data(kbd_data),
        .kbd_valid(kbd_valid),
        .btn_confirm(btn_confirm),
        .btn_next_attr(btn_next_attr),
        .btn_prev_attr(btn_prev_attr),
        .btn_id_inc(btn_id_inc),
        .btn_id_dec(btn_id_dec),
        .current_stock(8'h20),      // 模拟库存：32
        .current_price(8'h05),      // 模拟价格：5
        .sold_out_mask(4'b1010),    // 模拟状态
        .total_revenue(16'h1234),   // 模拟总额
        .view_data(view_data),
        .write_en(write_en),
        .update_type_out(update_type_out),
        .update_data(update_data),
        .drink_id(drink_id),
        .alarm_trigger(alarm_trigger),
        .exit_to_main(exit_to_main)
    );

    // 时钟生成 (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // --- 辅助 Task: 模拟键盘输入 ---
    task kbd_input(input [3:0] val);
        begin
            kbd_data = val;
            kbd_valid = 1;
            #10;
            kbd_valid = 0;
            #20;
        end
    endtask

    // --- 辅助 Task: 模拟按键脉冲 ---
    task btn_pulse(num);
        begin
            case(num)
                1: btn_confirm = 1;
                2: btn_next_attr = 1;
                3: btn_prev_attr = 1;
                4: btn_id_inc = 1;
                5: btn_id_dec = 1;
            endcase
            #10;
            {btn_confirm, btn_next_attr, btn_prev_attr, btn_id_inc, btn_id_dec} = 5'b0;
            #40; // 等待处理
        end
    endtask

    // --- 主测试流程 ---
    initial begin
        // 初始化信号
        rst_n = 0;
        admin_en = 0;
        sw_modify = 0;
        kbd_data = 0;
        kbd_valid = 0;
        {btn_confirm, btn_next_attr, btn_prev_attr, btn_id_inc, btn_id_dec} = 5'b0;

        // 1. 复位测试
        #20 rst_n = 1;
        #20;

        // 2. 模拟失败登录 (1次)
        $display("TC1: Testing Failed Login...");
        admin_en = 1;      // 开启管理开关
        #20;
        kbd_input(4'h1);   // 输错密码
        kbd_input(4'h2);
        btn_pulse(1);      // 确认
        
        // 3. 模拟成功登录 (密码 A5)
        $display("TC2: Testing Successful Login...");
        kbd_input(4'hA);   
        kbd_input(4'h5);
        btn_pulse(1);      // 确认 -> 进入 VIEW 状态
        #20;

        // 4. 线性翻页测试 (按键2: 右翻)
        $display("TC3: Testing Linear Navigation...");
        // 0号饮料：看属性1(价格), 属性2(状态)
        btn_pulse(2); 
        btn_pulse(2);
        // 自动跳转到 1号饮料属性0(库存)
        btn_pulse(2); 
        #20;

        // 5. 饮料 ID 强制切换测试 (按键4/5)
        $display("TC4: Testing ID Jumping...");
        btn_pulse(4); // 切换到 2号
        btn_pulse(4); // 切换到 3号
        #20;

        // 6. 到达序列末尾：显示总金额
        $display("TC5: Testing Total Revenue View...");
        btn_pulse(2); // 3号属性1
        btn_pulse(2); // 3号属性2
        btn_pulse(2); // 进入总额显示模式 (show_total = 1)
        #50;

        // 7. 修改模式测试 (补货)
        $display("TC6: Testing Modification Flow...");
        btn_pulse(3); // 先退回 3号属性2
        btn_pulse(3); // 退回 3号属性1 (价格)
        sw_modify = 1; // 拨开修改开关
        #20;
        kbd_input(4'h0); // 输入新价格 09
        kbd_input(4'h9);
        btn_pulse(1);    // 触发 SAVE
        #50;
        sw_modify = 0;   // 回到查看模式
        #20;

        // 8. 报警锁定测试
        $display("TC7: Testing Alarm Logic...");
        admin_en = 0;    // 退出重来
        #50;
        admin_en = 1;    // 重新进入
        #20;
        repeat(3) begin  // 连续错3次
            kbd_input(4'hF); kbd_input(4'hF);
            btn_pulse(1);
            #20;
        end
        // 此时应 alarm_trigger = 1
        #50;
        btn_pulse(1);    // 按下按键1解除报警并退回主菜单
        
        #100;
        $display("Testbench Finished.");
        $finish;
    end
endmodule
