----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
-- 
-- Description: TDMS Encoder 
--     8 bits colour, 2 control bits and one blanking bits in
--       10 bits of TDMS encoded data out
--     Clocked at the pixel clock
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.tmdspkg.all;

entity TDMS_encoder is
    generic (
      CHANNEL : integer range 0 to 2 := 0
    );
    Port ( clk     : in  STD_LOGIC;
           data    : in  STD_LOGIC_VECTOR (7 downto 0);
           c       : in  STD_LOGIC_VECTOR (1 downto 0);
           phase   : in  TMDS_PHASE_TYPE;
           encoded : out  STD_LOGIC_VECTOR (9 downto 0));
end TDMS_encoder;

architecture Behavioral of TDMS_encoder is
   signal xored  : STD_LOGIC_VECTOR (8 downto 0);
   signal xnored : STD_LOGIC_VECTOR (8 downto 0);
   
   signal ones                : STD_LOGIC_VECTOR (3 downto 0);
   signal data_word           : STD_LOGIC_VECTOR (8 downto 0);
   signal data_word_inv       : STD_LOGIC_VECTOR (8 downto 0);
   signal data_word_disparity : STD_LOGIC_VECTOR (3 downto 0);
   signal dc_bias             : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
   signal terc4_encoded       : STD_LOGIC_VECTOR (9 downto 0);
   signal to_terc4_encoder    : STD_LOGIC_VECTOR (3 downto 0);

   component terc4_encoder is
   port (
     din:  in std_logic_vector(3 downto 0);
     dout: out std_logic_vector(9 downto 0)
   );
   end component;

begin

  -- Packet guard... has odd bits on channel 0
  to_terc4_encoder <= data(3 downto 0) when phase/=PACKET_GUARD else c & "11";

  tenc0: terc4_encoder port map ( din => to_terc4_encoder, dout => terc4_encoded );

   -- Work our the two different encodings for the byte
   xored(0) <= data(0);
   xored(1) <= data(1) xor xored(0);
   xored(2) <= data(2) xor xored(1);
   xored(3) <= data(3) xor xored(2);
   xored(4) <= data(4) xor xored(3);
   xored(5) <= data(5) xor xored(4);
   xored(6) <= data(6) xor xored(5);
   xored(7) <= data(7) xor xored(6);
   xored(8) <= '1';

   xnored(0) <= data(0);
   xnored(1) <= data(1) xnor xnored(0);
   xnored(2) <= data(2) xnor xnored(1);
   xnored(3) <= data(3) xnor xnored(2);
   xnored(4) <= data(4) xnor xnored(3);
   xnored(5) <= data(5) xnor xnored(4);
   xnored(6) <= data(6) xnor xnored(5);
   xnored(7) <= data(7) xnor xnored(6);
   xnored(8) <= '0';
   
   -- Count how many ones are set in data
   ones <= "0000" + data(0) + data(1) + data(2) + data(3)
                   + data(4) + data(5) + data(6) + data(7);
 
   -- Decide which encoding to use
   process(ones, data(0), xnored, xored)
   begin
      if ones > 4 or (ones = 4 and data(0) = '0') then
         data_word     <= xnored;
         data_word_inv <= NOT(xnored);
      else
         data_word     <= xored;
         data_word_inv <= NOT(xored);
      end if;
   end process;                                          

   -- Work out the DC bias of the dataword;
   data_word_disparity  <= "1100" + data_word(0) + data_word(1) + data_word(2) + data_word(3) 
                                    + data_word(4) + data_word(5) + data_word(6) + data_word(7);

   -- Now work out what the output should be
   process(clk)
   begin
      if rising_edge(clk) then
        case phase is
          when VIDEO_GUARD  =>
            -- Video guard band (two pixels wide)
            case CHANNEL is
              when 0 => encoded <= "1011001100";
              when 1 => encoded <= "0100110011";
              when 2 => encoded <= "1011001100";
              when others => encoded <= (others => 'X');
            end case;

          when CONTROL | VIDEO_PREAMBLE | PACKET_PREAMBLE =>
            -- In the control periods, all values have and have balanced bit count
            -- The preamble type is set outside (on caller)
            case c is            
               when "00"   => encoded <= "1101010100";
               when "01"   => encoded <= "0010101011";
               when "10"   => encoded <= "0101010100";
               when others => encoded <= "1010101011";
            end case;
            dc_bias <= (others => '0');

          when PACKET_GUARD =>
            case CHANNEL is
              when 0    => encoded <= terc4_encoded; -- Note - this includes Hsync/Vsync
              when 1    => encoded <= "0100110011";
              when 2    => encoded <= "0100110011";
              when others => encoded <= (others => 'X');
            end case;

          when PACKET_DATA =>
            encoded <= terc4_encoded;

          when VIDEO_DATA  =>
            if dc_bias = "00000" or data_word_disparity = 0 then
               -- dataword has no disparity
               if data_word(8) = '1' then
                  encoded <= "01" & data_word(7 downto 0);
                  dc_bias <= dc_bias + data_word_disparity;
               else
                  encoded <= "10" & data_word_inv(7 downto 0);
                  dc_bias <= dc_bias - data_word_disparity;
               end if;
            elsif (dc_bias(3) = '0' and data_word_disparity(3) = '0') or 
                  (dc_bias(3) = '1' and data_word_disparity(3) = '1') then
               encoded <= '1' & data_word(8) & data_word_inv(7 downto 0);
               dc_bias <= dc_bias + data_word(8) - data_word_disparity;
            else
               encoded <= '0' & data_word;
               dc_bias <= dc_bias - data_word_inv(8) + data_word_disparity;
            end if;
          when others => encoded <= (others => 'X');
         end case;
      end if;
   end process;      
end Behavioral;