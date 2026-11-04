// ADS1115 的简易 I2C 主机，用于读取外接 FSR 力敏电阻传感器。
// 读取单端 AIN0（以 GND 为参考）的有符号转换结果。
// sample 是 ADC 原始 16 位有符号码；每次成功读取时 valid 拉高一个 clk 周期。
// ack_error 表示未收到从机 ACK；发生错误时不会产生 valid 脉冲。
// SCL/SDA 接入带 3.3 V 外部上拉电阻的 I2C 总线。
module ads1115_reader(
    input wire clk, reset_n,
    inout wire scl, sda,
    output reg [15:0] sample,
    output reg valid,
    output reg ack_error
);
    // 开漏输出：FPGA 只拉低总线或释放为高阻态，不主动输出高电平。
    reg scl_low, sda_low;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    reg sda_meta, sda_sync;
    reg [6:0] divider;
    reg [3:0] step;
    reg [2:0] phase, bit_idx;
    reg [8:0] wait_ticks;
    reg [7:0] rx_byte;
    reg [15:0] partial;
    reg [7:0] tx_byte;

    // 发送给 ADC 的字节序列：设备地址、配置寄存器指针/配置值，
    // 然后是转换寄存器指针和读地址。
    always @* begin
        case (step)
            1, 8: tx_byte = 8'h90; // ADS1115 地址 0x48，写操作
            2: tx_byte = 8'h01;    // 配置寄存器指针
            3: tx_byte = 8'h42;
            4: tx_byte = 8'he3;    // AIN0-GND，量程 ±4.096 V，连续转换，860 SPS
            9: tx_byte = 8'h00;    // 转换寄存器指针
            11: tx_byte = 8'h91;   // 地址 0x48，读操作
            default: tx_byte = 0;
        endcase
    end

    // 每 125 个 sys_clk 周期推进一个 I2C 子步骤（50 MHz 时 SCL 为 100 kHz）。
    // 状态机配置连续转换、间隔轮询；只有两个字节均读完且 ACK 正常才输出样本。
    always @(posedge clk) begin
        if (!reset_n) begin
            scl_low <= 0;
            sda_low <= 0;
            sda_meta <= 1;
            sda_sync <= 1;
            divider <= 0;
            step <= 0;
            phase <= 0;
            bit_idx <= 7;
            wait_ticks <= 0;
            rx_byte <= 0;
            partial <= 0;
            sample <= 0;
            valid <= 0;
            ack_error <= 0;
        end else begin
            sda_meta <= sda;
            sda_sync <= sda_meta;
            valid <= 0;
            if (divider == 7'd124) begin
                divider <= 0;
                case (step)
                    0, 7, 10: case (phase) // START or repeated START
                        0: begin scl_low <= 0; sda_low <= 0; phase <= 1; end
                        1: begin sda_low <= 1; phase <= 2; end
                        2: begin
                            scl_low <= 1;
                            phase <= 0;
                            step <= step + 1'b1;
                            bit_idx <= 7;
                            if (step == 7) ack_error <= 0;
                        end
                    endcase
                    1, 2, 3, 4, 8, 9, 11: case (phase) // WRITE byte + slave ACK
                        0: begin
                            scl_low <= 1;
                            sda_low <= !tx_byte[bit_idx];
                            phase <= 1;
                        end
                        1: begin scl_low <= 0; phase <= 2; end
                        2: phase <= 3;
                        3: begin
                            scl_low <= 1;
                            if (bit_idx == 0) phase <= 4;
                            else begin bit_idx <= bit_idx - 1'b1; phase <= 0; end
                        end
                        4: begin sda_low <= 0; phase <= 5; end
                        5: begin scl_low <= 0; phase <= 6; end
                        6: begin if (sda_sync) ack_error <= 1; phase <= 7; end
                        7: begin
                            scl_low <= 1;
                            step <= step + 1'b1;
                            bit_idx <= 7;
                            phase <= 0;
                        end
                    endcase
                    12, 13: case (phase) // READ byte + master ACK/NACK
                        0: begin scl_low <= 1; sda_low <= 0; phase <= 1; end
                        1: begin scl_low <= 0; phase <= 2; end
                        2: begin rx_byte[bit_idx] <= sda_sync; phase <= 3; end
                        3: begin
                            scl_low <= 1;
                            if (bit_idx == 0) phase <= 4;
                            else begin bit_idx <= bit_idx - 1'b1; phase <= 0; end
                        end
                        4: begin sda_low <= (step == 12); phase <= 5; end
                        5: begin scl_low <= 0; phase <= 6; end
                        6: phase <= 7;
                        7: begin
                            scl_low <= 1;
                            sda_low <= 0;
                            if (step == 12) partial[15:8] <= rx_byte;
                            else if (!ack_error) begin
                                sample <= {partial[15:8], rx_byte};
                                valid <= 1;
                            end
                            step <= step + 1'b1;
                            bit_idx <= 7;
                            phase <= 0;
                        end
                    endcase
                    5, 14: case (phase) // STOP
                        0: begin scl_low <= 1; sda_low <= 1; phase <= 1; end
                        1: begin scl_low <= 0; phase <= 2; end
                        2: begin
                            sda_low <= 0;
                            step <= step + 1'b1;
                            wait_ticks <= 0;
                            phase <= 0;
                        end
                    endcase
                    6, 15: begin // poll close to the ADS1115 860 SPS update rate
                        scl_low <= 0;
                        sda_low <= 0;
                        if (wait_ticks == 9'd399) begin
                            wait_ticks <= 0;
                            step <= 7;
                        end else wait_ticks <= wait_ticks + 1'b1;
                    end
                    default: step <= 0;
                endcase
            end else divider <= divider + 1'b1;
        end
    end
endmodule
