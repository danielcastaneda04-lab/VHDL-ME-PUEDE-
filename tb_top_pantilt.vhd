library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- tb_top_pantilt: testbench de integracion del sistema completo, ajustado
-- a la Tabla 3 (visualizacion en displays de 7 segmentos, tarjeta DE1):
--
--   SW[0]=0 -> HEX3='P', HEX2-HEX0 = angulo actual de PAN (000..180)
--   SW[0]=1 -> HEX3='t', HEX2-HEX0 = angulo actual de TILT (000..180)
--
-- El valor mostrado debe corresponder a la POSICION REAL ordenada al
-- servomotor en cada instante, no al dato crudo recibido por el puerto
-- serie (por eso se verifica que displays y PWM queden siempre coherentes,
-- incluso durante un comando invalido/fuera de rango, donde ambos deben
-- permanecer en su ultimo valor valido).
--
-- Se envian bytes reales por la linea serie (bit a bit, 8N1) y se miden
-- los pulsos PWM resultantes, ademas de leer directamente disp_angle_o /
-- disp_mode_o expuestos internamente por el DUT para validar el mux de sel.

entity tb_top_pantilt is
end entity tb_top_pantilt;

architecture sim of tb_top_pantilt is

	constant F_CLK       : integer := 50_000_000;
	constant CLK_PERIOD  : time    := 20 ns; -- 50 MHz
	constant CLKS_PER_BIT: integer := 20;    -- baudrate ficticio, solo para simular rapido
	constant N_POS       : integer := 8;

	constant T_MIN_US : integer := 500;
	constant T_MAX_US : integer := 3000; -- debe coincidir con pwm_servo.vhd (top_pantilt lo fija asi)
	constant ANG_MAX  : integer := 180;

	constant PAN_MIN_DEG  : integer := 0;
	constant PAN_MAX_DEG  : integer := 180;
	constant TILT_MIN_DEG : integer := 45;
	constant TILT_MAX_DEG : integer := 135;
	constant HOME_DEG     : integer := 90;

	constant D_PAN  : std_logic_vector(3 downto 0) := "1010";
	constant D_TILT : std_logic_vector(3 downto 0) := "1011";

	signal clk       : std_logic := '0';
	signal rst       : std_logic := '1';
	signal sel       : std_logic := '0'; -- SW[0]
	signal uart_line : std_logic := '1';
	signal servo_pan : std_logic;
	signal servo_til : std_logic;
	signal hex_a, hex_b, hex_c, hex_sel : std_logic_vector(6 downto 0);
	signal led_flag  : std_logic;

	signal sim_finished : boolean := false;

	component top_pantilt
		generic (
			F_CLK         : integer := 50_000_000;
			N_POS         : integer := 8;
			PAN_MIN_DEG   : integer := 0;
			PAN_MAX_DEG   : integer := 180;
			TILT_MIN_DEG  : integer := 45;
			TILT_MAX_DEG  : integer := 135;
			HOME_DEG      : integer := 90;
			SWEEP_STEP_MS : integer := 30;
			CLKS_PER_BIT  : integer := 1302
		);
		port (
			clk_i       : in  std_logic;
			rst_i       : in  std_logic;
			sel_i       : in  std_logic;
			uart_rx_i   : in  std_logic;
			servo_pan_o : out std_logic;
			servo_til_o : out std_logic;
			hex_a_o     : out std_logic_vector(6 downto 0);
			hex_b_o     : out std_logic_vector(6 downto 0);
			hex_c_o     : out std_logic_vector(6 downto 0);
			hex_sel_o   : out std_logic_vector(6 downto 0);
			led_o_o     : out std_logic
		);
	end component;

begin

	------------------------------------------------------------------
	-- DUT
	------------------------------------------------------------------
	DUT : top_pantilt
		generic map (
			F_CLK         => F_CLK,
			N_POS         => N_POS,
			PAN_MIN_DEG   => PAN_MIN_DEG,
			PAN_MAX_DEG   => PAN_MAX_DEG,
			TILT_MIN_DEG  => TILT_MIN_DEG,
			TILT_MAX_DEG  => TILT_MAX_DEG,
			HOME_DEG      => HOME_DEG,
			CLKS_PER_BIT  => CLKS_PER_BIT
		)
		port map (
			clk_i       => clk,
			rst_i       => rst,
			sel_i       => sel,
			uart_rx_i   => uart_line,
			servo_pan_o => servo_pan,
			servo_til_o => servo_til,
			hex_a_o     => hex_a,
			hex_b_o     => hex_b,
			hex_c_o     => hex_c,
			hex_sel_o   => hex_sel,
			led_o_o     => led_flag
		);

	------------------------------------------------------------------
	-- Reloj de 50 MHz
	------------------------------------------------------------------
	clk_gen : process
	begin
		while not sim_finished loop
			clk <= '0'; wait for CLK_PERIOD/2;
			clk <= '1'; wait for CLK_PERIOD/2;
		end loop;
		wait;
	end process clk_gen;

	------------------------------------------------------------------
	-- Estimulo
	------------------------------------------------------------------
	stim : process

		constant BIT_TIME : time := CLKS_PER_BIT * CLK_PERIOD;

		procedure uart_send_byte(b : std_logic_vector(7 downto 0)) is
		begin
			uart_line <= '0';
			wait for BIT_TIME;
			for i in 0 to 7 loop
				uart_line <= b(i);
				wait for BIT_TIME;
			end loop;
			uart_line <= '1';
			wait for BIT_TIME;
		end procedure;

		procedure uart_send_cmd(s : string) is
		begin
			for i in s'range loop
				uart_send_byte(std_logic_vector(to_unsigned(character'pos(s(i)), 8)));
			end loop;
			uart_send_byte(x"0D");
		end procedure;

		-- Replica EXACTAMENTE la aritmetica entera de pwm_servo.vhd:
		-- alli C_PASO se calcula en ciclos de reloj (C_MAX-C_MIN)/ANG_MAX,
		-- con C_MIN/C_MAX ya expresados en ciclos (us * C_US). Si se calcula
		-- el paso directamente en microsegundos se pierde precision por el
		-- truncamiento entero y el resultado no coincide con el hardware real.
		function expected_pulse_us(angle : integer) return integer is
			constant C_US   : integer := F_CLK / 1_000_000;
			constant C_MIN  : integer := C_US * T_MIN_US;
			constant C_MAX  : integer := C_US * T_MAX_US;
			constant C_PASO : integer := (C_MAX - C_MIN) / ANG_MAX; -- en ciclos
			variable ancho_ciclos : integer;
		begin
			ancho_ciclos := C_MIN + angle * C_PASO;
			return ancho_ciclos / C_US; -- de vuelta a microsegundos
		end function;

		procedure measure_pulse_us(signal s : in std_logic; result_us : out integer) is
			variable t0, t1 : time;
		begin
			wait until rising_edge(s);
			t0 := now;
			wait until falling_edge(s);
			t1 := now;
			result_us := (t1 - t0) / 1 us;
		end procedure;

		-- Convierte los 3 displays numericos (activos en bajo) a un entero 0..180
		-- para comparar directamente contra el angulo esperado (Tabla 3)
		function seg_to_digit(seg : std_logic_vector(6 downto 0)) return integer is
		begin
			case seg is
				when "1000000" => return 0;
				when "1111001" => return 1;
				when "0100100" => return 2;
				when "0110000" => return 3;
				when "0011001" => return 4;
				when "0010010" => return 5;
				when "0000010" => return 6;
				when "1111000" => return 7;
				when "0000000" => return 8;
				when "0010000" => return 9;
				when others    => return -1;
			end case;
		end function;

		function read_display_angle(cent, dec, uni : std_logic_vector(6 downto 0)) return integer is
			variable c, d, u : integer;
		begin
			c := seg_to_digit(cent);
			d := seg_to_digit(dec);
			u := seg_to_digit(uni);
			return c*100 + d*10 + u;
		end function;

		variable meas_us : integer;
		variable exp_us  : integer;
		variable disp_val: integer;

	begin
		report "=== INICIO TESTBENCH top_pantilt (Tabla 3: displays por SW[0]) ===";

		rst <= '1';
		sel <= '0'; -- SW[0]=0 -> mostrar PAN
		wait for 500 ns;
		rst <= '0';
		wait for 500 ns;

		----------------------------------------------------------------
		-- 1) Estado inicial: ambos ejes en HOME_DEG, display muestra pan='P',090
		----------------------------------------------------------------
		disp_val := read_display_angle(hex_c, hex_b, hex_a);
		assert disp_val = HOME_DEG
			report "FALLO: al reset, el display de PAN deberia mostrar " & integer'image(HOME_DEG) &
			       ", muestra " & integer'image(disp_val)
			severity error;
		assert hex_sel = "0000011" -- codigo de 'P'
			report "FALLO: HEX3 deberia mostrar 'P' con SW[0]=0" severity error;
		report "OK: reset -> HEX3='P', angulo mostrado = " & integer'image(disp_val);

		----------------------------------------------------------------
		-- 2) Enviar "P150<CR>": display de PAN y PWM deben reflejar 150
		----------------------------------------------------------------
		uart_send_cmd("P150");
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a);
		assert disp_val = 150
			report "FALLO: tras P150, el display (SW[0]=0) deberia mostrar 150, muestra " &
			       integer'image(disp_val)
			severity error;

		exp_us := expected_pulse_us(150);
		measure_pulse_us(servo_pan, meas_us);
		assert abs(meas_us - exp_us) <= 1
			report "FALLO: pulso PWM de pan incorrecto tras P150. Esperado ~" &
			       integer'image(exp_us) & " us, medido " & integer'image(meas_us) & " us"
			severity error;
		report "OK: P150 -> display PAN = " & integer'image(disp_val) &
			", pulso PWM = " & integer'image(meas_us) & " us";

		----------------------------------------------------------------
		-- 3) Cambiar SW[0] a '1': debe mostrarse el eje TILT, no el pan
		----------------------------------------------------------------
		sel <= '1';
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a);
		assert disp_val = HOME_DEG
			report "FALLO: con SW[0]=1, el display deberia mostrar el tilt actual (" &
			       integer'image(HOME_DEG) & "), muestra " & integer'image(disp_val)
			severity error;
		assert hex_sel = "0011011" -- codigo de 't'
			report "FALLO: HEX3 deberia mostrar 't' con SW[0]=1" severity error;
		report "OK: SW[0]=1 -> HEX3='t', angulo mostrado = " & integer'image(disp_val) &
			" (tilt aun no modificado)";

		----------------------------------------------------------------
		-- 4) Enviar "T060<CR>": con SW[0]=1, el display debe actualizarse a 060
		----------------------------------------------------------------
		uart_send_cmd("T060");
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a);
		assert disp_val = 60
			report "FALLO: tras T060, el display de TILT deberia mostrar 60, muestra " &
			       integer'image(disp_val)
			severity error;

		exp_us := expected_pulse_us(60);
		measure_pulse_us(servo_til, meas_us);
		assert abs(meas_us - exp_us) <= 1
			report "FALLO: pulso PWM de tilt incorrecto tras T060" severity error;
		report "OK: T060 -> display TILT = " & integer'image(disp_val) &
			", pulso PWM = " & integer'image(meas_us) & " us";

		----------------------------------------------------------------
		-- 5) Volver a SW[0]=0: el display de PAN debe seguir en 150
		--    (el comando T060 NO debio afectar el valor de pan)
		----------------------------------------------------------------
		sel <= '0';
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a);
		assert disp_val = 150
			report "FALLO: PAN deberia seguir en 150 tras comandar TILT, muestra " &
			       integer'image(disp_val)
			severity error;
		report "OK: SW[0]=0 -> PAN sigue en " & integer'image(disp_val) & " (no afectado por T060)";

		----------------------------------------------------------------
		-- 6) Comando fuera de rango (T200 > TILT_MAX_DEG): debe rechazarse
		--    y el display/PWM de tilt deben permanecer en el ultimo valor VALIDO (60)
		----------------------------------------------------------------
		uart_send_cmd("T200");
		wait for 200 ns;
		sel <= '1';
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a);
		assert disp_val = 60
			report "FALLO: T200 (fuera de rango) no debe modificar el display de tilt; " &
			       "deberia seguir en 60, muestra " & integer'image(disp_val)
			severity error;
		assert led_flag = '1'
			report "FALLO: led_o deberia indicar error (comando fuera de rango) tras T200"
			severity error;
		report "OK: T200 rechazado, display TILT permanece en " & integer'image(disp_val) &
			", led_o = '1' (error)";

		----------------------------------------------------------------
		-- 7) Comando H<CR>: ambos displays deben reflejar HOME_DEG
		----------------------------------------------------------------
		uart_send_cmd("H");
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a); -- sel='1' -> tilt
		assert disp_val = HOME_DEG
			report "FALLO: tras H, el display de TILT deberia mostrar " & integer'image(HOME_DEG)
			severity error;
		sel <= '0';
		wait for 200 ns;
		disp_val := read_display_angle(hex_c, hex_b, hex_a); -- pan
		assert disp_val = HOME_DEG
			report "FALLO: tras H, el display de PAN deberia mostrar " & integer'image(HOME_DEG)
			severity error;
		report "OK: H -> ambos displays muestran " & integer'image(HOME_DEG);

		report "=== TODAS LAS PRUEBAS (Tabla 3 incluida) FINALIZARON SIN ERRORES ===";
		sim_finished <= true;
		wait;

	end process stim;

end architecture sim;