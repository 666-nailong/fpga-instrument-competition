`timescale 1ns/1ps
// ADS1115 I2C 从设备仿真模型：校验配置写入、ACK、转换数据读取和 valid 脉冲。
// tri1 模拟外部上拉；slave_low 用于模拟 ADC 将 SDA 拉低发送 ACK/数据。
module tb_ads1115;
    reg test_passed = 0;
    reg clk = 0, reset_n = 0;
    always #10 clk = !clk;
    tri1 scl, sda;
    reg slave_low = 0;
    assign sda = slave_low ? 1'b0 : 1'bz;
    wire [15:0] sample;
    wire valid, ack_error;
    ads1115_reader dut(clk, reset_n, scl, sda, sample, valid, ack_error);
    reg [7:0] received;
    reg got_valid = 0;
    integer i;
    always @(posedge clk) if (valid) got_valid <= 1;

    task check;
        input condition;
        input [255:0] message;
        begin
            if (condition !== 1'b1) $fatal(1, "FAIL: %0s at %0t", message, $time);
        end
    endtask
    task receive_byte;
        input [7:0] expected;
        begin
            received = 0;
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge scl); #1;
                received[i] = sda;
            end
            check(received == expected, "I2C address/pointer/config byte");
            @(negedge scl); slave_low = 1;
            @(posedge scl);
            @(negedge scl); slave_low = 0;
        end
    endtask
    task wait_start;
        begin : wait_for_start
            forever begin
                @(negedge sda);
                if (scl === 1'b1) disable wait_for_start;
            end
        end
    endtask
    task wait_stop;
        begin : wait_for_stop
            forever begin
                @(posedge sda);
                if (scl === 1'b1) disable wait_for_stop;
            end
        end
    endtask
    task send_byte;
        input [7:0] value;
        input expected_ack;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                slave_low = !value[i];
                @(posedge scl);
                if (i != 0) @(negedge scl);
            end
            @(negedge scl); slave_low = 0;
            @(posedge scl); #1;
            if (sda != !expected_ack)
                $display("ACK mismatch value=%h expected_ack=%b sda=%b step=%0d phase=%0d", value, expected_ack, sda, dut.step, dut.phase);
            check(sda == !expected_ack, "master ACK after high byte, NACK after low byte");
            @(negedge scl);
        end
    endtask
    initial begin
        repeat (5) @(negedge clk); reset_n = 1;
        wait_start();
        receive_byte(8'h90);
        receive_byte(8'h01);
        receive_byte(8'h42);
        receive_byte(8'he3);
        wait_stop();
        wait_start();
        receive_byte(8'h90);
        receive_byte(8'h00);
        wait_start();
        receive_byte(8'h91);
        send_byte(8'h12, 1);
        send_byte(8'h34, 0);
        wait_stop();
        check(got_valid && sample == 16'h1234 && !ack_error,
              "ADS1115 conversion value and valid pulse");
        got_valid=0;
        // Leave SDA released for the next read transaction: no slave ACKs.
        wait_start();wait_stop();
        repeat(200) @(negedge clk);
        check(!got_valid && ack_error && sample==16'h1234,"NACK keeps last sample without valid");
        reset_n=0;repeat(4) @(negedge clk);
        check(!valid && sample==0 && scl===1'b1 && sda===1'b1,"reset releases open-drain bus");
        test_passed = 1;
        $display("PASS: ADS1115 config, pointer, repeated START, ACK/NACK, 16-bit read, missing slave retains sample/no valid, reset releases bus");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "FAIL: ADS1115 transaction timeout");
    end
endmodule
