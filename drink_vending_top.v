// =============================================================================
//  File        : drink_vending_top.v
//  Project     : FPGA 饮料售货机
//  Board       : EGO1 (XC7A35T-1CSG324C)
//  Author      : Member C
//  Description : 顶层模块。完成所有 wire 互联，子模块均已实例化。
//                A、B 按照各自 stub 的端口定义实现内部逻辑即可。
//
//  硬件关键特性：
//    - 数码管：共阴极，SEG / AN 均高电平有效
//    - DN0(右4位)和 DN1(左4位) 段线引脚完全独立，顶层引出 SEG0/SEG1 两套
//    - 音频：标准推挽输出，直接赋 0/1（无需 open-drain）
//    - LED：高电平点亮
//    - 按键：按下=高电平
// =============================================================================

`timescale 1ns / 1ps

module drink_vending_top (
    // ── 系统 ──────────────────────────────────────────────────────────────────
    input  wire        CLK100MHZ,    // P17

    // ── 复位 ──────────────────────────────────────────────────────────────────
    input  wire        CPU_RESETN,   // P15，低有效

    // ── 按键（按下=1）────────────────────────────────────────────────────────
    input  wire [4:0]  BTN,          // BTN[0]=R11确认, [1]=R17返回, [2]=R15取消,
                                     // [3]=V1左, [4]=U4右

    // ── 开关 ──────────────────────────────────────────────────────────────────
    input  wire [15:0] SW,           // SW[7:0]=拨码开关, SW[15:8]=DIP开关

    // ── PS/2 键盘（Bonus）────────────────────────────────────────────────────
    input  wire        PS2_CLK,      // K5
    input  wire        PS2_DATA,     // L4

    // ── LED（高电平点亮）─────────────────────────────────────────────────────
    output wire [15:0] LED,          // LED[7:0]=D1组, LED[15:8]=D2组

    // ── 七段数码管（共阴，高有效）────────────────────────────────────────────
    // DN0：右侧4位（位0~3）段线
    output wire [6:0]  SEG0,         // {CG0,CF0,CE0,CD0,CC0,CB0,CA0} 高有效
    output wire        DP0,          // D5
    // DN1：左侧4位（位4~7）段线
    output wire [6:0]  SEG1,         // {CG1,CF1,CE1,CD1,CC1,CB1,CA1} 高有效
    output wire        DP1,          // H2
    // 位选（高有效，AN[0]=BIT1最右位, AN[7]=BIT8最左位）
    output wire [7:0]  AN,

    // ── 音频（标准推挽）──────────────────────────────────────────────────────
    output wire        AUD_PWM,      // T1
    output wire        AUD_SD,       // M6，常 1

    // ── VGA（Bonus）──────────────────────────────────────────────────────────
    output wire [3:0]  VGA_R,        // F5 C6 C5 B7
    output wire [3:0]  VGA_G,        // B6 A6 A5 D8
    output wire [3:0]  VGA_B,        // C7 E6 E5 E7
    output wire        VGA_HS,       // D7
    output wire        VGA_VS        // C4
);

    // =========================================================================
    // 1. 时钟与复位
    // =========================================================================
    wire clk_sys;
    wire rst;       // 高有效同步复位，下游所有模块统一使用

    clk_rst_gen u_clk_rst (
        .clk_in    (CLK100MHZ),
        .rst_btn_n (CPU_RESETN),
        .clk_sys   (clk_sys),
        .rst_sync  (rst)
    );

    // =========================================================================
    // 2. 按键消抖（5 个通用按键）
    // =========================================================================
    wire [4:0] btn_lvl;   // 消抖后电平
    wire [4:0] btn_p;     // 消抖后单周期脉冲

    debouncer u_db0 (.clk(clk_sys),.rst(rst),.btn_in(BTN[0]),.btn_level(btn_lvl[0]),.btn_pulse(btn_p[0]));
    debouncer u_db1 (.clk(clk_sys),.rst(rst),.btn_in(BTN[1]),.btn_level(btn_lvl[1]),.btn_pulse(btn_p[1]));
    debouncer u_db2 (.clk(clk_sys),.rst(rst),.btn_in(BTN[2]),.btn_level(btn_lvl[2]),.btn_pulse(btn_p[2]));
    debouncer u_db3 (.clk(clk_sys),.rst(rst),.btn_in(BTN[3]),.btn_level(btn_lvl[3]),.btn_pulse(btn_p[3]));
    debouncer u_db4 (.clk(clk_sys),.rst(rst),.btn_in(BTN[4]),.btn_level(btn_lvl[4]),.btn_pulse(btn_p[4]));

    // =========================================================================
    // 3. 拨码/DIP 开关同步
    // =========================================================================
    wire [15:0] sw;

    sw_sync u_sw (
        .clk    (clk_sys),
        .sw_in  (SW),
        .sw_out (sw)
    );

    // =========================================================================
    // 4. PS/2 键盘解码（Bonus）
    // =========================================================================
    wire [7:0] kbd_code;
    wire       kbd_valid;
    wire       kbd_release;

    ps2_keyboard u_ps2 (
        .clk         (clk_sys),
        .rst         (rst),
        .ps2_clk     (PS2_CLK),
        .ps2_data    (PS2_DATA),
        .scancode    (kbd_code),
        .key_valid   (kbd_valid),
        .key_release (kbd_release)
    );

    // =========================================================================
    // 5. 事件仲裁
    // =========================================================================
    wire        ev_pulse;
    wire [3:0]  ev_code;
    wire        buzzer_click;

    event_arbiter u_evt (
        .clk         (clk_sys),
        .rst         (rst),
        .btn0_p      (btn_p[0]),
        .btn1_p      (btn_p[1]),
        .btn2_p      (btn_p[2]),
        .btn3_p      (btn_p[3]),
        .btn4_p      (btn_p[4]),
        .sw          (sw),
        .kbd_valid   (kbd_valid),
        .kbd_code    (kbd_code),
        .kbd_release (kbd_release),
        .ev_pulse    (ev_pulse),
        .ev_code     (ev_code),
        .buzzer_click(buzzer_click)
    );

    // =========================================================================
    // 6. 全局模式控制器
    // =========================================================================
    wire sales_exit_req;
    wire admin_exit_req;
    wire pwd_ok;
    wire pwd_fail3;

    wire mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm;
    wire scroll_enable;

    mode_controller u_mode (
        .clk            (clk_sys),
        .rst            (rst),
        .ev_pulse       (ev_pulse),
        .ev_code        (ev_code),
        .sw             (sw),
        .sales_exit_req (sales_exit_req),
        .admin_exit_req (admin_exit_req),
        .pwd_ok         (pwd_ok),
        .pwd_fail3      (pwd_fail3),
        .mode_main      (mode_main),
        .mode_sales     (mode_sales),
        .mode_pwd       (mode_pwd),
        .mode_admin     (mode_admin),
        .mode_alarm     (mode_alarm),
        .scroll_enable  (scroll_enable)
    );

    // =========================================================================
    // 7. 中央寄存器堆
    // =========================================================================
    // ── 读端口多路选择（按模式决定谁控制 rd_idx）────────────────────────────
    wire [2:0] s_rf_rd_idx;   // 销售模块请求的读索引
    wire [2:0] a_rf_rd_idx;   // 管理模块请求的读索引
    wire [2:0] v_rf_rd_idx;   // VGA 模块请求的读索引（扫描所有商品）

    wire [2:0] rf_rd_idx_mux =
        mode_admin ? a_rf_rd_idx :
        mode_sales ? s_rf_rd_idx :
                     v_rf_rd_idx ;  // 主菜单/密码/报警时 VGA 主导

    // ── reg_file 输出 ────────────────────────────────────────────────────────
    wire [3:0]  rf_rd_name_id;
    wire [7:0]  rf_rd_price;
    wire [3:0]  rf_rd_stock;
    wire        rf_rd_enabled;
    wire [15:0] rf_rd_total_revenue;

    // ── 销售写端口 ───────────────────────────────────────────────────────────
    wire        s_rf_sale_we;
    wire [2:0]  s_rf_sale_idx;
    wire [7:0]  s_rf_sale_amount;
    wire        s_rf_refund_we;
    wire [2:0]  s_rf_refund_idx;
    wire [7:0]  s_rf_refund_amount;

    // ── 管理写端口 ───────────────────────────────────────────────────────────
    wire        a_rf_we_price;
    wire [2:0]  a_rf_price_idx;
    wire [7:0]  a_rf_price_val;
    wire        a_rf_we_restock;
    wire [2:0]  a_rf_restock_idx;
    wire [3:0]  a_rf_restock_amt;
    wire        a_rf_we_toggle;
    wire [2:0]  a_rf_toggle_idx;

    reg_file #(.N(8)) u_rf (
        .clk                (clk_sys),
        .rst                (rst),
        .rd_idx             (rf_rd_idx_mux),
        .rd_name_id         (rf_rd_name_id),
        .rd_price           (rf_rd_price),
        .rd_stock           (rf_rd_stock),
        .rd_enabled         (rf_rd_enabled),
        .rd_total_revenue   (rf_rd_total_revenue),
        .sale_we            (s_rf_sale_we),
        .sale_idx           (s_rf_sale_idx),
        .sale_amount        (s_rf_sale_amount),
        .refund_we          (s_rf_refund_we),
        .refund_idx         (s_rf_refund_idx),
        .refund_amount      (s_rf_refund_amount),
        .admin_we_price     (a_rf_we_price),
        .admin_price_idx    (a_rf_price_idx),
        .admin_price_val    (a_rf_price_val),
        .admin_we_restock   (a_rf_we_restock),
        .admin_restock_idx  (a_rf_restock_idx),
        .admin_restock_amt  (a_rf_restock_amt),
        .admin_we_toggle    (a_rf_we_toggle),
        .admin_toggle_idx   (a_rf_toggle_idx)
    );

    // =========================================================================
    // 8. 销售模块（成员 B）
    // =========================================================================
    wire [2:0]  s_disp_sel_idx;
    wire [7:0]  s_disp_balance;
    wire [7:0]  s_disp_price;
    wire [3:0]  s_disp_countdown;
    wire [3:0]  s_disp_err_code;
    wire [2:0]  s_sales_state;
    wire [15:0] s_led_pattern;
    wire        s_led_breathing;
    wire        s_led_error_blink;

    sales_module u_sales (
        .clk              (clk_sys),
        .rst              (rst),
        .enable           (mode_sales),
        .ev_pulse         (ev_pulse),
        .ev_code          (ev_code),
        .sw               (sw),
        .rf_rd_idx        (s_rf_rd_idx),
        .rf_rd_name_id    (rf_rd_name_id),
        .rf_rd_price      (rf_rd_price),
        .rf_rd_stock      (rf_rd_stock),
        .rf_rd_enabled    (rf_rd_enabled),
        .rf_sale_we       (s_rf_sale_we),
        .rf_sale_idx      (s_rf_sale_idx),
        .rf_sale_amount   (s_rf_sale_amount),
        .rf_refund_we     (s_rf_refund_we),
        .rf_refund_idx    (s_rf_refund_idx),
        .rf_refund_amount (s_rf_refund_amount),
        .disp_sel_idx     (s_disp_sel_idx),
        .disp_balance     (s_disp_balance),
        .disp_price       (s_disp_price),
        .disp_countdown   (s_disp_countdown),
        .disp_err_code    (s_disp_err_code),
        .sales_state      (s_sales_state),
        .led_pattern      (s_led_pattern),
        .led_breathing    (s_led_breathing),
        .led_error_blink  (s_led_error_blink),
        .exit_req         (sales_exit_req)
    );

    // =========================================================================
    // 9. 管理模块（成员 A）
    // =========================================================================
    wire [2:0]  a_admin_subfn;
    wire [2:0]  a_disp_admin_idx;
    wire [7:0]  a_disp_admin_val;
    wire [15:0] a_disp_total_revenue;
    wire [3:0]  a_disp_admin_err;
    wire [15:0] a_led_admin;

    admin_module u_admin (
        .clk                  (clk_sys),
        .rst                  (rst),
        .enable               (mode_admin),
        .ev_pulse             (ev_pulse),
        .ev_code              (ev_code),
        .sw                   (sw),
        .rf_rd_idx            (a_rf_rd_idx),
        .rf_rd_name_id        (rf_rd_name_id),
        .rf_rd_price          (rf_rd_price),
        .rf_rd_stock          (rf_rd_stock),
        .rf_rd_enabled        (rf_rd_enabled),
        .rf_rd_total_revenue  (rf_rd_total_revenue),
        .rf_admin_we_price    (a_rf_we_price),
        .rf_admin_price_idx   (a_rf_price_idx),
        .rf_admin_price_val   (a_rf_price_val),
        .rf_admin_we_restock  (a_rf_we_restock),
        .rf_admin_restock_idx (a_rf_restock_idx),
        .rf_admin_restock_amt (a_rf_restock_amt),
        .rf_admin_we_toggle   (a_rf_we_toggle),
        .rf_admin_toggle_idx  (a_rf_toggle_idx),
        .admin_subfn          (a_admin_subfn),
        .disp_admin_idx       (a_disp_admin_idx),
        .disp_admin_val       (a_disp_admin_val),
        .disp_total_revenue   (a_disp_total_revenue),
        .disp_admin_err       (a_disp_admin_err),
        .led_admin            (a_led_admin),
        .exit_req             (admin_exit_req)
    );

    // =========================================================================
    // 10. 密码校验（成员 A，Bonus）
    // =========================================================================
    wire        pwd_fail;
    wire [1:0]  pwd_fail_cnt;
    wire [3:0]  pwd_err_code;

    password_unit #(.PWD_DEFAULT(8'hB4)) u_pwd (
        .clk           (clk_sys),
        .rst           (rst),
        .enable        (mode_pwd),
        .ev_pulse      (ev_pulse),
        .ev_code       (ev_code),
        .sw            (sw),
        .pwd_ok        (pwd_ok),
        .pwd_fail      (pwd_fail),
        .pwd_fail3     (pwd_fail3),
        .fail_cnt      (pwd_fail_cnt),
        .disp_err_code (pwd_err_code)
    );

    // =========================================================================
    // 11. 显示数据多路选择
    // =========================================================================
    wire [4:0] digit [0:7];
    wire [7:0] dp_mask;

    display_mux u_dispmux (
        .clk           (clk_sys),
        .rst           (rst),
        .mode_main     (mode_main),
        .mode_sales    (mode_sales),
        .mode_pwd      (mode_pwd),
        .mode_admin    (mode_admin),
        .mode_alarm    (mode_alarm),
        .scroll_enable (scroll_enable),
        .s_sel_idx     (s_disp_sel_idx),
        .s_balance     (s_disp_balance),
        .s_price       (s_disp_price),
        .s_countdown   (s_disp_countdown),
        .s_err_code    (s_disp_err_code),
        .s_state       (s_sales_state),
        .rf_name_id    (rf_rd_name_id),
        .a_subfn       (a_admin_subfn),
        .a_idx         (a_disp_admin_idx),
        .a_val         (a_disp_admin_val),
        .a_total       (a_disp_total_revenue),
        .a_err         (a_disp_admin_err),
        .pwd_fail_cnt  (pwd_fail_cnt),
        .pwd_sw_echo   (sw[7:0]),
        .pwd_err       (pwd_err_code),
        .digit0        (digit[0]),
        .digit1        (digit[1]),
        .digit2        (digit[2]),
        .digit3        (digit[3]),
        .digit4        (digit[4]),
        .digit5        (digit[5]),
        .digit6        (digit[6]),
        .digit7        (digit[7]),
        .dp_mask       (dp_mask)
    );

    // =========================================================================
    // 12. 数码管驱动（共阴，双组段线）
    // =========================================================================
    seg7_driver u_seg (
        .clk    (clk_sys),
        .rst    (rst),
        .digit0 (digit[0]),
        .digit1 (digit[1]),
        .digit2 (digit[2]),
        .digit3 (digit[3]),
        .digit4 (digit[4]),
        .digit5 (digit[5]),
        .digit6 (digit[6]),
        .digit7 (digit[7]),
        .dp_mask(dp_mask),
        .SEG0   (SEG0),
        .DP0    (DP0),
        .SEG1   (SEG1),
        .DP1    (DP1),
        .AN     (AN)
    );

    // =========================================================================
    // 13. LED 驱动
    // =========================================================================
    led_driver u_led (
        .clk                 (clk_sys),
        .rst                 (rst),
        .mode_main           (mode_main),
        .mode_sales          (mode_sales),
        .mode_pwd            (mode_pwd),
        .mode_admin          (mode_admin),
        .mode_alarm          (mode_alarm),
        .sales_led_pattern   (s_led_pattern),
        .sales_led_breathing (s_led_breathing),
        .sales_led_error     (s_led_error_blink),
        .admin_led_pattern   (a_led_admin),
        .pwd_sw_echo         (sw[7:0]),
        .led                 (LED)
    );

    // =========================================================================
    // 14. 蜂鸣器驱动（Bonus）
    // =========================================================================
    buzzer_driver u_buzz (
        .clk         (clk_sys),
        .rst         (rst),
        .click_pulse (buzzer_click),
        .mode_alarm  (mode_alarm),
        .AUD_PWM     (AUD_PWM),
        .AUD_SD      (AUD_SD)
    );

    // =========================================================================
    // 15. VGA 驱动（Bonus）
    // =========================================================================
    vga_driver u_vga (
        .clk_100m            (clk_sys),
        .rst                 (rst),
        .mode_main           (mode_main),
        .mode_sales          (mode_sales),
        .mode_pwd            (mode_pwd),
        .mode_admin          (mode_admin),
        .mode_alarm          (mode_alarm),
        .rf_rd_idx_vga       (v_rf_rd_idx),
        .rf_name_id          (rf_rd_name_id),
        .rf_price            (rf_rd_price),
        .rf_stock            (rf_rd_stock),
        .rf_enabled          (rf_rd_enabled),
        .sales_sel_idx       (s_disp_sel_idx),
        .sales_balance       (s_disp_balance),
        .admin_total_revenue (rf_rd_total_revenue),
        .VGA_HS              (VGA_HS),
        .VGA_VS              (VGA_VS),
        .VGA_R               (VGA_R),
        .VGA_G               (VGA_G),
        .VGA_B               (VGA_B)
    );

endmodule


// =============================================================================
//  以下为所有子模块的 STUB 声明
//  端口已冻结。各负责人替换自己模块的实现即可，顶层不需要修改。
// =============================================================================

// -----------------------------------------------------------------------------
// clk_rst_gen [C]
// -----------------------------------------------------------------------------
module clk_rst_gen (
    input  wire clk_in,
    input  wire rst_btn_n,   // 低有效
    output wire clk_sys,
    output wire rst_sync     // 高有效
);
    // TODO[C]: 两级 FF 同步复位。clk_sys 直通 clk_in（如需 PLL 可在此加 MMCM）。
    reg [1:0] rst_sr;
    always @(posedge clk_in or negedge rst_btn_n) begin
        if (!rst_btn_n) rst_sr <= 2'b11;
        else            rst_sr <= {rst_sr[0], 1'b0};
    end
    assign clk_sys  = clk_in;
    assign rst_sync = rst_sr[1];
endmodule

// -----------------------------------------------------------------------------
// debouncer [C]
// -----------------------------------------------------------------------------
module debouncer #(parameter CNT_MAX = 2_000_000)
(
    input  wire clk, rst,
    input  wire btn_in,
    output reg  btn_level,
    output reg  btn_pulse
);
    // TODO[C]: 两级同步 + 计数器消抖 + 上升沿脉冲
    reg btn_sync0, btn_sync1, btn_prev;
    reg [21:0] cnt;
    always @(posedge clk) begin
        if (rst) begin
            btn_sync0 <= 0; btn_sync1 <= 0;
            btn_prev  <= 0; btn_level <= 0;
            btn_pulse <= 0; cnt <= 0;
        end else begin
            btn_sync0 <= btn_in;
            btn_sync1 <= btn_sync0;
            btn_pulse <= 0;
            if (btn_sync1 != btn_level) begin
                if (cnt == CNT_MAX - 1) begin
                    btn_level <= btn_sync1;
                    btn_pulse <= btn_sync1;  // 上升沿=按下时出脉冲
                    cnt <= 0;
                end else cnt <= cnt + 1;
            end else cnt <= 0;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// sw_sync [C]
// -----------------------------------------------------------------------------
module sw_sync (
    input  wire        clk,
    input  wire [15:0] sw_in,
    output reg  [15:0] sw_out
);
    reg [15:0] sw_meta;
    always @(posedge clk) begin
        sw_meta <= sw_in;
        sw_out  <= sw_meta;
    end
endmodule

// -----------------------------------------------------------------------------
// ps2_keyboard [C] (Bonus)
// -----------------------------------------------------------------------------
module ps2_keyboard (
    input  wire       clk, rst,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output reg  [7:0] scancode,
    output reg        key_valid,
    output reg        key_release
);
    // TODO[C]: PS/2 11-bit 帧接收（下降沿采样，LSB先到）
    // 帧格式：1 start(0) + 8 data(LSB first) + 1 parity(odd) + 1 stop(1)
    // break code：收到 0xF0 后下一个 scancode 置 key_release=1
    reg [2:0]  ps2_clk_sync;
    reg [10:0] shift_reg;
    reg [3:0]  bit_cnt;
    reg        got_f0;

    always @(posedge clk) begin
        if (rst) begin
            ps2_clk_sync <= 3'b111; shift_reg <= 0;
            bit_cnt <= 0; key_valid <= 0; key_release <= 0;
            scancode <= 0; got_f0 <= 0;
        end else begin
            ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
            key_valid <= 0;
            // 下降沿检测
            if (ps2_clk_sync[2:1] == 2'b10) begin
                shift_reg <= {ps2_data, shift_reg[10:1]};
                if (bit_cnt == 10) begin
                    // 帧完成（不校验，简化）
                    bit_cnt <= 0;
                    if (shift_reg[8:1] == 8'hF0) begin
                        got_f0 <= 1;
                    end else begin
                        scancode    <= shift_reg[8:1];
                        key_release <= got_f0;
                        key_valid   <= 1;
                        got_f0      <= 0;
                    end
                end else bit_cnt <= bit_cnt + 1;
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// event_arbiter [C]
// -----------------------------------------------------------------------------
module event_arbiter (
    input  wire        clk, rst,
    input  wire        btn0_p, btn1_p, btn2_p, btn3_p, btn4_p,
    input  wire [15:0] sw,
    input  wire        kbd_valid,
    input  wire [7:0]  kbd_code,
    input  wire        kbd_release,
    output reg         ev_pulse,
    output reg  [3:0]  ev_code,
    output reg         buzzer_click
);
    // ev_code 常量
    localparam EV_CONFIRM=4'd0, EV_UP=4'd1, EV_DOWN=4'd2,
               EV_LEFT=4'd3,   EV_RIGHT=4'd4,
               EV_NUM0=4'd5,   // NUM1~9 = 5~13（NUM0=5,NUM1=6,...NUM9=14）
               EV_NONE=4'd15;

    // PS/2 扫描码 → 事件映射（Make code）
    // Enter=0x5A, Esc=0x76, BackSpace=0x66, ←=0x6B, →=0x74
    // 数字 0=0x45, 1=0x16, 2=0x1E, 3=0x26, 4=0x25,
    //       5=0x2E, 6=0x36, 7=0x3D, 8=0x3E, 9=0x46
    function [3:0] kbd_to_ev;
        input [7:0] sc;
        case (sc)
            8'h5A: kbd_to_ev = EV_CONFIRM;
            8'h76: kbd_to_ev = EV_UP;
            8'h66: kbd_to_ev = EV_DOWN;
            8'h6B: kbd_to_ev = EV_LEFT;
            8'h74: kbd_to_ev = EV_RIGHT;
            8'h45: kbd_to_ev = 4'd5;   // 0
            8'h16: kbd_to_ev = 4'd6;   // 1
            8'h1E: kbd_to_ev = 4'd7;   // 2
            8'h26: kbd_to_ev = 4'd8;   // 3
            8'h25: kbd_to_ev = 4'd9;   // 4
            8'h2E: kbd_to_ev = 4'd10;  // 5
            8'h36: kbd_to_ev = 4'd11;  // 6
            8'h3D: kbd_to_ev = 4'd12;  // 7
            8'h3E: kbd_to_ev = 4'd13;  // 8
            8'h46: kbd_to_ev = 4'd14;  // 9
            default: kbd_to_ev = EV_NONE;
        endcase
    endfunction

    wire [3:0] kbd_ev = kbd_to_ev(kbd_code);

    always @(posedge clk) begin
        if (rst) begin
            ev_pulse <= 0; ev_code <= EV_NONE; buzzer_click <= 0;
        end else begin
            ev_pulse     <= 0;
            buzzer_click <= 0;
            // 按键优先，键盘次之
            if (btn0_p) begin ev_pulse<=1; ev_code<=EV_CONFIRM; buzzer_click<=1; end
            else if (btn1_p) begin ev_pulse<=1; ev_code<=EV_UP;      buzzer_click<=1; end
            else if (btn2_p) begin ev_pulse<=1; ev_code<=EV_DOWN;    buzzer_click<=1; end
            else if (btn3_p) begin ev_pulse<=1; ev_code<=EV_LEFT;    buzzer_click<=1; end
            else if (btn4_p) begin ev_pulse<=1; ev_code<=EV_RIGHT;   buzzer_click<=1; end
            else if (kbd_valid && !kbd_release && kbd_ev != EV_NONE) begin
                ev_pulse <= 1; ev_code <= kbd_ev; buzzer_click <= 1;
            end else begin
                ev_code <= EV_NONE;
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// mode_controller [C]
// -----------------------------------------------------------------------------
module mode_controller (
    input  wire        clk, rst,
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    input  wire        sales_exit_req,
    input  wire        admin_exit_req,
    input  wire        pwd_ok,
    input  wire        pwd_fail3,
    output reg         mode_main,
    output reg         mode_sales,
    output reg         mode_pwd,
    output reg         mode_admin,
    output reg         mode_alarm,
    output reg         scroll_enable
);
    localparam S_MAIN=3'd0, S_SALES=3'd1, S_PWD=3'd2,
               S_ADMIN=3'd3, S_ALARM=3'd4;
    localparam EV_CONFIRM=4'd0, EV_UP=4'd1;

    reg [2:0] state;
    // 报警态长按 2s 计时器
    reg [27:0] alarm_hold_cnt;
    localparam HOLD_2S = 28'd200_000_000;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_MAIN;
            alarm_hold_cnt <= 0;
        end else begin
            case (state)
                S_MAIN: begin
                    if (ev_pulse && ev_code == EV_CONFIRM) begin
                        if (sw[0] == 0) state <= S_SALES;
                        else            state <= S_PWD;
                    end
                end
                S_SALES: begin
                    if (sales_exit_req || (ev_pulse && ev_code == EV_UP))
                        state <= S_MAIN;
                end
                S_PWD: begin
                    if (pwd_ok)    state <= S_ADMIN;
                    if (pwd_fail3) state <= S_ALARM;
                    if (ev_pulse && ev_code == EV_UP) state <= S_MAIN;
                end
                S_ADMIN: begin
                    if (admin_exit_req || (ev_pulse && ev_code == EV_UP))
                        state <= S_MAIN;
                end
                S_ALARM: begin
                    // 需要长按 BTN[1]（EV_UP）2 秒才能解除
                    // TODO[C]: 这里先用单次按键解除，实际可改为长按
                    if (ev_pulse && ev_code == EV_UP) state <= S_MAIN;
                end
            endcase
        end
    end

    always @(*) begin
        mode_main    = (state == S_MAIN);
        mode_sales   = (state == S_SALES);
        mode_pwd     = (state == S_PWD);
        mode_admin   = (state == S_ADMIN);
        mode_alarm   = (state == S_ALARM);
        scroll_enable= (state == S_MAIN);
    end
endmodule

// -----------------------------------------------------------------------------
// reg_file [C]
// -----------------------------------------------------------------------------
module reg_file #(parameter N = 8) (
    input  wire        clk, rst,
    input  wire [2:0]  rd_idx,
    output wire [3:0]  rd_name_id,
    output wire [7:0]  rd_price,
    output wire [3:0]  rd_stock,
    output wire        rd_enabled,
    output wire [15:0] rd_total_revenue,
    input  wire        sale_we,
    input  wire [2:0]  sale_idx,
    input  wire [7:0]  sale_amount,
    input  wire        refund_we,
    input  wire [2:0]  refund_idx,
    input  wire [7:0]  refund_amount,
    input  wire        admin_we_price,
    input  wire [2:0]  admin_price_idx,
    input  wire [7:0]  admin_price_val,
    input  wire        admin_we_restock,
    input  wire [2:0]  admin_restock_idx,
    input  wire [3:0]  admin_restock_amt,
    input  wire        admin_we_toggle,
    input  wire [2:0]  admin_toggle_idx
);
    reg [3:0]  name_id [0:N-1];
    reg [7:0]  price   [0:N-1];
    reg [3:0]  stock   [0:N-1];
    reg        enabled [0:N-1];
    reg [15:0] total_revenue;

    // ── 初始值 ────────────────────────────────────────────────────────────────
    integer i;
    initial begin
        // name_id: 0=COLA,1=SPRT,2=ORNG,3=MILK,4=BEER,5=H2O,6=TEA,7=CFEE
        name_id[0]=0; price[0]=30; stock[0]=5; enabled[0]=1;
        name_id[1]=1; price[1]=30; stock[1]=5; enabled[1]=1;
        name_id[2]=2; price[2]=35; stock[2]=4; enabled[2]=1;
        name_id[3]=3; price[3]=40; stock[3]=3; enabled[3]=1;
        name_id[4]=4; price[4]=50; stock[4]=2; enabled[4]=1;
        name_id[5]=5; price[5]=20; stock[5]=8; enabled[5]=1;
        name_id[6]=6; price[6]=25; stock[6]=6; enabled[6]=1;
        name_id[7]=7; price[7]=60; stock[7]=0; enabled[7]=1;
        total_revenue = 0;
    end

    // ── 读 ───────────────────────────────────────────────────────────────────
    assign rd_name_id       = name_id[rd_idx];
    assign rd_price         = price[rd_idx];
    assign rd_stock         = stock[rd_idx];
    assign rd_enabled       = enabled[rd_idx];
    assign rd_total_revenue = total_revenue;

    // ── 写（销售优先于管理）──────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst) begin
            name_id[0]<=0; price[0]<=30; stock[0]<=5; enabled[0]<=1;
            name_id[1]<=1; price[1]<=30; stock[1]<=5; enabled[1]<=1;
            name_id[2]<=2; price[2]<=35; stock[2]<=4; enabled[2]<=1;
            name_id[3]<=3; price[3]<=40; stock[3]<=3; enabled[3]<=1;
            name_id[4]<=4; price[4]<=50; stock[4]<=2; enabled[4]<=1;
            name_id[5]<=5; price[5]<=20; stock[5]<=8; enabled[5]<=1;
            name_id[6]<=6; price[6]<=25; stock[6]<=6; enabled[6]<=1;
            name_id[7]<=7; price[7]<=60; stock[7]<=0; enabled[7]<=1;
            total_revenue <= 0;
        end else begin
            // 销售扣库存
            if (sale_we && stock[sale_idx] != 0) begin
                stock[sale_idx]  <= stock[sale_idx] - 1;
                total_revenue    <= total_revenue + sale_amount;
            end
            // 退款
            if (refund_we) begin
                stock[refund_idx] <= stock[refund_idx] + 1;
                if (total_revenue >= refund_amount)
                    total_revenue <= total_revenue - refund_amount;
                else
                    total_revenue <= 0;
            end
            // 管理写（sales 未占用时才执行）
            if (!sale_we && !refund_we) begin
                if (admin_we_price)
                    price[admin_price_idx] <= admin_price_val;
                if (admin_we_restock)
                    stock[admin_restock_idx] <=
                        (stock[admin_restock_idx] + admin_restock_amt > 15) ?
                        4'd15 : stock[admin_restock_idx] + admin_restock_amt;
                if (admin_we_toggle)
                    enabled[admin_toggle_idx] <= ~enabled[admin_toggle_idx];
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// sales_module [B] — B 实现内部 FSM
// -----------------------------------------------------------------------------
module sales_module (
    input  wire        clk, rst,
    input  wire        enable,
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    output reg  [2:0]  rf_rd_idx,
    input  wire [3:0]  rf_rd_name_id,
    input  wire [7:0]  rf_rd_price,
    input  wire [3:0]  rf_rd_stock,
    input  wire        rf_rd_enabled,
    output reg         rf_sale_we,
    output reg  [2:0]  rf_sale_idx,
    output reg  [7:0]  rf_sale_amount,
    output reg         rf_refund_we,
    output reg  [2:0]  rf_refund_idx,
    output reg  [7:0]  rf_refund_amount,
    output reg  [2:0]  disp_sel_idx,
    output reg  [7:0]  disp_balance,
    output reg  [7:0]  disp_price,
    output reg  [3:0]  disp_countdown,
    output reg  [3:0]  disp_err_code,
    output reg  [2:0]  sales_state,
    output reg  [15:0] led_pattern,
    output reg         led_breathing,
    output reg         led_error_blink,
    output reg         exit_req
);
    // TODO[B]: 实现销售状态机
    // 子状态: 0=IDLE, 1=SELECT, 2=PAY, 3=CONFIRM, 4=DISPENSE, 5=PICKUP_WAIT, 6=DONE, 7=ERR
    // 饮料编号 = sw[3:1]
    // 金额 = sw[7:0]
    // 5s 计时 = 500_000_000 clk 周期
    initial begin
        rf_rd_idx=0; rf_sale_we=0; rf_sale_idx=0; rf_sale_amount=0;
        rf_refund_we=0; rf_refund_idx=0; rf_refund_amount=0;
        disp_sel_idx=0; disp_balance=0; disp_price=0;
        disp_countdown=0; disp_err_code=0; sales_state=0;
        led_pattern=0; led_breathing=0; led_error_blink=0; exit_req=0;
    end
    always @(posedge clk) begin
        if (rst || !enable) begin
            rf_sale_we<=0; rf_refund_we<=0; exit_req<=0;
        end
        // STUB: B 填写
    end
endmodule

// -----------------------------------------------------------------------------
// admin_module [A] — A 实现内部 FSM
// -----------------------------------------------------------------------------
module admin_module (
    input  wire        clk, rst,
    input  wire        enable,
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    output reg  [2:0]  rf_rd_idx,
    input  wire [3:0]  rf_rd_name_id,
    input  wire [7:0]  rf_rd_price,
    input  wire [3:0]  rf_rd_stock,
    input  wire        rf_rd_enabled,
    input  wire [15:0] rf_rd_total_revenue,
    output reg         rf_admin_we_price,
    output reg  [2:0]  rf_admin_price_idx,
    output reg  [7:0]  rf_admin_price_val,
    output reg         rf_admin_we_restock,
    output reg  [2:0]  rf_admin_restock_idx,
    output reg  [3:0]  rf_admin_restock_amt,
    output reg         rf_admin_we_toggle,
    output reg  [2:0]  rf_admin_toggle_idx,
    output reg  [2:0]  admin_subfn,
    output reg  [2:0]  disp_admin_idx,
    output reg  [7:0]  disp_admin_val,
    output reg  [15:0] disp_total_revenue,
    output reg  [3:0]  disp_admin_err,
    output reg  [15:0] led_admin,
    output reg         exit_req
);
    // TODO[A]: 实现管理子功能路由
    // 子功能由 sw[14:12] 决定（见 README §4.9）
    // 各写使能仅在 EV_CONFIRM 确认时拉高 1 周期
    initial begin
        rf_rd_idx=0;
        rf_admin_we_price=0; rf_admin_price_idx=0; rf_admin_price_val=0;
        rf_admin_we_restock=0; rf_admin_restock_idx=0; rf_admin_restock_amt=0;
        rf_admin_we_toggle=0; rf_admin_toggle_idx=0;
        admin_subfn=0; disp_admin_idx=0; disp_admin_val=0;
        disp_total_revenue=0; disp_admin_err=0; led_admin=0; exit_req=0;
    end
    always @(posedge clk) begin
        if (rst || !enable) begin
            rf_admin_we_price<=0; rf_admin_we_restock<=0;
            rf_admin_we_toggle<=0; exit_req<=0;
        end
        // STUB: A 填写
    end
endmodule

// -----------------------------------------------------------------------------
// password_unit [A] (Bonus)
// -----------------------------------------------------------------------------
module password_unit #(parameter PWD_DEFAULT = 8'hB4)
(
    input  wire        clk, rst,
    input  wire        enable,
    input  wire        ev_pulse,
    input  wire [3:0]  ev_code,
    input  wire [15:0] sw,
    output reg         pwd_ok,
    output reg         pwd_fail,
    output reg         pwd_fail3,
    output reg  [1:0]  fail_cnt,
    output reg  [3:0]  disp_err_code
);
    localparam EV_CONFIRM = 4'd0;
    // TODO[A]: sw[7:0] + EV_CONFIRM 校验
    // 错误: fail_cnt++, pwd_fail 脉冲; 3次: pwd_fail3 锁存
    // 正确: pwd_ok 脉冲, fail_cnt 清零
    always @(posedge clk) begin
        if (rst) begin
            pwd_ok<=0; pwd_fail<=0; pwd_fail3<=0;
            fail_cnt<=0; disp_err_code<=0;
        end else if (!enable) begin
            pwd_ok<=0; pwd_fail<=0;
            // pwd_fail3 保持锁存，由 mode_controller 控制清零
        end else begin
            pwd_ok <= 0; pwd_fail <= 0;
            if (ev_pulse && ev_code == EV_CONFIRM) begin
                if (sw[7:0] == PWD_DEFAULT[7:0]) begin
                    pwd_ok   <= 1;
                    fail_cnt <= 0;
                end else begin
                    pwd_fail <= 1;
                    if (fail_cnt == 2'd2)
                        pwd_fail3 <= 1;
                    else
                        fail_cnt <= fail_cnt + 1;
                end
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// display_mux [C]
// -----------------------------------------------------------------------------
module display_mux (
    input  wire        clk, rst,
    input  wire        mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    input  wire        scroll_enable,
    input  wire [2:0]  s_sel_idx,
    input  wire [7:0]  s_balance, s_price,
    input  wire [3:0]  s_countdown, s_err_code,
    input  wire [2:0]  s_state,
    input  wire [3:0]  rf_name_id,
    input  wire [2:0]  a_subfn,
    input  wire [2:0]  a_idx,
    input  wire [7:0]  a_val,
    input  wire [15:0] a_total,
    input  wire [3:0]  a_err,
    input  wire [1:0]  pwd_fail_cnt,
    input  wire [7:0]  pwd_sw_echo,
    input  wire [3:0]  pwd_err,
    output reg  [4:0]  digit0, digit1, digit2, digit3,
    output reg  [4:0]  digit4, digit5, digit6, digit7,
    output reg  [7:0]  dp_mask
);
    // 字符 ID: 0~9=数字, 10=H,11=E,12=L,13=O,14=P,15=S,16=n,17=r,18=t,
    //          19=A,20=b,21=c,22=d,23=F,24=U,25='-',26=空白
    localparam BLANK=5'd26, DASH=5'd25;
    localparam CH_H=5'd10, CH_E=5'd11, CH_L=5'd12, CH_O=5'd13;
    localparam CH_P=5'd14, CH_S=5'd15, CH_n=5'd16, CH_r=5'd17;
    localparam CH_t=5'd18, CH_A=5'd19, CH_b=5'd20, CH_c=5'd21;
    localparam CH_d=5'd22, CH_F=5'd23, CH_U=5'd24;

    // 主菜单滚动
    reg [23:0] scroll_cnt;
    reg [3:0]  scroll_pos;
    // 滚动序列: H E L L O [空] [空] [空] 共 8 帧，再到 [空][空] O P E N [空][空]
    always @(posedge clk) begin
        if (rst) begin scroll_cnt<=0; scroll_pos<=0; end
        else if (scroll_enable) begin
            if (scroll_cnt == 24'd50_000_000) begin   // 0.5s 步进
                scroll_cnt  <= 0;
                scroll_pos  <= (scroll_pos == 15) ? 0 : scroll_pos + 1;
            end else scroll_cnt <= scroll_cnt + 1;
        end else scroll_cnt <= 0;
    end

    // 名称查表（name_id→4字符 ID）
    // 0=COLA: C(21) O(13) L(12) A(19)
    // 1=SPRT: S(15) P(14) r(17) t(18)
    // 2=ORNG: O(13) r(17) n(16) G(需要g≈d=22)
    // 3=MILK: M→需要/用n(16)代 I(1) L(12) K→用b(20)代
    // 4=BEER: b(20) E(11) E(11) r(17)
    // 5=H2O : H(10) 2    O(13) [空]
    // 6=TEA : t(18) E(11) A(19) [空]
    // 7=CFEE: c(21) F(23) E(11) E(11)
    task get_name_chars;
        input [3:0] nid;
        output [4:0] c3,c2,c1,c0;  // c3=最左字符
        case (nid)
            4'd0: begin c3=CH_c; c2=CH_O; c1=CH_L; c0=CH_A; end   // COLA
            4'd1: begin c3=CH_S; c2=CH_P; c1=CH_r; c0=CH_t; end   // SPrt
            4'd2: begin c3=CH_O; c2=CH_r; c1=CH_n; c0=CH_d; end   // Ornd≈ORNG
            4'd3: begin c3=CH_n; c2=5'd1; c1=CH_L; c0=CH_b; end   // nILb≈MILK
            4'd4: begin c3=CH_b; c2=CH_E; c1=CH_E; c0=CH_r; end   // bEEr≈BEER
            4'd5: begin c3=CH_H; c2=5'd2; c1=CH_O; c0=BLANK;end   // H2O
            4'd6: begin c3=CH_t; c2=CH_E; c1=CH_A; c0=BLANK;end   // tEA
            4'd7: begin c3=CH_c; c2=CH_F; c1=CH_E; c0=CH_E; end   // cFEE≈CFEE
            default: begin c3=BLANK; c2=BLANK; c1=BLANK; c0=BLANK; end
        endcase
    endtask

    reg [4:0] nc3, nc2, nc1, nc0;

    // 主逻辑
    always @(posedge clk) begin
        if (rst) begin
            digit7<=BLANK; digit6<=BLANK; digit5<=BLANK; digit4<=BLANK;
            digit3<=BLANK; digit2<=BLANK; digit1<=BLANK; digit0<=BLANK;
            dp_mask <= 8'h00;
        end else begin
            dp_mask <= 8'h00;
            // ── 主菜单滚动 ───────────────────────────────────────────────────
            if (mode_main) begin
                // 16 帧滚动：先 HELLO 再 OPEN
                case (scroll_pos)
                    // HELLO 从右向左滚入
                    0:  begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=CH_H; end
                    1:  begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=BLANK;digit2<=BLANK;digit1<=CH_H;digit0<=CH_E; end
                    2:  begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=BLANK;digit2<=CH_H;digit1<=CH_E;digit0<=CH_L; end
                    3:  begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=CH_H;digit2<=CH_E;digit1<=CH_L;digit0<=CH_L; end
                    4:  begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=CH_H;digit3<=CH_E;digit2<=CH_L;digit1<=CH_L;digit0<=CH_O; end
                    5:  begin digit7<=BLANK;digit6<=BLANK;digit5<=CH_H;digit4<=CH_E;digit3<=CH_L;digit2<=CH_L;digit1<=CH_O;digit0<=BLANK; end
                    6:  begin digit7<=BLANK;digit6<=CH_H;digit5<=CH_E;digit4<=CH_L;digit3<=CH_L;digit2<=CH_O;digit1<=BLANK;digit0<=BLANK; end
                    7:  begin digit7<=CH_H;digit6<=CH_E;digit5<=CH_L;digit4<=CH_L;digit3<=CH_O;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK; end
                    // OPEN 滚入
                    8:  begin digit7<=CH_E;digit6<=CH_L;digit5<=CH_L;digit4<=CH_O;digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK; end
                    9:  begin digit7<=CH_O;digit6<=CH_P;digit5<=CH_E;digit4<=CH_n;digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK; end
                    10: begin digit7<=BLANK;digit6<=CH_O;digit5<=CH_P;digit4<=CH_E;digit3<=CH_n;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK; end
                    11: begin digit7<=BLANK;digit6<=BLANK;digit5<=CH_O;digit4<=CH_P;digit3<=CH_E;digit2<=CH_n;digit1<=BLANK;digit0<=BLANK; end
                    12: begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=CH_O;digit3<=CH_P;digit2<=CH_E;digit1<=CH_n;digit0<=BLANK; end
                    13: begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=CH_O;digit2<=CH_P;digit1<=CH_E;digit0<=CH_n; end
                    14: begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=BLANK;digit2<=CH_O;digit1<=CH_P;digit0<=CH_E; end
                    15: begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=BLANK;digit2<=BLANK;digit1<=CH_O;digit0<=CH_P; end
                    default: begin digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK; end
                endcase
            end
            // ── 密码模式 ─────────────────────────────────────────────────────
            else if (mode_pwd) begin
                // [P][S][错误次数][空][sw7~4(hex)][sw3~0(hex)]
                digit7 <= CH_P;
                digit6 <= CH_S;
                digit5 <= {3'b0, pwd_fail_cnt};   // 0~3
                digit4 <= BLANK;
                digit3 <= pwd_sw_echo[7:4];        // 高4位 hex
                digit2 <= pwd_sw_echo[3:0];        // 低4位 hex
                digit1 <= BLANK;
                digit0 <= BLANK;
            end
            // ── 报警模式 ─────────────────────────────────────────────────────
            else if (mode_alarm) begin
                // A L A r M [空] [错误次数] [空]
                digit7 <= CH_A;
                digit6 <= CH_L;
                digit5 <= CH_A;
                digit4 <= CH_r;
                digit3 <= 5'd22; // M 用 d 代（7段近似），TODO[C]可加 M 字符
                digit2 <= BLANK;
                digit1 <= {3'b0, pwd_fail_cnt + 2'd3};  // 显示为 3
                digit0 <= BLANK;
            end
            // ── 销售模式 ─────────────────────────────────────────────────────
            else if (mode_sales) begin
                get_name_chars(rf_name_id, nc3, nc2, nc1, nc0);
                case (s_state)
                    3'd0,  // IDLE
                    3'd1:  begin   // SELECT: [编号][名称4字符][空][P][r][价格]
                        digit7 <= {2'b0, s_sel_idx};
                        digit6 <= nc3; digit5 <= nc2; digit4 <= nc1; digit3 <= nc0;
                        digit2 <= CH_P; digit1 <= CH_r;
                        digit0 <= s_price % 10;            // 价格个位
                        dp_mask[1] <= 1;                   // 十位点亮小数点表示十进制
                    end
                    3'd2:  begin   // PAY: [b][A][L][余额高][余额低][/][价格高][价格低]
                        digit7 <= CH_b; digit6 <= CH_A; digit5 <= CH_L;
                        digit4 <= s_balance / 10;
                        digit3 <= s_balance % 10;
                        digit2 <= DASH;
                        digit1 <= s_price / 10;
                        digit0 <= s_price % 10;
                    end
                    3'd3,  // CONFIRM
                    3'd4:  begin   // DISPENSE
                        digit7 <= CH_d; digit6 <= CH_O; digit5 <= CH_n; digit4 <= CH_E;
                        digit3 <= BLANK; digit2 <= BLANK; digit1 <= BLANK; digit0 <= BLANK;
                    end
                    3'd5:  begin   // PICKUP_WAIT: [P][i][c][k][空][空][空][倒计时]
                        digit7 <= CH_P;
                        digit6 <= 5'd1;  // i≈1
                        digit5 <= CH_c;
                        digit4 <= CH_b;  // k 近似
                        digit3 <= BLANK; digit2 <= BLANK; digit1 <= BLANK;
                        digit0 <= {1'b0, s_countdown};
                    end
                    3'd6:  begin   // DONE
                        digit7<=CH_d;digit6<=CH_O;digit5<=CH_n;digit4<=CH_E;
                        digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK;
                    end
                    3'd7:  begin   // ERROR: [E][-][错误码][空空空空空]
                        digit7 <= CH_E; digit6 <= DASH;
                        digit5 <= {1'b0, s_err_code};
                        digit4<=BLANK;digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK;
                    end
                    default: begin
                        digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;
                        digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK;
                    end
                endcase
            end
            // ── 管理模式 ─────────────────────────────────────────────────────
            else if (mode_admin) begin
                get_name_chars(rf_name_id, nc3, nc2, nc1, nc0);
                case (a_subfn)
                    3'd0:  begin  // 查库存: [编号][名称][S][t][库存]
                        digit7 <= {2'b0, a_idx};
                        digit6 <= nc3; digit5 <= nc2; digit4 <= nc1; // 只显3字符
                        digit3 <= CH_S; digit2 <= CH_t;
                        digit1 <= a_val / 10; digit0 <= a_val % 10;
                    end
                    3'd1:  begin  // 查价格: [编号][名称][价格.角]
                        digit7 <= {2'b0, a_idx};
                        digit6 <= nc3; digit5 <= nc2; digit4 <= nc1;
                        digit3 <= a_val / 10; digit2 <= a_val % 10;
                        digit1 <= BLANK; digit0 <= BLANK;
                        dp_mask[3] <= 1;
                    end
                    3'd2:  begin  // 查累计: [t][o][t][A][L][金额3位]
                        digit7 <= CH_t; digit6 <= CH_O; digit5 <= CH_t;
                        digit4 <= CH_A; digit3 <= CH_L;
                        digit2 <= (a_total / 100) % 10;
                        digit1 <= (a_total / 10)  % 10;
                        digit0 <= a_total % 10;
                    end
                    3'd3:  begin  // 查停售: [d][i][S][空][编号][状态]
                        digit7<=CH_d;digit6<=5'd1;digit5<=CH_S;digit4<=BLANK;
                        digit3<={2'b0,a_idx};digit2<=BLANK;
                        digit1<=(a_val[0]? CH_O : CH_d); // O=在售, d≈off=停售
                        digit0<=BLANK;
                    end
                    3'd4:  begin  // 改价: [P][r][i][空][编号][新价格]
                        digit7<=CH_P;digit6<=CH_r;digit5<=5'd1;digit4<=BLANK;
                        digit3<={2'b0,a_idx};
                        digit2<=a_val/10; digit1<=a_val%10; digit0<=BLANK;
                    end
                    3'd5:  begin  // 补货: [A][d][d][空][编号][增量]
                        digit7<=CH_A;digit6<=CH_d;digit5<=CH_d;digit4<=BLANK;
                        digit3<={2'b0,a_idx};
                        digit2<=a_val/10; digit1<=a_val%10; digit0<=BLANK;
                    end
                    3'd6:  begin  // 切停售: [t][O][G][空][编号][状态]
                        digit7<=CH_t;digit6<=CH_O;digit5<=CH_d;digit4<=BLANK;
                        digit3<={2'b0,a_idx};digit2<=BLANK;
                        digit1<=(a_val[0]? CH_O : CH_d);
                        digit0<=BLANK;
                    end
                    3'd7:  begin  // 退出
                        digit7<=CH_E;digit6<=5'd12;digit5<=5'd12;digit4<=CH_A;
                        digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK;
                        // ELLA 近似 EXIT 的显示
                    end
                    default: begin
                        digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;
                        digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK;
                    end
                endcase
            end else begin
                digit7<=BLANK;digit6<=BLANK;digit5<=BLANK;digit4<=BLANK;
                digit3<=BLANK;digit2<=BLANK;digit1<=BLANK;digit0<=BLANK;
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// seg7_driver [C] — EGO1 共阴极，双组独立段线
// -----------------------------------------------------------------------------
module seg7_driver (
    input  wire        clk, rst,
    input  wire [4:0]  digit0, digit1, digit2, digit3,
    input  wire [4:0]  digit4, digit5, digit6, digit7,
    input  wire [7:0]  dp_mask,
    output reg  [6:0]  SEG0,   // DN0 段线，高有效
    output reg         DP0,
    output reg  [6:0]  SEG1,   // DN1 段线，高有效
    output reg         DP1,
    output reg  [7:0]  AN      // 位选，高有效
);
    // 分频：100 MHz / 100_000 = 1 kHz / 位
    reg [16:0] div_cnt;
    reg [2:0]  scan_idx;

    always @(posedge clk) begin
        if (rst) begin div_cnt<=0; scan_idx<=0; end
        else if (div_cnt == 17'd99_999) begin div_cnt<=0; scan_idx<=scan_idx+1; end
        else div_cnt <= div_cnt + 1;
    end

    // 字符 → 7 段编码（高有效，位序 [6:0] = {G,F,E,D,C,B,A}）
    function [6:0] char_to_seg;
        input [4:0] ch;
        case (ch)
            5'd0:  char_to_seg = 7'b0111111; // 0
            5'd1:  char_to_seg = 7'b0000110; // 1
            5'd2:  char_to_seg = 7'b1011011; // 2
            5'd3:  char_to_seg = 7'b1001111; // 3
            5'd4:  char_to_seg = 7'b1100110; // 4
            5'd5:  char_to_seg = 7'b1101101; // 5
            5'd6:  char_to_seg = 7'b1111101; // 6
            5'd7:  char_to_seg = 7'b0000111; // 7
            5'd8:  char_to_seg = 7'b1111111; // 8
            5'd9:  char_to_seg = 7'b1101111; // 9
            5'd10: char_to_seg = 7'b1110110; // H
            5'd11: char_to_seg = 7'b1111001; // E
            5'd12: char_to_seg = 7'b0111000; // L
            5'd13: char_to_seg = 7'b0111111; // O
            5'd14: char_to_seg = 7'b1110011; // P
            5'd15: char_to_seg = 7'b1101101; // S
            5'd16: char_to_seg = 7'b1010100; // n
            5'd17: char_to_seg = 7'b1010000; // r
            5'd18: char_to_seg = 7'b1111000; // t
            5'd19: char_to_seg = 7'b1110111; // A
            5'd20: char_to_seg = 7'b1111100; // b
            5'd21: char_to_seg = 7'b1011000; // c
            5'd22: char_to_seg = 7'b1011110; // d
            5'd23: char_to_seg = 7'b1110001; // F
            5'd24: char_to_seg = 7'b0111110; // U
            5'd25: char_to_seg = 7'b1000000; // -
            5'd26: char_to_seg = 7'b0000000; // 空白
            default: char_to_seg = 7'b0000000;
        endcase
    endfunction

    reg [4:0] cur_digit;
    reg       cur_dp;

    always @(*) begin
        case (scan_idx)
            3'd0: begin cur_digit = digit0; cur_dp = dp_mask[0]; end
            3'd1: begin cur_digit = digit1; cur_dp = dp_mask[1]; end
            3'd2: begin cur_digit = digit2; cur_dp = dp_mask[2]; end
            3'd3: begin cur_digit = digit3; cur_dp = dp_mask[3]; end
            3'd4: begin cur_digit = digit4; cur_dp = dp_mask[4]; end
            3'd5: begin cur_digit = digit5; cur_dp = dp_mask[5]; end
            3'd6: begin cur_digit = digit6; cur_dp = dp_mask[6]; end
            3'd7: begin cur_digit = digit7; cur_dp = dp_mask[7]; end
            default: begin cur_digit = 5'd26; cur_dp = 0; end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            AN <= 8'h00; SEG0 <= 7'h00; DP0 <= 0; SEG1 <= 7'h00; DP1 <= 0;
        end else begin
            AN   <= (8'h01 << scan_idx);   // 高有效，选中当前位
            if (scan_idx <= 3'd3) begin    // 位 0~3 → DN0
                SEG0 <= char_to_seg(cur_digit);
                DP0  <= cur_dp;
                SEG1 <= 7'h00;
                DP1  <= 1'b0;
            end else begin                 // 位 4~7 → DN1
                SEG1 <= char_to_seg(cur_digit);
                DP1  <= cur_dp;
                SEG0 <= 7'h00;
                DP0  <= 1'b0;
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// led_driver [C]
// -----------------------------------------------------------------------------
module led_driver (
    input  wire        clk, rst,
    input  wire        mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    input  wire [15:0] sales_led_pattern,
    input  wire        sales_led_breathing,
    input  wire        sales_led_error,
    input  wire [15:0] admin_led_pattern,
    input  wire [7:0]  pwd_sw_echo,
    output reg  [15:0] led
);
    // TODO[C]: 实现各模式 LED 效果
    // 主菜单：跑马灯；销售：透传 pattern；密码：低8位=sw；管理：透传；报警：全闪
    reg [26:0] cnt;
    reg [3:0]  chase_pos;   // 跑马灯位置
    reg        flash_bit;   // 报警闪烁位

    always @(posedge clk) begin
        if (rst) begin cnt<=0; chase_pos<=0; flash_bit<=0; end
        else begin
            if (cnt == 27'd49_999_999) begin  // 0.5s
                cnt <= 0;
                chase_pos <= (chase_pos == 15) ? 0 : chase_pos + 1;
                flash_bit <= ~flash_bit;
            end else cnt <= cnt + 1;
        end
    end

    always @(*) begin
        if (mode_alarm)
            led = flash_bit ? 16'hFFFF : 16'h0000;
        else if (mode_main)
            led = (16'h0001 << chase_pos);
        else if (mode_sales)
            led = sales_led_pattern;
        else if (mode_pwd)
            led = {8'h00, pwd_sw_echo};
        else if (mode_admin)
            led = admin_led_pattern;
        else
            led = 16'h0000;
    end
endmodule

// -----------------------------------------------------------------------------
// buzzer_driver [C] (Bonus)
// -----------------------------------------------------------------------------
module buzzer_driver (
    input  wire clk, rst,
    input  wire click_pulse,
    input  wire mode_alarm,
    output wire AUD_PWM,
    output wire AUD_SD
);
    // TODO[C]: 实现操作音（4kHz, 50ms）和报警音（1kHz/2kHz交替, 200ms切换）
    // EGO1 音频为标准推挽，直接 assign AUD_PWM = pwm_out

    // 4 kHz: 100M / (4000*2) = 12500 分频
    // 1 kHz: 100M / (1000*2) = 50000
    // 2 kHz: 100M / (2000*2) = 25000

    reg [16:0] tone_div_cnt;
    reg [16:0] tone_div_max;
    reg        tone_out;
    reg [22:0] click_cnt;      // 50ms = 5_000_000 cycles
    reg        click_active;
    reg [23:0] alarm_switch_cnt; // 200ms = 20_000_000 cycles
    reg        alarm_tone_sel;   // 0=1kHz, 1=2kHz
    reg        pwm_out;

    localparam DIV_4K = 17'd12500;
    localparam DIV_1K = 17'd50000;
    localparam DIV_2K = 17'd25000;

    always @(posedge clk) begin
        if (rst) begin
            tone_div_cnt<=0; tone_out<=0; click_cnt<=0;
            click_active<=0; alarm_switch_cnt<=0; alarm_tone_sel<=0;
        end else begin
            // 操作音计时
            if (click_pulse) begin click_active<=1; click_cnt<=0; end
            if (click_active) begin
                if (click_cnt == 23'd4_999_999) click_active<=0;
                else click_cnt <= click_cnt + 1;
            end
            // 报警音切换
            if (mode_alarm) begin
                if (alarm_switch_cnt == 24'd19_999_999) begin
                    alarm_switch_cnt <= 0;
                    alarm_tone_sel   <= ~alarm_tone_sel;
                end else alarm_switch_cnt <= alarm_switch_cnt + 1;
            end else alarm_switch_cnt <= 0;
            // 确定分频值
            if (click_active)
                tone_div_max <= DIV_4K;
            else if (mode_alarm)
                tone_div_max <= alarm_tone_sel ? DIV_2K : DIV_1K;
            else
                tone_div_max <= DIV_4K;  // 无声时不分频（靠 pwm_out=0 静音）
            // 方波生成
            if (click_active || mode_alarm) begin
                if (tone_div_cnt >= tone_div_max - 1) begin
                    tone_div_cnt <= 0;
                    tone_out     <= ~tone_out;
                end else tone_div_cnt <= tone_div_cnt + 1;
            end else begin
                tone_div_cnt <= 0;
                tone_out     <= 0;
            end
        end
    end

    assign pwm_out = tone_out;
    assign AUD_PWM = pwm_out;   // 标准推挽，直接赋值
    assign AUD_SD  = 1'b1;      // 常使能
endmodule

// -----------------------------------------------------------------------------
// vga_driver [C] (Bonus)
// -----------------------------------------------------------------------------
module vga_driver (
    input  wire        clk_100m, rst,
    input  wire        mode_main, mode_sales, mode_pwd, mode_admin, mode_alarm,
    output reg  [2:0]  rf_rd_idx_vga,
    input  wire [3:0]  rf_name_id,
    input  wire [7:0]  rf_price,
    input  wire [3:0]  rf_stock,
    input  wire        rf_enabled,
    input  wire [2:0]  sales_sel_idx,
    input  wire [7:0]  sales_balance,
    input  wire [15:0] admin_total_revenue,
    output wire        VGA_HS, VGA_VS,
    output wire [3:0]  VGA_R, VGA_G, VGA_B
);
    // TODO[C]:
    // 1. 25 MHz 像素时钟（100 MHz / 4 分频）
    // 2. 640×480@60Hz VGA 时序
    //    H: 有效640 + 前沿16 + 同步96 + 后沿48 = 800总
    //    V: 有效480 + 前沿10 + 同步2  + 后沿33 = 525总
    // 3. 字符 ROM（8×16 点阵）渲染商品列表
    // 4. 按模式切换画面

    reg [1:0]  pix_div;
    reg        pix_clk;
    reg [9:0]  h_cnt, v_cnt;
    reg        h_sync, v_sync;
    reg        in_display;

    // 25 MHz 像素时钟
    always @(posedge clk_100m) begin
        if (rst) pix_div <= 0;
        else     pix_div <= pix_div + 1;
    end
    always @(posedge clk_100m) begin
        if (rst) pix_clk <= 0;
        else if (pix_div == 2'd1) pix_clk <= ~pix_clk;
    end

    // 行列计数器（在像素时钟上升沿更新）
    always @(posedge clk_100m) begin
        if (rst) begin h_cnt<=0; v_cnt<=0; end
        else if (pix_div == 2'd3) begin  // pix_clk 上升沿附近
            if (h_cnt == 10'd799) begin
                h_cnt <= 0;
                if (v_cnt == 10'd524) v_cnt <= 0;
                else                  v_cnt <= v_cnt + 1;
            end else h_cnt <= h_cnt + 1;
        end
    end

    assign VGA_HS = (h_cnt >= 10'd656 && h_cnt < 10'd752) ? 1'b0 : 1'b1;
    assign VGA_VS = (v_cnt >= 10'd490 && v_cnt < 10'd492) ? 1'b0 : 1'b1;

    wire disp_area = (h_cnt < 10'd640) && (v_cnt < 10'd480);

    // STUB: 简单彩色背景（C 后续替换为字符渲染）
    assign VGA_R = disp_area ? (mode_alarm ? 4'hF : (mode_sales ? 4'h0 : 4'h2)) : 4'h0;
    assign VGA_G = disp_area ? (mode_sales ? 4'hA : (mode_admin ? 4'h8 : 4'h2)) : 4'h0;
    assign VGA_B = disp_area ? (mode_main  ? 4'hF : (mode_pwd   ? 4'h8 : 4'h2)) : 4'h0;

    always @(posedge clk_100m) rf_rd_idx_vga <= 3'd0;  // STUB
endmodule
