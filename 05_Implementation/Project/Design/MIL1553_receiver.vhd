library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mil1553_rx is
    Port (
        clk          : in  STD_LOGIC;                      -- Clock di sistema a 16 MHz
        rst          : in  STD_LOGIC;                      -- Reset sincrono attivo alto
        rx_p         : in  STD_LOGIC;                      -- Ingresso differenziale positivo (dal transceiver)
        rx_n         : in  STD_LOGIC;                      -- Ingresso differenziale negativo (dal transceiver)
        data_out     : out STD_LOGIC_VECTOR(15 downto 0);  -- Parola dati ricevuta (16 bit)
        is_cmd_stat  : out STD_LOGIC;                      -- '1' = Command/Status, '0' = Data
        data_valid   : out STD_LOGIC;                      -- Impulso di 1 ciclo quando la parola è valida
        parity_error : out STD_LOGIC                       -- '1' se rilevato errore di parità
    );
end mil1553_rx;

architecture Behavioral of mil1553_rx is

    -- Costanti temporali basate su clock a 16 MHz (1 bit = 16 cicli = 1 us)
    constant HALF_BIT_CYCLES : integer := 8;  -- 0.5 us
    constant FULL_BIT_CYCLES : integer := 16; -- 1.0 us
    constant SYNC_HALF_MIN   : integer := 20; -- 1.25 us (tolleranza per 1.5 us = 24 cicli)
    constant SYNC_HALF_MAX   : integer := 28; -- 1.75 us

    -- Stati della Macchina a Stati Finiti (FSM)
    type state_type is (IDLE, SYNC_FIRST_HALF, SYNC_SECOND_HALF, RECEIVE_BITS, CHECK_PARITY);
    signal state : state_type := IDLE;

    -- Segnali per sincronizzazione e filtro di ingresso
    signal rx_sync      : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal rx_clean     : STD_LOGIC := '0';
    signal rx_prev      : STD_LOGIC := '0';
    signal edge_detect  : STD_LOGIC := '0';

    -- Contatori e registri interni
    signal timer        : integer range 0 to 63 := 0;
    signal bit_cnt      : integer range 0 to 17 := 0;
    signal shift_reg    : STD_LOGIC_VECTOR(16 downto 0) := (others => '0'); -- 16 bit dati + 1 parità
    signal sync_type    : STD_LOGIC := '0';
    signal first_half   : STD_LOGIC := '0';

begin

    -- 1. Sincronizzatore a 3 stadi e filtro anti-glitch per evitare metastabilità
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rx_sync  <= (others => '0');
                rx_clean <= '0';
                rx_prev  <= '0';
            else
                -- Consideriamo bus attivo solo se rx_p e rx_n sono complementari
                if (rx_p /= rx_n) then
                    rx_sync <= rx_sync(1 downto 0) & rx_p;
                else
                    rx_sync <= rx_sync(1 downto 0) & '0'; -- Bus in stato di idle/alta impedenza
                end if;

                -- Voto a maggioranza sui 3 campioni
                rx_clean <= (rx_sync(2) and rx_sync(1)) or 
                            (rx_sync(2) and rx_sync(0)) or 
                            (rx_sync(1) and rx_sync(0));
                
                rx_prev <= rx_clean;
            end if;
        end if;
    end process;

    -- Rilevamento fronti (sia salita che discesa)
    edge_detect <= rx_clean xor rx_prev;

    -- 2. Macchina a stati principale per decodifica Sync e Manchester II
    process(clk)
        variable parity_calc : STD_LOGIC;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                timer        <= 0;
                bit_cnt      <= 0;
                shift_reg    <= (others => '0');
                data_out     <= (others => '0');
                is_cmd_stat  <= '0';
                data_valid   <= '0';
                parity_error <= '0';
            else
                -- Default per segnali impulsivi
                data_valid <= '0';

                case state is
                    -- Attesa di un fronte di inizio trasmissione
                    when IDLE =>
                        parity_error <= '0';
                        if edge_detect = '1' then
                            timer     <= 1;
                            sync_type <= rx_clean; -- '1' = Cmd/Status, '0' = Data
                            state     <= SYNC_FIRST_HALF;
                        end if;

                    -- Misura della prima metà del Sync (deve durare ~1.5 us = 24 cicli)
                    when SYNC_FIRST_HALF =>
                        if edge_detect = '1' then
                            if (timer >= SYNC_HALF_MIN) and (timer <= SYNC_HALF_MAX) then
                                timer <= 1;
                                state <= SYNC_SECOND_HALF;
                            else
                                -- Durata non valida: falso allarme o rumore
                                state <= IDLE;
                            end if;
                        else
                            if timer < 63 then
                                timer <= timer + 1;
                            else
                                state <= IDLE; -- Timeout
                            end if;
                        end if;

                    -- Misura della seconda metà del Sync (~1.5 us)
                    -- Nota: Se il primo bit di dati inizia con lo stesso livello della seconda metà
                    -- del sync, non ci sarà un fronte a 1.5 us ma a 2.0 us (1.5 us sync + 0.5 us bit).
                    when SYNC_SECOND_HALF =>
                        if edge_detect = '1' then
                            -- Caso A: Fronte esattamente a 1.5 us (il primo bit è opposto al sync)
                            if (timer >= SYNC_HALF_MIN) and (timer <= SYNC_HALF_MAX) then
                                timer   <= 1;
                                bit_cnt <= 0;
                                state   <= RECEIVE_BITS;
                            -- Caso B: Fronte a 2.0 us (il primo bit continua il livello del sync per 0.5 us)
                            elsif (timer >= (SYNC_HALF_MIN + 8)) and (timer <= (SYNC_HALF_MAX + 8)) then
                                -- Abbiamo già superato la prima metà del bit 0!
                                first_half <= not sync_type;
                                timer      <= 9; -- Siamo già al centro della seconda metà
                                bit_cnt    <= 0;
                                state      <= RECEIVE_BITS;
                            else
                                state <= IDLE;
                            end if;
                        else
                            if timer < 63 then
                                timer <= timer + 1;
                            else
                                state <= IDLE;
                            end if;
                        end if;

                    -- Ricezione dei 16 bit di dati + 1 bit di parità (17 bit totali)
                    when RECEIVE_BITS =>
                        -- Campionamento a 1/4 di bit (ciclo 4) per la prima metà
                        if timer = 4 then
                            first_half <= rx_clean;
                        end if;

                        -- Campionamento a 3/4 di bit (ciclo 12) per la seconda metà e decodifica Manchester
                        if timer = 12 then
                            -- In Manchester II: 
                            -- Transizione Alto -> Basso = '1'
                            -- Transizione Basso -> Alto = '0'
                            if (first_half = '1') and (rx_clean = '0') then
                                shift_reg <= shift_reg(15 downto 0) & '1';
                            elsif (first_half = '0') and (rx_clean = '1') then
                                shift_reg <= shift_reg(15 downto 0) & '0';
                            else
                                -- Errore di codifica Manchester (mancata transizione a metà bit)
                                state <= IDLE;
                            end if;
                        end if;

                        -- Gestione fine bit (16 cicli) e risincronizzazione sul fronte centrale
                        if (edge_detect = '1') and (timer >= 6) and (timer <= 10) then
                            -- Risincronizza il timer al centro esatto del bit (ciclo 8) per compensare il drift
                            timer <= 8;
                        elsif timer = FULL_BIT_CYCLES then
                            timer <= 1;
                            if bit_cnt = 16 then
                                state <= CHECK_PARITY;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            timer <= timer + 1;
                        end if;

                    -- Verifica della parità dispari (Odd Parity)
                    when CHECK_PARITY =>
                        parity_calc := '1'; -- Partiamo da '1' per verificare parità dispari
                        for i in 1 to 16 loop
                            parity_calc := parity_calc xor shift_reg(i);
                        end loop;

                        data_out    <= shift_reg(16 downto 1);
                        is_cmd_stat <= sync_type;
                        data_valid  <= '1';

                        if parity_calc /= shift_reg(0) then
                            parity_error <= '1';
                        else
                            parity_error <= '0';
                        end if;

                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;