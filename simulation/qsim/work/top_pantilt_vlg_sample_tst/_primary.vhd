library verilog;
use verilog.vl_types.all;
entity top_pantilt_vlg_sample_tst is
    port(
        clk_i           : in     vl_logic;
        rst_i           : in     vl_logic;
        uart_rx_i       : in     vl_logic;
        sampler_tx      : out    vl_logic
    );
end top_pantilt_vlg_sample_tst;
