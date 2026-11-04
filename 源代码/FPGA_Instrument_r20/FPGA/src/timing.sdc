create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
set_false_path -from [get_ports {rst_n}]
# UART is asynchronous; only the first sampling register is exempted.
set_false_path -to [get_regs {screen_input/rx_meta_s0 display_link/rx_meta_s0}]
# phase_index is loaded at output_tick, then WAIT (state 4) precedes the
# first coefficient capture (state 1): E0 -> E2. It remains stable for all
# 64 taps. Only this phase launch is multicycle; tap/data/MAC remain 1-cycle.
set_multicycle_path 2 -setup -from [get_regs {converter/phase_index*}]
set_multicycle_path 1 -hold -from [get_regs {converter/phase_index*}]
create_generated_clock -name usb_clk -source [get_ports {sys_clk}] -multiply_by 6 -divide_by 5 [get_pins {usb_clock/pll/CLKOUT0}]
# Exempt only the first request/acknowledge synchronizer stages.
set_false_path -to [get_regs {state_bridge/request_sync_0_s0 state_bridge/acknowledge_sync_0_s0}]
# Source payload remains stable throughout the acknowledged transfer.
set_max_delay -from [get_regs {state_bridge/payload_*_s0}] -to [get_regs {state_bridge/dst_state_*_s0}] 20
set_min_delay -from [get_regs {state_bridge/payload_*_s0}] -to [get_regs {state_bridge/dst_state_*_s0}] 0

set_false_path -to [get_regs {adc/sda_meta_s0}]
