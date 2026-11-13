library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ram_1024x8 is
    port (
        clk  : in  std_logic;
        we   : in  std_logic;
        addr : in  std_logic_vector(9 downto 0);  -- 1024 locazioni
        din  : in  std_logic_vector(7 downto 0);
        dout : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of ram_1024x8 is

    type ram_type is array (0 to 1023) of std_logic_vector(7 downto 0);
    signal ram : ram_type := (others => (others => '0'));

begin

    process(clk)
    begin
        if rising_edge(clk) then

            -- Scrittura
            if we = '1' then
                ram(to_integer(unsigned(addr))) <= din;
            end if;

            -- Lettura sincrona
            dout <= ram(to_integer(unsigned(addr)));

        end if;
    end process;

end architecture rtl;