// Pressure maps release hold duration, followed by the original natural envelope.
// Timeout/NACK clears retained notes. Physical keys are never muted by ADC failure.
module pressure_sustain32 #(
 parameter integer CLK_HZ=50000000,
 parameter integer TIMEOUT_MS=100,
 parameter integer FULL_SCALE=20000,
 parameter integer DEAD_ZONE=400,
 parameter integer MAX_HOLD_MS=8000
)(
 input wire clk,reset_n,tick_ms,clear,
 input wire [31:0] held,
 input wire [15:0] adc_sample,
 input wire adc_valid,adc_error,
 output wire [31:0] sustained,
 output reg [7:0] pressure,
 output wire sensor_ready
);
 reg [15:0] age;
 reg [15:0] countdown[0:31] /* synthesis syn_ramstyle="registers" */;
 reg [31:0] retained;
 reg scan_active;
 reg [4:0] scan_index;
 reg [31:0] scan_held;
 reg [15:0] scan_duration;
 wire sample_ok=!adc_sample[15];
 assign sensor_ready=age<TIMEOUT_MS && !adc_error;
 assign sustained=held|retained;
 integer i;
 // ADC updates are milliseconds apart. Spend 68 clocks on exact scaling
 // instead of placing two combinational dividers on the 50MHz path.
 reg [2:0] scale_state;
 reg [15:0] delta,duration;
 reg [7:0] scaled_pressure;
 reg [31:0] numerator,remainder,quotient;
 reg [5:0] bit_count;
 wire [31:0] divisor=scale_state==4 ? 32'd255 : FULL_SCALE-DEAD_ZONE;
 wire [32:0] trial={remainder,numerator[31]};
 wire take=trial>={1'b0,divisor};
 wire [32:0] difference=trial-{1'b0,divisor};
 wire [31:0] next_quotient={quotient[30:0],take};
 always @(posedge clk)begin
 if(!reset_n)begin
 age<=TIMEOUT_MS;pressure<=0;retained<=0;
 scan_active<=0;scan_index<=0;scan_held<=0;scan_duration<=0;
 scale_state<=0;delta<=0;duration<=0;scaled_pressure<=0;
 numerator<=0;remainder<=0;quotient<=0;bit_count<=0;
 for(i=0;i<32;i=i+1)countdown[i]<=0;
 end else begin
 if(adc_valid && !adc_error)begin
 age<=0;
 end else if(tick_ms && age<TIMEOUT_MS)age<=age+1'b1;
 if(adc_error || clear)begin scale_state<=0;pressure<=0;duration<=0;end
 else if(adc_valid)begin
 if(!sample_ok || adc_sample<=DEAD_ZONE)begin pressure<=0;duration<=0;scale_state<=0;end
 else if(adc_sample>=FULL_SCALE)begin pressure<=255;duration<=MAX_HOLD_MS;scale_state<=0;end
 else begin delta<=adc_sample-DEAD_ZONE;scale_state<=1;end
 end else case(scale_state)
 1:begin numerator<=delta*32'd255;remainder<=0;quotient<=0;bit_count<=0;scale_state<=2;end
 2,4:begin
 numerator<=numerator<<1;remainder<=take ? difference[31:0] : trial[31:0];
 quotient<=next_quotient;bit_count<=bit_count+1'b1;
 if(bit_count==31)begin
 if(scale_state==2)begin scaled_pressure<=next_quotient[7:0];scale_state<=3;end
 else begin pressure<=scaled_pressure;duration<=next_quotient[15:0];scale_state<=0;end
 end
 end
 3:begin numerator<=scaled_pressure*MAX_HOLD_MS;remainder<=0;quotient<=0;bit_count<=0;scale_state<=4;end
 default:scale_state<=0;
 endcase
 // One shared timer update per clock, all 32 slots within 640ns at 50MHz.
 // Physical held keys bypass this scan; each millisecond uses one snapshot.
 if(clear || !sensor_ready || pressure==0)begin retained<=0;scan_active<=0;end
 else if(tick_ms)begin
 scan_active<=1;scan_index<=0;scan_held<=held;scan_duration<=duration;
 end else if(scan_active)begin
 if(scan_held[scan_index])begin retained[scan_index]<=1;countdown[scan_index]<=0;end
 else if(retained[scan_index])begin
 if(countdown[scan_index]>=scan_duration)begin retained[scan_index]<=0;countdown[scan_index]<=0;end
 else countdown[scan_index]<=countdown[scan_index]+1'b1;
 end
 if(scan_index==31)scan_active<=0;else scan_index<=scan_index+1'b1;
 end
 end
 end
endmodule
