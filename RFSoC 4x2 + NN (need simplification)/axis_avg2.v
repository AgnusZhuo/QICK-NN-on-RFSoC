// ---------------------------------------------------------------
// axis_avg2
//   552MHz 域的 2:1 相邻求和（取平均）：
//   把相邻两个 AXIS 字的 I、Q 分量分别相加后右移一位，输出一个字。
//   输出速率 276.5M 字/s，与后级 Clock Converter 读侧(276.5MHz)相等，
//   FIFO 永不积压。
//
//   相比直接抽取：信号相干累加、噪声按 √2 增长，SNR 提升 √2；
//   而抽取扔掉一半样本，SNR 反而掉 √2。两者相差 2 倍。
//
//   数据格式（与 NN_axi.cpp 中的解包一致）：
//     [13:0]  = I (14位有符号)
//     [29:16] = Q (14位有符号)
//   两数相加得 15 位，右移一位后仍为 14 位，不会溢出，
//   下游 ap_fixed<14,14> 无需任何改动。
// ---------------------------------------------------------------
module axis_avg2 (
    input  wire        aclk,      // 552 MHz (clk_adc0_x2)
    input  wire        aresetn,   // 低有效

    // 从 broadcaster 进
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // 出到 AXIS Clock Converter 的写侧
    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready
);

    // 上游 broadcaster 不看反压，恒接收
    assign s_axis_tready = 1'b1;

    wire signed [13:0] i_in = s_axis_tdata[13:0];
    wire signed [13:0] q_in = s_axis_tdata[29:16];

    reg  signed [13:0] i_hold;
    reg  signed [13:0] q_hold;
    reg                phase;

    // 15 位和，取 [14:1] 等价于算术右移一位（取平均）
    wire signed [14:0] i_sum = i_hold + i_in;
    wire signed [14:0] q_sum = q_hold + q_in;

    always @(posedge aclk) begin
        if (!aresetn) begin
            phase         <= 1'b0;
            i_hold        <= 14'sd0;
            q_hold        <= 14'sd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= 32'd0;
        end else begin
            m_axis_tvalid <= 1'b0;       // 默认拉低，每两个字才输出一拍

            if (s_axis_tvalid) begin
                phase <= ~phase;

                if (phase == 1'b0) begin
                    // 第一个字：暂存
                    i_hold <= i_in;
                    q_hold <= q_in;
                end else begin
                    // 第二个字：与暂存值求和取平均后输出
                    m_axis_tdata  <= {2'b00, q_sum[14:1], 2'b00, i_sum[14:1]};
                    m_axis_tvalid <= 1'b1;
                end
            end
        end
    end

endmodule
