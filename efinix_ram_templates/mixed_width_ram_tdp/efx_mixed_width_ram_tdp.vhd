-------------------------------------------------------------------------------
--
-- Copyright (C) 2013-2019 Efinix Inc. All rights reserved.
-- 
-- True Dual-Port RAM
-- 1) Single Clock
-- 2) Different data width on the 2 ports.
-- 3) During write, read returns old data for mixed ports and new data on the same
-- port.
--
-- The first port datawidth and address width are specificed. Then the second
-- port data width is :
-- DATA_WIDTH1 * RATIO, where RATIO = (1 << (ADDRESS_WIDTH1 - ADDRESS_WIDT2).
-- RATIO must have value that is supported by the memory blocks in TRION.

-- VHDL Template for Asymmetric TDP RAM.
-- *******************************
-- Revisions:
-- 0.0 Initial release
-- *******************************

library ieee;
use ieee.std_logic_1164.all;

entity efx_mixed_width_ram_tdp is
	generic (
          OUTREG_A        : boolean :=false; 
          OUTREG_B        : boolean :=false;
          WRITE_MODE_A    : string :="READ_FIRST";
          WRITE_MODE_B    : string :="READ_FIRST";
          DATA_WIDTH_A    : natural :=  8;      
          ADDRESS_WIDTH_A : natural :=  10;
          ADDRESS_WIDTH_B : natural :=  8);

	port (
          clk            : in std_logic;
          en             : in std_logic;
          we_a           : in std_logic;
          we_b           : in std_logic;
          addr_a         : in natural range 0 to (2 ** ADDRESS_WIDTH_A - 1);
          addr_b         : in natural range 0 to (2 ** ADDRESS_WIDTH_B - 1);
          data_in_a      : in  std_logic_vector(DATA_WIDTH_A - 1 downto 0);
          data_in_b      : in  std_logic_vector(DATA_WIDTH_A * (2 ** (ADDRESS_WIDTH_A - ADDRESS_WIDTH_B)) - 1 downto 0);                
          data_out_a     : out std_logic_vector(DATA_WIDTH_A - 1 downto 0);
          data_out_b     : out std_logic_vector(DATA_WIDTH_A * 2 ** (ADDRESS_WIDTH_A - ADDRESS_WIDTH_B) - 1 downto 0));

end efx_mixed_width_ram_tdp;

architecture rtl of efx_mixed_width_ram_tdp is

        -- Constant
	constant RATIO       : natural := 2 ** (ADDRESS_WIDTH_A - ADDRESS_WIDTH_B) ;
	constant DATA_WIDTH2 : natural := DATA_WIDTH_A * RATIO; 
	constant RAM_DEPTH   : natural := 2 ** ADDRESS_WIDTH_B;

        --Multi-dimentional Array. 
	type word_type is array(RATIO - 1 downto 0) of std_logic_vector(DATA_WIDTH_A - 1 downto 0);
	type ram_type is array (0 to RAM_DEPTH - 1) of word_type;

	-- RAM with shared variable. 
	shared variable  ram : ram_type;

        -- Signals 
	signal wl_wire : word_type;
	signal ql_wire : word_type;

        signal data_out_a0 : std_logic_vector(DATA_WIDTH_A - 1 downto 0);
        signal data_out_a1 : std_logic_vector(DATA_WIDTH_A - 1 downto 0);

        signal data_out_b0     : std_logic_vector(DATA_WIDTH_A * 2 ** (ADDRESS_WIDTH_A - ADDRESS_WIDTH_B) - 1 downto 0);
        signal data_out_b1     : std_logic_vector(DATA_WIDTH_A * 2 ** (ADDRESS_WIDTH_A - ADDRESS_WIDTH_B) - 1 downto 0);       
          
begin  -- rtl

        --Re-assign the signals
	gen_reassign: for i in 0 to RATIO - 1 generate    
		wl_wire(i) <= data_in_b(DATA_WIDTH_A*(i+1) - 1 downto DATA_WIDTH_A*i);
		data_out_b0(DATA_WIDTH_A*(i+1) - 1 downto DATA_WIDTH_A*i) <= ql_wire(i);
	end generate gen_reassign;


        process(clk)
	begin
          if(rising_edge(clk)) then
            if (en = '1') then
              data_out_b1 <= data_out_b0;
            end if;
          end if;
	end process;

 --Port A
 

        --Write Mode
        gen_mode0_porta: if  WRITE_MODE_A = "READ_FIRST" generate
          process(clk)
          begin
            if(rising_edge(clk)) then
              if (en = '1') then
                if(we_a ='1') then
                  ram(addr_a / RATIO)(addr_a mod RATIO) := data_in_a;
                end if;
                data_out_a0 <= ram(addr_a / RATIO )(addr_a mod RATIO);
                data_out_a1 <= data_out_a0;
              end if;
            end if;
          end process;       
        end generate gen_mode0_porta;

        gen_mode1_porta: if  WRITE_MODE_A = "WRITE_FIRST" generate
          process(clk)
          begin
            if(rising_edge(clk)) then
              if (en = '1') then
                if(we_a ='1') then
                  ram(addr_a / RATIO)(addr_a mod RATIO) := data_in_a;
                  data_out_a0 <= data_in_a;
                else
                  data_out_a0 <= ram(addr_a / RATIO )(addr_a mod RATIO);  
                end if;
                data_out_a1 <= data_out_a0;
              end if;
            end if;
          end process;       
        end generate gen_mode1_porta;

        gen_mode2_porta: if  WRITE_MODE_A = "NO_CHANGE" generate
          process(clk)
          begin
            if(rising_edge(clk)) then
              if (en = '1') then
                if(we_a ='1') then
                  ram(addr_a / RATIO)(addr_a mod RATIO) := data_in_a;
                else
                  data_out_a0 <= ram(addr_a / RATIO )(addr_a mod RATIO);    
                end if;
        
                data_out_a1 <= data_out_a0;
              end if;
            end if;
          end process;       
        end generate gen_mode2_porta;

       
        
        gen_pipe_a0: if  OUTREG_A = false generate
           data_out_a <=  data_out_a0;
        end generate gen_pipe_a0;

        gen_pipe_a1: if  OUTREG_A = true generate
           data_out_a <=  data_out_a1;
        end generate gen_pipe_a1;

        
 --Port B
        --Read First

        gen_mode0_portb: if  WRITE_MODE_A = "READ_FIRST" generate
        process(clk)
	begin
          if(rising_edge(clk)) then
            if (en = '1') then
              if(we_b = '1') then
                ram(addr_b) := wl_wire;
              end if;
              ql_wire <= ram(addr_b);
            end if;
          end if;
        end process;
       end generate gen_mode0_portb;


        --Write First.
        gen_mode1_portb: if  WRITE_MODE_A = "WRITE_FIRST" generate
	process(clk)
	begin
          if(rising_edge(clk)) then
            if (en = '1') then
              if(we_b = '1') then
                ram(addr_b) := wl_wire;
                ql_wire <= wl_wire;  
              else              
                ql_wire <= ram(addr_b);
              end if;
            end if;
          end if;
        end process;
       end generate gen_mode1_portb;


        --No Change.
   gen_mode2_portb: if  WRITE_MODE_A = "NO_CHANGE" generate

	process(clk)
	begin
          if(rising_edge(clk)) then
            if (en = '1') then
              if(we_b = '1') then
                ram(addr_b) := wl_wire;
              else
                ql_wire <= ram(addr_b);
              end if;
            end if;
          end if;
        end process;
  end generate gen_mode2_portb;


 --Pipeline on Output.

        gen_pipe_b0: if  OUTREG_B = false generate
           data_out_b <=  data_out_b0;
        end generate gen_pipe_b0;

        gen_pipe_b1: if  OUTREG_B = true generate
           data_out_b <=  data_out_b1;
        end generate gen_pipe_b1;

end rtl;
