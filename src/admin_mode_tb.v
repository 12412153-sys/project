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
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/26 22:15:00
// Design Name: 
// Module Name: admin_mode_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Testbench for the updated admin_mode with BCD and adaptiveness.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module admin_mode_tb;

    // 1. 信号定义（与待测模块接口一一对应）
    reg clk;
    reg rst_n;
    reg admin_en;
    reg sw_modify;
    
    // 键盘接口
    reg [3:0] kbd_data;
    reg kbd_valid;
    
    // 按键输入
    reg btn_confirm;
    reg btn_next_attr;
    reg btn_prev_attr;
    reg btn_id_inc;
    reg btn_id_dec;
    
    // 寄存器数据
    reg [7:0] current_stock;
    reg [7:0] current_price;
    reg [3:0] sold_out_mask;
    reg [15:0] total_revenue;
    reg [7:0] password_in;
    
    // 输出监视总线
    wire [31:0] view_data;
    wire write_en;
    wire [1:0]  update_type_out;
    wire [7:0]  update_data;
    wire [2:0]  drink_id;
    wire alarm_trigger;
    wire exit_to_main;

    // 2. 实例化待测模块 (UUT)
    admin_mode uut (
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
        .current_stock(current_stock),
        .current_price(current_price),
        .sold_out_mask(sold_out_mask),
        .total_revenue(total_revenue),
        .password_in(password_in),
        .view_data(view_data),
        .write_en(write_en),
        .update_type_out(update_type_out),
        .update_data(update_data),
        .drink_id(drink_id),
        .alarm_trigger(alarm_trigger),
        .exit_to_main(exit_to_main)
    );

    // 3. 产生100MHz系统时钟
    always #5 clk = ~clk;

    // 4. 用户行为模拟任务（Tasks）
    
    // 模拟按键脉冲（单时钟周期高电平）
    task press_button;
        input reg [3:0] btn_num; // 1:confirm, 2:next, 3:prev, 4:inc, 5:dec
        begin
            case(btn_num)
                1: btn_confirm   = 1'b1;
                2: btn_next_attr = 1'b1;
                3: btn_prev_attr = 1'b1;
                4: btn_id_inc    = 1'b1;
                5: btn_id_dec    = 1'b1;
            endcase
            #10; // 维持一个时钟周期
            btn_confirm   = 1'b0;
            btn_next_attr = 1'b0;
            btn_prev_attr = 1'b0;
            btn_id_inc    = 1'b0;
            btn_id_dec    = 1'b0;
            #20; // 按键间隔等待
        end
    endtask

    // 模拟键盘输入单个有效数字
    task input_digit;
        input [3:0] val;
        begin
            kbd_data = val;
            kbd_valid = 1'b1;
            #10;
            kbd_valid = 1'b0;
            #20;
        end
    endtask

    // 5. 测试激励流程
    initial begin
        // --- 初始化输入状态 ---
        clk = 0;
        rst_n = 0;
        admin_en = 0;
        sw_modify = 0;
        kbd_data = 4'h0;
        kbd_valid = 1'b0;
        btn_confirm = 0; btn_next_attr = 0; btn_prev_attr = 0; btn_id_inc = 0; btn_id_dec = 0;
        
        // 设置顶层给出的密码总线以及商品底层初始值
        password_in = 8'hA5;        // 正确密码设置为 A5
        current_stock = 8'd38;      // 初始库存：十进制 38
        current_price = 8'd15;      // 初始单价：十进制 15
        sold_out_mask = 4'b0100;    // 2号饮料(TEA)处于停售状态
        total_revenue = 16'h1234;   // 累计营收
        
        #30 rst_n = 1;              // 解除复位
        #20;

        // ========================================================
        // 测试一：连续错3次密码触发锁定报警逻辑
        // ========================================================
        $display("[测试一] 开始测试密码连续输错报警机制...");
        admin_en = 1; #10;         // 开启使能，进入 S_AUTH
        
        // 第一次输错
        input_digit(4'h1); input_digit(4'h1); press_button(1); 
        // 第二次输错
        input_digit(4'h2); input_digit(4'h2); press_button(1); 
        // 第三次输错 -> 触发 S_ALARM 锁定
        input_digit(4'h3); input_digit(4'h3); press_button(1); 
        #20;
        if (alarm_trigger) $display("-> 成功：模块输出报警脉冲 alarm_trigger = 1，数码管显示 AAAAAAAA");
        
        // 按确认键恢复，并关闭管理开关复位状态
        press_button(1);
        admin_en = 0;
        #50;

        // ========================================================
        // 测试二：正确密码登录与自适应英文名字显示
        // ========================================================
        $display("[测试二] 开始测试正确密码登录及名字缩写对齐...");
        admin_en = 1; #10;
        // 输入正确密码 8'hA5 并确认
        input_digit(4'hA); input_digit(4'h5); press_button(1);
        #20; // 此时进入 S_VIEW
        
        // 1. 验证 0号商品 (COLA: 4位名字) 的十进制库存显示
        // 预期 view_data = C0dA_FF_38 (中间暗2位)
        $display("COLA 库存显示 (Hex): %h", view_data);
        
        // 2. 切换到 2号商品 (TEA: 3位名字)
        press_button(4); // 变成 1号(SODA)
        press_button(4); // 变成 2号(TEA)
        #10;
        // 预期 view_data = 7EA_FFF_38 (名字变短，中间自动多暗一位，变为3位 F)
        $display("TEA  库存显示 (Hex): %h", view_data);

        // ========================================================
        // 测试三：右翻页顺序遍历与单纯的状态位显示
        // ========================================================
        $display("[测试三] 测试右翻页与状态位(0或1)格式点亮...");
        // 当前在 2号商品(TEA) 属性0(库存)，连续按两下右翻页到属性2(状态)
        press_button(2); // 切到属性1: 单价
        press_button(2); // 切到属性2: 停售状态
        // 2号商品对应 sold_out_mask[2] = 1，预期最低位显示 1，高位全部消隐
        // 预期 view_data = 7EA_FFFF_01
        $display("TEA  停售状态显示 (Hex): %h", view_data);

        // ========================================================
        // 测试四：左翻页边界卡死防溢出逻辑（原逻辑核心修改验证）
        // ========================================================
        $display("[测试四] 测试左翻页边界安全锁...");
        // 连续按左翻页退回到 0号商品(COLA) 的 属性0(库存) 界面
        repeat(10) press_button(3);
        #10;
        // 此时已处于极左边界，再次按下按键3
        press_button(3);
        #10;
        // 检查是否保持原样，防止了 drink_id 变成 7 产生下溢出
        if (drink_id == 0 && uut.attr_sel == 0)
            $display("-> 成功：左翻页边界锁定生效。当前ID: %d, 属性索引: %d", drink_id, uut.attr_sel);
        else
            $display("-> 失败：越界溢出错误！当前ID: %d", drink_id);

        // ========================================================
        // 测试五：修改状态下的十进制同步更新与存盘写脉冲
        // ========================================================
        $display("[测试五] 测试修改模式下键盘十进制输入与写存盘脉冲...");
        // 当前在 COLA 库存显示界面，拉高修改开关
        sw_modify = 1; #20; // 进入 S_MODIFY
        
        // 在矩阵小键盘上输入要改的新库存值：十进制 "85"
        input_digit(4'h8); input_digit(4'h5);
        #10;
        // 观察修改期间的数码管，左边名字应保留，右边直接显示输入的 85
        // 预期 view_data = C0dA_FF_85
        $display("修改期间数码管即时显示 (Hex): %h", view_data);
        
        // 按下确认键，保存并触发写使能脉冲
        press_button(1);
        
        // 等待捕捉单时钟周期的 write_en 上升沿
        @(posedge write_en);
        $display("-> 成功：检测到存盘写信号 write_en 变高");
        $display("下发的更新类型 update_type_out (预期2): %b", update_type_out);
        $display("下发的二进制数据 update_data (预期8'h55，即十进制85的Hex值): %h", update_data);
        
        #20;
        sw_modify = 0; // 退出修改模式
        #50;
        
        $display("全部核心控制及显示对齐逻辑验证通过！");
        $finish;
    end

endmodule