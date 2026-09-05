library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- top_pantilt: modulo principal.
-- Flujo:  UART -> UART_RX -> parser_cmd (interprete de comandos ASCII P/T/H/S/X/R)
--                                  |-> pan_angle_o  -> pwm_servo -> servo_pan_o
--                                  |-> tilt_angle_o -> pwm_servo -> servo_til_o
--                                  |-> disp_angle_o -> hex7seg -> bcd_7seg x3 -> displays numericos
--                                  '-> disp_mode_o  -> bcd_7seg -> display indicador (p/t/H/S/-)

entity top_pantilt is
	generic (
		F_CLK         : integer := 50_000_000; -- reloj de la FPGA (EP2C20F484C7)
		N_POS         : integer := 8;          -- ancho de las consignas de angulo
		PAN_MIN_DEG   : integer := 0;
		PAN_MAX_DEG   : integer := 180;
		TILT_MIN_DEG  : integer := 45;         -- limites de seguridad del eje tilt
		TILT_MAX_DEG  : integer := 135;
		HOME_DEG      : integer := 90;
		SWEEP_STEP_MS : integer := 30;
		CLKS_PER_BIT  : integer := 1302         -- cambie la división despues 
	);
	port (
		clk_i     : in  std_logic;
		rst_i     : in  std_logic;
		sel_i     : in  std_logic;
		uart_rx_i : in  std_logic;                     -- linea serie de entrada

		servo_pan_o : out std_logic;                   -- PWM servo pan
		servo_til_o : out std_logic;                   -- PWM servo tilt

		hex_a_o   : out std_logic_vector(6 downto 0);  -- display unidades
		hex_b_o   : out std_logic_vector(6 downto 0);  -- display decenas
		hex_c_o   : out std_logic_vector(6 downto 0);  -- display centenas
		hex_sel_o : out std_logic_vector(6 downto 0);   -- display indicador (p/t/H/S/-)
		led_o_o	 : out std_logic
		
	);
end top_pantilt;

architecture structural of top_pantilt is

	component UART_RX
		generic (
			g_CLKS_PER_BIT : integer := 1302
		);
		port (
			i_Clk       : in  std_logic;
			i_RX_Serial : in  std_logic;
			o_RX_DV     : out std_logic;
			o_RX_Byte   : out std_logic_vector(7 downto 0)
		);
	end component;

	component parser_cmd
		generic (
			N_POS         : integer := 8;
			F_CLK         : integer := 50_000_000;
			PAN_MIN_DEG   : integer := 0;
			PAN_MAX_DEG   : integer := 180;
			TILT_MIN_DEG  : integer := 45;
			TILT_MAX_DEG  : integer := 135;
			HOME_DEG      : integer := 90;
			SWEEP_STEP_MS : integer := 30
		);
		port (
			clk          : in  std_logic;
			rst          : in  std_logic;
			rx_dv_i      : in  std_logic;
			rx_byte_i    : in  std_logic_vector(7 downto 0);
			sel			 : in  std_logic;
			pan_angle_o  : out std_logic_vector(N_POS-1 downto 0);
			tilt_angle_o : out std_logic_vector(N_POS-1 downto 0);
			disp_angle_o : out std_logic_vector(N_POS-1 downto 0);
			disp_mode_o  : out std_logic_vector(3 downto 0);
			led_o			 : out std_logic
		);
	end component;

	component pwm_servo
		generic (
			F_CLK    : integer := 50_000_000;
			F_TRAMA  : integer := 50;
			T_MIN_US : integer := 500;
			T_MAX_US : integer := 3000;
			T_INI_US : integer := 1500;
			N_POS    : integer := 8;
			ANG_MAX  : integer := 180
		);
		port (
			clk   : in  std_logic;
			rst   : in  std_logic;
			pst   : in  std_logic_vector(N_POS-1 downto 0);
			servo : out std_logic
		);
	end component;

	component hex7seg
		port (
			ang_i    : in  std_logic_vector(7 downto 0);
			seg_uni  : out std_logic_vector(6 downto 0);
			seg_dec  : out std_logic_vector(6 downto 0);
			seg_cent : out std_logic_vector(6 downto 0)
		);
	end component;

	component bcd_7seg
		port (
			bcd_i : in  std_logic_vector(3 downto 0);
			seg_o : out std_logic_vector(6 downto 0)
		);
	end component;

	signal rx_dv   : std_logic;
	signal rx_byte : std_logic_vector(7 downto 0);

	signal pan_angle  : std_logic_vector(N_POS-1 downto 0);
	signal tilt_angle : std_logic_vector(N_POS-1 downto 0);
	signal disp_angle : std_logic_vector(N_POS-1 downto 0);
	signal disp_mode  : std_logic_vector(3 downto 0);

begin

	-- Recepcion UART: 8N1 (8 datos, sin paridad, 1 bit de parada)
	U_UART : UART_RX
		generic map (
			g_CLKS_PER_BIT => CLKS_PER_BIT
		)
		port map (
			i_Clk       => clk_i,
			i_RX_Serial => uart_rx_i,
			o_RX_DV     => rx_dv,
			o_RX_Byte   => rx_byte
		);

	-- Interprete de comandos ASCII (P/T/H/S/X/R)
	U_PARSER : parser_cmd
		generic map (
			N_POS         => N_POS,
			F_CLK         => F_CLK,
			PAN_MIN_DEG   => PAN_MIN_DEG,
			PAN_MAX_DEG   => PAN_MAX_DEG,
			TILT_MIN_DEG  => TILT_MIN_DEG,
			TILT_MAX_DEG  => TILT_MAX_DEG,
			HOME_DEG      => HOME_DEG,
			SWEEP_STEP_MS => SWEEP_STEP_MS
		)
		port map (
			clk          => clk_i,
			rst          => rst_i,
			rx_dv_i      => rx_dv,
			rx_byte_i    => rx_byte,
			sel 			 => sel_i,
			pan_angle_o  => pan_angle,
			tilt_angle_o => tilt_angle,
			disp_angle_o => disp_angle,
			disp_mode_o  => disp_mode,
			led_o 		 => led_o_o
		);

	-- Generacion de PWM, un modulo por servomotor
	U_PWM_PAN : pwm_servo
		generic map (
			F_CLK   => F_CLK,
			N_POS   => N_POS,
			ANG_MAX => PAN_MAX_DEG
		)
		port map (
			clk   => clk_i,
			rst   => rst_i,
			pst   => pan_angle,
			servo => servo_pan_o
		);

	U_PWM_TIL : pwm_servo
		generic map (
			F_CLK   => F_CLK,
			N_POS   => N_POS,
			ANG_MAX => PAN_MAX_DEG  -- misma escala fisica 0..180; el tilt solo se satura a un subrango
		)
		port map (
			clk   => clk_i,
			rst   => rst_i,
			pst   => tilt_angle,
			servo => servo_til_o
		);

	-- Visualizacion del angulo activo (3 digitos)
	U_HEX : hex7seg
		port map (
			ang_i    => disp_angle,
			seg_uni  => hex_a_o,
			seg_dec  => hex_b_o,
			seg_cent => hex_c_o
		);

	-- Indicador de estado / eje activo ('p','t','H','S','-')
	U_SEL : bcd_7seg
		port map (
			bcd_i => disp_mode,
			seg_o => hex_sel_o
		);

end architecture structural;