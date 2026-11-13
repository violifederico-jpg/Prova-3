library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity generic_register_file is
    Generic (
        DATA_WIDTH : integer := 32;   -- Larghezza del dato in bit (es. 32)
        ADDR_WIDTH : integer := 4     -- 4 bit di indirizzo = 2^4 = 16 registri
    );
    Port (
        clk      : in  STD_LOGIC;                      -- Clock di sistema
        rst_n    : in  STD_LOGIC;                      -- Reset asincrono attivo basso
        wr_en    : in  STD_LOGIC;                      -- Abilitazione scrittura ('1' = Scrivi)
        addr     : in  STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0); -- Indirizzo (3 downto 0 per 16 registri)
        data_in  : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);  -- Dato da scrivere
        data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0)   -- Dato letto
    );
end entity generic_register_file;

architecture Behavioral of generic_register_file is

    -- Calcolo automatico del numero totale di registri (16)
    constant NUM_REGS : integer := 2**ADDR_WIDTH;

    -- Definizione dell'array per contenere i 16 registri
    type reg_array_t is array (0 to NUM_REGS - 1) of STD_LOGIC_VECTOR(DATA_WIDTH - 1 downto 0);
    
    signal regs : reg_array_t;

begin

    -- Processo sincrono per la scrittura
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            regs <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if wr_en = '1' then
                regs(to_integer(unsigned(addr))) <= data_in;
            end if;
        end if;
    end process;

    -- Lettura combinatoria asincrona
    data_out <= regs(to_integer(unsigned(addr)));

end architecture Behavioral;