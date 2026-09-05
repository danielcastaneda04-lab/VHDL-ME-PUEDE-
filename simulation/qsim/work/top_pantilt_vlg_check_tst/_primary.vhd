library verilog;
use verilog.vl_types.all;
entity top_pantilt_vlg_check_tst is
    port(
        hex_a_o         : in     vl_logic_vector(6 downto 0);
        hex_b_o         : in     vl_logic_vector(6 downto 0);
        hex_c_o         : in     vl_logic_vector(6 downto 0);
        hex_sel_o       : in     vl_logic_vector(6 downto 0);
        servo_pan_o     : in     vl_logic;
        servo_til_o     : in     vl_logic;
        sampler_rx      : in     vl_logic
    );
end top_pantilt_vlg_check_tst;
