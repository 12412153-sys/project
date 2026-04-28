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

// 模块名称: admin_mode_tb
// 描述: admin_mode 的行为仿真脚本。
// 流程包含：密码错误报警测试、密码正确通过测试、饮料切换以及模拟写入脉冲测试。

module admin_mode_tb;

    // 定义输入信号
    reg clk;
    reg rst_n;
    reg admin_en;
    reg [7:0] switch_in;
    reg btn_confirm;
    reg btn_next;

    // 定义输出信号
    wire [7:0] update_data;
    wire [2:0] drink_id;
    wire write_en;
    wire alarm_trigger;
    wire [3:0] error_code;

    // 实例化
    admin_mode uut (
        .clk(clk),
        .rst_n(rst_n),
        .admin_en(admin_en),
        .switch_in(switch_in),
        .btn_confirm(btn_confirm),
        .btn_next(btn_next),
        .update_data(update_data),
        .drink_id(drink_id),
        .write_en(write_en),
        .alarm_trigger(alarm_trigger),
        .error_code(error_code)
    );

    // 系统时钟：100MHz，周期为10ns
    always #5 clk = ~clk;

    // 模拟按键动作（模拟一个维持 10ns 的高电平）
    task press_confirm;
        begin
            btn_confirm = 1;
            #10; // 维持一个时钟周期
            btn_confirm = 0;
            #30; // 动作之间的间隔缓冲
        end
    endtask

    task press_next;
        begin
            btn_next = 1;
            #10;
            btn_next = 0;
            #30;
        end
    endtask


    initial begin
        // 初始化所有输入信号
        clk = 0;
        rst_n = 0;
        admin_en = 0;
        switch_in = 8'd0;
        btn_confirm = 0;
        btn_next = 0;

        // 全局复位 100ns
        #100;
        rst_n = 1;
        #50;


        // 连续3次密码错误
        admin_en = 1;         // 成员C切换到了管理模式
        switch_in = 8'h00;    // 正确是 8'hA5
        #20;

        press_confirm; // 错1次，error_code 变为 4'hE
        press_confirm; // 错2次，error_code 变为 4'hE
        press_confirm; // 错3次，alarm_trigger 变为 1，error_code 变为 4'hA
        #50;


        // 切出管理模式，解除报警
        admin_en = 0;         // 切回主菜单
        #50;                  // alarm_trigger 恢复 0，error_code 恢复 0


        // 管理员操作(登录>选饮料>改数据)
        admin_en = 1;         // 再次进入管理模式
        switch_in = 8'hA5;    // 正确密码 (10100101)
        #20;
        press_confirm;        // 验证通过，状态变为 S_SELECT
        
        // 切换饮料 ID
        press_next;           // drink_id 变成 1
        press_next;           // drink_id 变成 2
        
        // 选定 drink_id 为 2 的饮料，准备修改
        press_confirm;        // 状态变为 S_MODIFY
        
        // 输入新参数 (假设新价格为 8'h3C)
        switch_in = 8'h3C;
        #20;                  // update_data 实时变成 8'h3C
        
        // 确认保存
        press_confirm;        // 状态变为 S_SAVE
        #50;


        admin_en = 0; 
        #100;
        $stop; // 结束仿真
    end
endmodule
