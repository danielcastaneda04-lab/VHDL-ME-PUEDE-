library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- hex7seg: convierte el angulo binario (0-180) en sus 3 digitos BCD
-- (centena, decena, unidad) e instancia bcd_7seg para decodificar
-- cada digito hacia su display de 7 segmentos.

entity hex7seg is
	port (
		ang_i    : in  std_logic_vector(7 downto 0); -- angulo binario, 0..180

		seg_uni  : out std_logic_vector(6 downto 0);
		seg_dec  : out std_logic_vector(6 downto 0);
		seg_cent : out std_logic_vector(6 downto 0)
	);
end hex7seg;

architecture behavioral of hex7seg is

	component bcd_7seg
		port (
			bcd_i : in  std_logic_vector(3 downto 0);
			seg_o : out std_logic_vector(6 downto 0)
		);
	end component;

	signal unidad  : std_logic_vector(3 downto 0);
	signal decena  : std_logic_vector(3 downto 0);
	signal centena : std_logic_vector(3 downto 0);

begin

	process (ang_i)
		variable ang_v     : integer range 0 to 255;
		variable centena_v : integer range 0 to 9;
		variable decena_v  : integer range 0 to 9;
		variable unidad_v  : integer range 0 to 9;
	begin
		ang_v := to_integer(unsigned(ang_i));

		-- division/modulo entero: totalmente combinacional, sin bucles
		centena_v := ang_v / 100;
		decena_v  := (ang_v mod 100) / 10;
		unidad_v  := ang_v mod 10;

		unidad  <= std_logic_vector(to_unsigned(unidad_v, 4));
		decena  <= std_logic_vector(to_unsigned(decena_v, 4));
		centena <= std_logic_vector(to_unsigned(centena_v, 4));
	end process;

	U_UNI  : bcd_7seg port map (bcd_i => unidad,  seg_o => seg_uni);
	U_DEC  : bcd_7seg port map (bcd_i => decena,  seg_o => seg_dec);
	U_CENT : bcd_7seg port map (bcd_i => centena, seg_o => seg_cent);

end architecture behavioral;