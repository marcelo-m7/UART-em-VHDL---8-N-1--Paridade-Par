library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART is
  Port (
    clk       : in  std_logic;                         -- Clock do sistema
    reset     : in  std_logic;                         -- Reset assíncrono ativo em nível alto
    data_in   : in  std_logic_vector(7 downto 0);      -- Byte de dados de entrada para transmissão
    tx_start  : in  std_logic;                         -- Sinal para iniciar transmissão do data_in
    tx_out    : out std_logic;                         -- Saída serial do transmissor UART
    busy      : out std_logic;                         -- Indicador de transmissor ocupado (ocupado=1)
    rx_in     : in  std_logic;                         -- Entrada serial do receptor UART
    data_out  : out std_logic_vector(7 downto 0);      -- Byte de dados paralelo recebido
    data_valid: out std_logic                          -- Sinal indicando que data_out tem dado válido
    -- parity_error : out std_logic                    -- (Opcional) '1' se erro de paridade detectado
  );
end UART;

architecture Behavioral of UART is

  -- Constante para definir duração de cada bit em ciclos de clock (sem oversampling)
  constant BIT_TICKS : integer := 16;
  -- Constante para oversampling: meio período do bit (amostragem 8x)
  constant HALF_BIT_TICKS : integer := BIT_TICKS / 2;
  -- Constante para contagem estendida no estado de stop (paridade + 1.5 bits)
  constant RX_STOP_COUNT : integer := BIT_TICKS + HALF_BIT_TICKS + 1;

  -- Estados para FSM do transmissor (Tx)
  type Tx_State_Type is (IDLE, START, DATA, PARITY, STOP);
  signal tx_state : Tx_State_Type := IDLE;

  -- Estados para FSM do receptor (Rx)
  type Rx_State_Type is (RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP);
  signal rx_state : Rx_State_Type := RX_IDLE;

  -- Sinais internos do transmissor
  signal data_reg      : std_logic_vector(7 downto 0) := (others => '0');  -- buffer de dados a transmitir
  signal parity_bit    : std_logic := '0';        -- bit de paridade calculado (even parity)
  signal tx_out_reg    : std_logic := '1';        -- registro para tx_out (linha serial)
  signal busy_reg      : std_logic := '0';        -- registro para sinal busy
  signal tx_tick_count : integer range 0 to BIT_TICKS-1 := 0;  -- contador de ticks para temporização de bits
  signal tx_bit_count  : integer range 0 to 8 := 0;            -- contador de bits de dados enviados

  -- Sinais internos do receptor
  signal data_buffer   : std_logic_vector(7 downto 0) := (others => '0');  -- buffer montando byte recebido
  signal parity_calc   : std_logic := '0';        -- acumulador de paridade (XOR dos bits recebidos)
  signal parity_error_flag : std_logic := '0';    -- flag interna de erro de paridade
  signal data_valid_reg: std_logic := '0';        -- registro do sinal data_valid
  signal rx_tick_count : integer range 0 to RX_STOP_COUNT-1 := 0;  -- contador de ticks para temporização (oversampling)
  signal rx_bit_count  : integer range 0 to 7 := 0;            -- contador de bits de dados já recebidos

begin
  -- Mapeamento das saídas registradas para as portas de saída da entidade
  tx_out    <= tx_out_reg;
  busy      <= busy_reg;
  data_out  <= data_buffer;
  data_valid <= data_valid_reg;
  -- parity_error <= parity_error_flag;  -- (Descomentar se quiser saída de erro de paridade)

  --------------------------------------------------------------------
  -- Processo do Transmissor (Tx_Process): FSM para transmissão UART
  --------------------------------------------------------------------
  Tx_Process: process(clk, reset)
  begin
    if reset = '1' then
      -- Reset: reinicia todos os registradores do transmissor
      tx_state     <= IDLE;
      tx_out_reg   <= '1';         -- linha TX em repouso (alto)
      busy_reg     <= '0';         -- transmissor livre
      tx_tick_count <= 0;
      tx_bit_count  <= 0;
      data_reg     <= (others => '0');
      parity_bit   <= '0';
    elsif rising_edge(clk) then
      case tx_state is

        when IDLE =>
          tx_out_reg <= '1';      -- estado idle: linha TX permanece em nível alto
          busy_reg   <= '0';      -- não ocupado em idle
          if tx_start = '1' then
            -- Início de transmissão: carregar dados e calcular paridade (paridade par)
            data_reg   <= data_in;
            parity_bit <= data_in(0) xor data_in(1) xor data_in(2) xor data_in(3) xor 
                         data_in(4) xor data_in(5) xor data_in(6) xor data_in(7);
            tx_bit_count  <= 0;
            tx_tick_count <= 0;
            busy_reg  <= '1';     -- sinaliza ocupado durante a transmissão
            tx_state  <= START;   -- vai enviar o start bit
          end if;

        when START =>
          tx_out_reg <= '0';   -- envia bit de Start (nível baixo)
          if tx_tick_count < BIT_TICKS-1 then
            tx_tick_count <= tx_tick_count + 1;  -- aguarda término do período do start bit
          else
            -- Concluiu período do start, passa ao primeiro bit de dados
            tx_tick_count <= 0;
            tx_state <= DATA;
            -- Configura a saída para o primeiro bit de dado (LSB) e prepara shift
            tx_out_reg <= data_reg(0);           -- LSB do data_reg na linha TX
            data_reg <= '0' & data_reg(7 downto 1);  -- desloca data_reg para direita (descarta LSB enviado)
            tx_bit_count <= 1;                   -- já enviou 1º bit de dado
          end if;

        when DATA =>
          -- Envia bits de dados (já estamos com um bit em tx_out_reg)
          if tx_tick_count < BIT_TICKS-1 then
            tx_tick_count <= tx_tick_count + 1;  -- mantém o bit atual por todo o período
          else
            tx_tick_count <= 0;
            if tx_bit_count < 8 then
              -- Passa para o próximo bit de dado
              tx_out_reg <= data_reg(0);            -- coloca próximo bit (seguinte LSB) na saída
              data_reg <= '0' & data_reg(7 downto 1);-- desloca para preparar próximo bit
              tx_bit_count <= tx_bit_count + 1;     -- incrementa contador de bits enviados
              -- permanece no estado DATA até enviar todos os 8 bits
            else
              -- Todos os 8 bits de dado foram enviados; ir para bit de paridade
              tx_state <= PARITY;
              tx_out_reg <= parity_bit;    -- coloca o bit de paridade calculado na linha TX
              -- tx_bit_count neste momento deve ser 8 (8 bits enviados)
            end if;
          end if;

        when PARITY =>
          -- Bit de paridade sendo transmitido
          if tx_tick_count < BIT_TICKS-1 then
            tx_tick_count <= tx_tick_count + 1;  -- mantém bit de paridade por todo o período
          else
            tx_tick_count <= 0;
            tx_state <= STOP;
            tx_out_reg <= '1';   -- após paridade, envia bit de parada (alto)
          end if;

        when STOP =>
          -- Bit de parada sendo transmitido (tx_out_reg já está em '1')
          if tx_tick_count < BIT_TICKS-1 then
            tx_tick_count <= tx_tick_count + 1;  -- mantém stop bit pelo período necessário
          else
            -- Fim do bit de parada, encerrar transmissão
            tx_tick_count <= 0;
            busy_reg <= '0';     -- transmissor fica livre (busy=0)
            tx_state <= IDLE;    -- retorna ao estado ocioso (linha TX permanece em '1')
          end if;

      end case;
    end if;
  end process Tx_Process;

  --------------------------------------------------------------------
  -- Processo do Receptor (Rx_Process): FSM para recepção UART
  --------------------------------------------------------------------
  Rx_Process: process(clk, reset)
  begin
    if reset = '1' then
      -- Reset: reinicia todos os registradores do receptor
      rx_state       <= RX_IDLE;
      data_buffer    <= (others => '0');
      data_valid_reg <= '0';
      parity_calc    <= '0';
      parity_error_flag <= '0';
      rx_tick_count  <= 0;
      rx_bit_count   <= 0;
    elsif rising_edge(clk) then
      case rx_state is

        when RX_IDLE =>
          data_valid_reg <= '0';       -- em idle, não há dado válido novo (limpa sinal)
          parity_error_flag <= '0';    -- limpa flag de erro de paridade
          if rx_in = '0' then          -- detecta início (start bit = 0)
            rx_state <= RX_START;
            rx_tick_count <= 0;
            rx_bit_count <= 0;
            parity_calc <= '0';        -- reseta cálculo de paridade para novo byte
          end if;

        when RX_START =>
          -- Aguarda meio período do start bit para alinhar amostragem (oversampling 8x)
          if rx_tick_count < (HALF_BIT_TICKS - 1) then
            rx_tick_count <= rx_tick_count + 1;
          else
            rx_tick_count <= 0;
            -- Verifica se linha permanece em nível baixo (start válido)
            if rx_in = '0' then
              rx_state <= RX_DATA;    -- meio do start alcançado, pronto para começar a amostrar dados
            else
              rx_state <= RX_IDLE;    -- ruído detectado, retorna ao idle
            end if;
          end if;

        when RX_DATA =>
          if rx_tick_count < BIT_TICKS-1 then
            rx_tick_count <= rx_tick_count + 1;
          else
            rx_tick_count <= 0;
            -- Amostra bit de dado no meio do período do bit (já alinhado)
            data_buffer(rx_bit_count) <= rx_in;        -- guarda o bit recebido na posição apropriada (LSB primeiro)
            parity_calc <= parity_calc xor rx_in;      -- acumula bit para verificação de paridade
            if rx_bit_count = 7 then
              -- Último bit de dado recebido (MSB)
              rx_state <= RX_PARITY;
            else
              -- Ainda há bits de dados restantes
              rx_bit_count <= rx_bit_count + 1;
            end if;
          end if;

        when RX_PARITY =>
          if rx_tick_count < BIT_TICKS-1 then
            rx_tick_count <= rx_tick_count + 1;
          else
            rx_tick_count <= 0;
            -- Verifica paridade do byte recebido em comparação com o bit de paridade recebido
            parity_error_flag <= parity_calc xor rx_in;  -- '1' se bit de paridade não corresponder (erro de paridade)
            rx_state <= RX_STOP;
          end if;

        when RX_STOP =>
          if rx_tick_count < (RX_STOP_COUNT - 1) then
            rx_tick_count <= rx_tick_count + 1;
            -- (Opcional: poderia-se checar rx_in = '1' durante o stop bit; assume-se correto)
          else
            rx_tick_count <= 0;
            -- Byte recebido completamente; sinaliza dado válido
            data_valid_reg <= '1';    -- indica que data_out (data_buffer) contém um byte válido
            rx_state <= RX_IDLE;      -- retorna ao estado ocioso para aguardar próximo frame
            -- parity_error_flag pode ser consultada se necessário
          end if;

      end case;
    end if;
  end process Rx_Process;

end Behavioral;
