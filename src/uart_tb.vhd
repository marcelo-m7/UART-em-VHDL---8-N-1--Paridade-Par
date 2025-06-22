library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_tb is
end UART_tb;

architecture sim of UART_tb is
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

  signal clk_tb        : std_logic := '0';
  signal reset_tb      : std_logic := '0';
  signal data_in_tb    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_start_tb   : std_logic := '0';
  signal tx_out_tb     : std_logic;
  signal busy_tb       : std_logic;
  signal rx_in_tb      : std_logic;
  signal data_out_tb   : std_logic_vector(7 downto 0);
  signal data_valid_tb : std_logic;

begin
  -- Instancia DUT (Dispositivo Sob Teste)
  DUT: UART 
    port map(
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

  -- Conecta saída do transmissor na entrada do receptor (loopback)
  rx_in_tb <= tx_out_tb;

  -- Geração de clock de 50 MHz (período 20 ns)
  ClockGen: process
  begin
    wait for 10 ns;
    clk_tb <= not clk_tb;
  end process;

  Stimulus: process
  begin
    -- Aplicar reset inicial
    reset_tb <= '1';
    wait for 40 ns;
    reset_tb <= '0';
    wait for 20 ns;

    -- Enviar byte 0xAA
    data_in_tb  <= "10101010";  -- 0xAA
    tx_start_tb <= '1';
    wait for 20 ns;
    tx_start_tb <= '0';

    -- Espera fim da transmissão (busy_tb = '0')
    wait until busy_tb = '0';

    -- Espera recepção completa (data_valid_tb = '1')
    wait until data_valid_tb = '1';

    -- Verificar resultado da recepção
    if data_out_tb = "10101010" then
      report "Recepção bem-sucedida: data_out = " & integer'image(to_integer(unsigned(data_out_tb))) & " (0xAA)" severity note;
    else
      report "Falha na recepção ou dado incorreto! (Esperado 0xAA)" severity error;
    end if;

    wait;  -- fim da simulação
  end process;

end architecture;
