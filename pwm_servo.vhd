library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_servo is
	generic (
		F_CLK    : integer := 50_000_000;  -- Hz, reloj del sistema 
		F_TRAMA  : integer := 50;          -- Hz, refresco (50 Hz = 20 ms) 
		T_MIN_US : integer := 500;         -- us, ancho minimo (calibrar) 
		T_MAX_US : integer := 3000;        -- us, ancho maximo (calibrar) 
		T_INI_US : integer := 1500;        -- us, posicion de reposo 
		N_POS    : integer := 8;           -- bits de la consigna
		ANG_MAX  : integer := 180
	);
	port (
		clk   : in  std_logic; 
		rst   : in  std_logic; 
		pst   : in  std_logic_vector(N_POS-1 downto 0); 
		servo : out std_logic
	);
end pwm_servo;

architecture rtl of pwm_servo is
	constant C_US    : integer := F_CLK / 1_000_000;       -- ciclos por us 
	constant C_TRAMA : integer := F_CLK / F_TRAMA;         -- 1 000 000 
	constant C_MIN   : integer := C_US * T_MIN_US;         --    25 000 
	constant C_MAX   : integer := C_US * T_MAX_US;         --   125 000 
	constant C_INI   : integer := C_US * T_INI_US;         --    75 000 
	constant POS_MAX : integer := 2**N_POS - 1;            --       255 
	constant C_PASO  : integer := (C_MAX - C_MIN)/POS_MAX; --       392 
	  
	signal cnt   : integer range 0 to C_TRAMA-1 := 0; 
	signal ancho : integer range 0 to C_MAX     := C_INI;
		
begin

	process(clk)
	begin
			if rising_edge(clk) then
				if rst = '1' then
					cnt 	<=  0;
					ancho <= C_INI;
				elsif cnt = C_TRAMA-1 then 
					cnt   <= 0; -- el ancho se refresca UNA sola vez por trama 
					ancho <= C_MIN + to_integer(unsigned(pst)) * C_PASO; 
				else 
					cnt <= cnt + 1; 
				end if; 
			end if; 
	end process; 
	
	servo <= '0' when rst = '1' else 
				'1' when cnt < ancho else 
				'0';   
				
end architecture rtl; 

	
	
	
	
	
	
	
	
	
	
	