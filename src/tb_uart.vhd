library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_tb is
end UART_tb;

architecture sim of UART_tb is
  ------------------------------------------------------------------
  -- Componente UART (mesmo de antes)
  ------------------------------------------------------------------
  component UART
    Port (
      clk        : in  std_logic;
      reset      : in  std_logic;
      data_in    : in  std_logic_vector(7 downto 0);
      tx_start   : in  std_logic;
      tx_out     : out std_logic;
      busy       : out std_logic;
      rx_in      : in  std_logic;
      data_out   : out std_logic_vector(7 downto 0);
      data_valid : out std_logic
    );
  end component;

  -- Sinais de interligação
  signal clk_tb        : std_logic := '0';
  signal reset_tb      : std_logic := '0';
  signal data_in_tb    : std_logic_vector(7 downto 0) := (others=>'0');
  signal tx_start_tb   : std_logic := '0';
  signal tx_out_tb     : std_logic;
  signal busy_tb       : std_logic;
  signal rx_in_tb      : std_logic;
  signal data_out_tb   : std_logic_vector(7 downto 0);
  signal data_valid_tb : std_logic;

  ------------------------------------------------------------------
  -- Funções utilitárias para imprimir em hexadecimal (ASCII puro)
  ------------------------------------------------------------------
  function to_hex_char(v : std_logic_vector(3 downto 0)) return character is
    variable n : integer := to_integer(unsigned(v));
  begin
    if n < 10 then
      return character'VAL(character'POS('0') + n);
    else
      return character'VAL(character'POS('A') + n - 10);
    end if;
  end function;

  function to_hex_string(v : std_logic_vector(7 downto 0)) return string is
    variable s : string(1 to 2);
  begin
    s(1) := to_hex_char(v(7 downto 4));
    s(2) := to_hex_char(v(3 downto 0));
    return s;
  end function;

begin
  ------------------------------------------------------------------
  -- Instância da UART em loopback
  ------------------------------------------------------------------
  DUT : UART
    port map (
      clk        => clk_tb,
      reset      => reset_tb,
      data_in    => data_in_tb,
      tx_start   => tx_start_tb,
      tx_out     => tx_out_tb,
      busy       => busy_tb,
      rx_in      => rx_in_tb,
      data_out   => data_out_tb,
      data_valid => data_valid_tb
    );

  -- Loopback: TX → RX
  rx_in_tb <= tx_out_tb;

  ------------------------------------------------------------------
  -- Clock de 50 MHz (período 20 ns)
  ------------------------------------------------------------------
  ClockGen : process
  begin
    wait for 10 ns;
    clk_tb <= not clk_tb;
  end process;

  ------------------------------------------------------------------
  -- Estímulos: envia 0xAA e depois 0xFF
  ------------------------------------------------------------------
  Stimulus : process
  begin
    -- Reset inicial
    reset_tb <= '1';
    wait for 40 ns;
    reset_tb <= '0';
    wait for 20 ns;

    ----------------------------------------------------------------
    -- 1º byte = 0xAA
    ----------------------------------------------------------------
    data_in_tb  <= x"AA";
    tx_start_tb <= '1';
    wait for 20 ns;              -- pulso de 1 ciclo
    tx_start_tb <= '0';

    wait until busy_tb = '0';    -- transmissor livre
    wait for 20 ns;              -- garante que FSM voltou a IDLE
    wait until data_valid_tb = '1';

    if data_out_tb = x"AA" then
      report "Byte 1 recebido corretamente: 0x" & to_hex_string(data_out_tb)
        severity note;
    else
      report "ERRO - byte 1 incorreto! Esperado 0xAA, recebido 0x"
        & to_hex_string(data_out_tb) severity error;
    end if;
    wait until data_valid_tb = '0';

    ----------------------------------------------------------------
    -- 2º byte = 0xFF
    ----------------------------------------------------------------
    data_in_tb  <= x"FF";
    tx_start_tb <= '1';
    wait for 40 ns;
    tx_start_tb <= '0';

    wait until busy_tb = '0';
    wait for 20 ns;              -- novo ciclo para garantir IDLE
    wait until data_valid_tb = '1';

    if data_out_tb = x"FF" then
      report "Byte 2 recebido corretamente: 0x" & to_hex_string(data_out_tb)
        severity note;
    else
      report "ERRO - byte 2 incorreto! Esperado 0xFF, recebido 0x"
        & to_hex_string(data_out_tb) severity error;
    end if;
    wait until data_valid_tb = '0';

    ----------------------------------------------------------------
    report "Teste concluido!" severity note;
    wait;                        -- encerra simulação
  end process;

end architecture;
