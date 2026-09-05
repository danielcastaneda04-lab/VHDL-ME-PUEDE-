library verilog;
use verilog.vl_types.all;
entity top_pantilt is
    port(
        clk_i           : in     vl_logic;
        rst_i           : in     vl_logic;
        uart_rx_i       : in     vl_logic;
        servo_pan_o     : out    vl_logic;
        servo_til_o     : out    vl_logic;
        hex_a_o         : out    vl_logic_vector(6 downto 0);
        hex_b_o         : out    vl_logic_vector(6 downto 0);
        hex_c_o         : out    vl_logic_vector(6 downto 0);
        hex_sel_o       : out    vl_logic_vector(6 downto 0)
    );
end top_pantilt;
