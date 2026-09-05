library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--   P<ddd><CR>  Posicionar acimut (pan)  0..180
--   T<ddd><CR>  Posicionar elevacion (tilt), saturado a limites de seguridad
--   H<CR>       Reposo: ambos ejes a 090
--   S<CR>       Barrido automatico del eje pan hasta recibir otro comando
--   X<CR>       Parada: congela ambos ejes e ignora comandos siguientes
--   R<CR>       Rearme: sale de Parada y vuelve a admitir comandos
--
-- Tabla 3 (visualizacion): el valor mostrado en los displays corresponde
-- SIEMPRE a la posicion real ordenada al servo (p_disp_angle / t_disp_angle),
-- nunca al dato crudo recibido por el puerto serie. SW[0] (sel) elige el eje:
--   sel='0' -> HEX3 = 'P', HEX2-0 = angulo actual de pan
--   sel='1' -> HEX3 = 't', HEX2-0 = angulo actual de tilt

entity parser_cmd is
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
		clk       : in  std_logic;
		rst       : in  std_logic;
		rx_dv_i   : in  std_logic;
		rx_byte_i : in  std_logic_vector(7 downto 0);
		sel       : in  std_logic;  -- SW[0]: '0'=mostrar pan, '1'=mostrar tilt

		pan_angle_o  : out std_logic_vector(N_POS-1 downto 0);
		tilt_angle_o : out std_logic_vector(N_POS-1 downto 0);

		disp_angle_o : out std_logic_vector(N_POS-1 downto 0);
		disp_mode_o  : out std_logic_vector(3 downto 0);
		led_o        : out std_logic
	);
end parser_cmd;

architecture rtl of parser_cmd is

	constant C_CR   : std_logic_vector(7 downto 0) := x"0D";
	constant C_P_U  : std_logic_vector(7 downto 0) := x"50";
	constant C_P_L  : std_logic_vector(7 downto 0) := x"70";
	constant C_T_U  : std_logic_vector(7 downto 0) := x"54";
	constant C_T_L  : std_logic_vector(7 downto 0) := x"74";
	constant C_H_U  : std_logic_vector(7 downto 0) := x"48";
	constant C_H_L  : std_logic_vector(7 downto 0) := x"68";
	constant C_S_U  : std_logic_vector(7 downto 0) := x"53";
	constant C_S_L  : std_logic_vector(7 downto 0) := x"73";
	constant C_X_U  : std_logic_vector(7 downto 0) := x"58";
	constant C_X_L  : std_logic_vector(7 downto 0) := x"78";
	constant C_R_U  : std_logic_vector(7 downto 0) := x"52";
	constant C_R_L  : std_logic_vector(7 downto 0) := x"72";

	-- Tabla 3: solo se necesitan los codigos 'P' y 't' para el display indicador
	constant D_PAN  : std_logic_vector(3 downto 0) := "1010"; -- 'P'
	constant D_TILT : std_logic_vector(3 downto 0) := "1011"; -- 't'

	type t_fsm  is (S_WAIT, S_DIGIT1, S_DIGIT2, S_DIGIT3, S_WAIT_CR);
	type t_mode is (M_NORMAL, M_SWEEP, M_STOPPED);

	signal r_fsm      : t_fsm  := S_WAIT;
	signal r_mode     : t_mode := M_NORMAL;
	signal r_cmd_char : std_logic_vector(7 downto 0) := (others => '0');

	signal r_d1, r_d2, r_d3 : integer range 0 to 9 := 0;

	-- consignas reales enviadas al PWM
	signal r_pan  : unsigned(N_POS-1 downto 0) := to_unsigned(HOME_DEG, N_POS);
	signal r_tilt : unsigned(N_POS-1 downto 0) := to_unsigned(HOME_DEG, N_POS);

	-- valores mostrados en los displays: SIEMPRE reflejan la posicion real
	-- ordenada a cada eje (no el dato crudo recibido por UART)
	signal p_disp_angle : unsigned(N_POS-1 downto 0) := to_unsigned(HOME_DEG, N_POS);
	signal t_disp_angle : unsigned(N_POS-1 downto 0) := to_unsigned(HOME_DEG, N_POS);

	signal rx_dv_d : std_logic := '0';

	constant C_SWEEP_TICKS : integer := (F_CLK/1000) * SWEEP_STEP_MS;
	signal r_sweep_cnt : integer range 0 to C_SWEEP_TICKS-1 := 0;
	signal r_sweep_dir : std_logic := '1';

	function is_digit(b : std_logic_vector(7 downto 0)) return boolean is
	begin
		return (b >= x"30") and (b <= x"39");
	end function;

	function ascii2int(b : std_logic_vector(7 downto 0)) return integer is
	begin
		return to_integer(unsigned(b)) - 48;
	end function;

begin

	-- Proceso sincrono unico: framer ASCII + ejecucion de comandos + barrido.
	process(clk)
		variable v_val        : integer range 0 to 999;
		variable v_byte_event : boolean;
	begin
		if rising_edge(clk) then

			if rst = '1' then
				r_fsm        <= S_WAIT;
				r_mode       <= M_NORMAL;
				r_pan        <= to_unsigned(HOME_DEG, N_POS);
				r_tilt       <= to_unsigned(HOME_DEG, N_POS);
				p_disp_angle <= to_unsigned(HOME_DEG, N_POS);
				t_disp_angle <= to_unsigned(HOME_DEG, N_POS);
				r_sweep_cnt  <= 0;
				r_sweep_dir  <= '1';
				rx_dv_d      <= '0';
				led_o        <= '0';

			else
				rx_dv_d <= rx_dv_i;
				v_byte_event := (rx_dv_i = '1') and (rx_dv_d = '0');

				if v_byte_event then
					-------------------------------------------------------------
					-- Maquina de estados del framer ASCII
					-------------------------------------------------------------
					case r_fsm is

						when S_WAIT =>
							if (rx_byte_i = C_P_U) or (rx_byte_i = C_P_L) then
								r_cmd_char <= C_P_U;
								r_fsm      <= S_DIGIT1;
								led_o      <= '0';
							elsif (rx_byte_i = C_T_U) or (rx_byte_i = C_T_L) then
								r_cmd_char <= C_T_U;
								r_fsm      <= S_DIGIT1;
								led_o      <= '0';
							elsif (rx_byte_i = C_H_U) or (rx_byte_i = C_H_L) or
							      (rx_byte_i = C_S_U) or (rx_byte_i = C_S_L) or
							      (rx_byte_i = C_X_U) or (rx_byte_i = C_X_L) or
							      (rx_byte_i = C_R_U) or (rx_byte_i = C_R_L) then
								if (rx_byte_i = C_H_U) or (rx_byte_i = C_H_L) then
									r_cmd_char <= C_H_U;
								elsif (rx_byte_i = C_S_U) or (rx_byte_i = C_S_L) then
									r_cmd_char <= C_S_U;
								elsif (rx_byte_i = C_X_U) or (rx_byte_i = C_X_L) then
									r_cmd_char <= C_X_U;
								else
									r_cmd_char <= C_R_U;
								end if;
								r_fsm <= S_WAIT_CR;
								led_o <= '0';
							else
								r_fsm <= S_WAIT; -- caracter desconocido, se ignora
								led_o <= '1';
							end if;

						when S_DIGIT1 =>
							if is_digit(rx_byte_i) then
								r_d1  <= ascii2int(rx_byte_i);
								r_fsm <= S_DIGIT2;
								led_o <= '0';
							else
								r_fsm <= S_WAIT;
								led_o <= '1';
							end if;

						when S_DIGIT2 =>
							if is_digit(rx_byte_i) then
								r_d2  <= ascii2int(rx_byte_i);
								r_fsm <= S_DIGIT3;
								led_o <= '0';
							else
								r_fsm <= S_WAIT;
								led_o <= '1';
							end if;

						when S_DIGIT3 =>
							if is_digit(rx_byte_i) then
								r_d3  <= ascii2int(rx_byte_i);
								r_fsm <= S_WAIT_CR;
								led_o <= '0';
							else
								r_fsm <= S_WAIT;
								led_o <= '1';
							end if;

						when S_WAIT_CR =>
							r_fsm <= S_WAIT;

							if rx_byte_i = C_CR then
								case r_cmd_char is

									when C_P_U => -- Posicionar acimut (pan)
										if r_mode /= M_STOPPED then
											v_val := r_d1*100 + r_d2*10 + r_d3;
											if (v_val > PAN_MAX_DEG) or (v_val < PAN_MIN_DEG) then
												led_o <= '1'; -- fuera de rango, se descarta
											else
												r_pan        <= to_unsigned(v_val, N_POS);
												p_disp_angle <= to_unsigned(v_val, N_POS);
												r_mode       <= M_NORMAL;
												led_o        <= '0';
											end if;
										else
											led_o <= '1'; -- ignorado por estar en PARADA
										end if;

									when C_T_U => -- Posicionar elevacion (tilt), limites de seguridad
										if r_mode /= M_STOPPED then
											v_val := r_d1*100 + r_d2*10 + r_d3;
											if (v_val > TILT_MAX_DEG) or (v_val < TILT_MIN_DEG) then
												led_o <= '1';
											else
												r_tilt       <= to_unsigned(v_val, N_POS);
												t_disp_angle <= to_unsigned(v_val, N_POS);
												r_mode       <= M_NORMAL;
												led_o        <= '0';
											end if;
										else
											led_o <= '1';
										end if;

									when C_H_U => -- Reposo: ambos ejes a HOME_DEG
										if r_mode /= M_STOPPED then
											r_pan        <= to_unsigned(HOME_DEG, N_POS);
											r_tilt       <= to_unsigned(HOME_DEG, N_POS);
											p_disp_angle <= to_unsigned(HOME_DEG, N_POS);
											t_disp_angle <= to_unsigned(HOME_DEG, N_POS);
											r_mode       <= M_NORMAL;
											led_o        <= '0';
										else
											led_o <= '1';
										end if;

									when C_S_U => -- Barrido automatico de pan
										if r_mode /= M_STOPPED then
											r_mode      <= M_SWEEP;
											r_sweep_cnt <= 0;
											led_o       <= '0';
											-- p_disp_angle se sigue actualizando en cada paso
											-- del generador de barrido, mas abajo.
										else
											led_o <= '1';
										end if;

									when C_X_U => -- Parada: congela ambos ejes
										r_mode <= M_STOPPED;
										led_o  <= '0';

									when C_R_U => -- Rearme
										if r_mode = M_STOPPED then
											r_mode <= M_NORMAL;
										end if;
										led_o <= '0';

									when others =>
										led_o <= '1';

								end case;
							else
								led_o <= '1'; -- trama malformada (no llego <CR>)
							end if;

					end case;

				elsif r_mode = M_SWEEP then
					-------------------------------------------------------------
					-- Generador de barrido: rebota el pan entre PAN_MIN_DEG y PAN_MAX_DEG
					-------------------------------------------------------------
					if r_sweep_cnt = C_SWEEP_TICKS-1 then
						r_sweep_cnt <= 0;

						if r_sweep_dir = '1' then
							if r_pan >= to_unsigned(PAN_MAX_DEG, N_POS) then
								r_sweep_dir <= '0';
								r_pan       <= r_pan - 1;
								p_disp_angle<= r_pan - 1;
							else
								r_pan        <= r_pan + 1;
								p_disp_angle <= r_pan + 1;
							end if;
						else
							if r_pan <= to_unsigned(PAN_MIN_DEG, N_POS) then
								r_sweep_dir <= '1';
								r_pan       <= r_pan + 1;
								p_disp_angle<= r_pan + 1;
							else
								r_pan        <= r_pan - 1;
								p_disp_angle <= r_pan - 1;
							end if;
						end if;
					else
						r_sweep_cnt <= r_sweep_cnt + 1;
					end if;
				end if;

			end if;
		end if;
	end process;

	-- Mux de visualizacion (SW[0] = sel): puramente combinacional,
	-- fuera del proceso sincrono para evitar un ciclo extra de retardo.
	disp_angle_o <= std_logic_vector(p_disp_angle) when sel = '0' else std_logic_vector(t_disp_angle);
	disp_mode_o  <= D_PAN                          when sel = '0' else D_TILT;

	pan_angle_o  <= std_logic_vector(r_pan);
	tilt_angle_o <= std_logic_vector(r_tilt);

end architecture rtl;