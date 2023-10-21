-------------------------------------------------------------------------------
--
-- Copyright (C) 2013-2019 Efinix Inc. All rights reserved.
-- 
-- True Dual Port RAM with 2 clocks and read first mode.  
-- *******************************
-- Revisions:
-- 0.0 Initial release
-- *******************************

library ieee;
use ieee.std_logic_1164.all;

package ram_pkg is
    function logb2 (depth: in natural) return integer;
end ram_pkg;

package body ram_pkg is

    function logb2( depth : natural) return integer is
        variable temp    : integer := depth;
        variable ret_val : integer := 0;
    begin
        while temp > 1 loop
            ret_val := ret_val + 1;
            temp    := temp / 2;
        end loop;

        return ret_val;
    end function;

end package body ram_pkg;

------------------------------------------------------------------------
library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ram_pkg.all;
USE std.textio.all;

entity efx_true_dual_port_read_first_2_clk_ram is
generic (
    RAM_WIDTH : integer := 8;     -- Set RAM data width
    RAM_DEPTH : integer := 32;    -- Set RAM depth
    OUTREG    : boolean := false; -- Set OUTREG to false/true
    INIT_FILE : string  := ""     -- Set memory initialization file E.g. input file name "ram_init.mem",  Memory will be initialled to all zero by default.
);

port (
        addra : in std_logic_vector((logb2(RAM_DEPTH)-1) downto 0); -- Port A Address
        addrb : in std_logic_vector((logb2(RAM_DEPTH)-1) downto 0); -- Port B Address
        dina  : in std_logic_vector(RAM_WIDTH-1 downto 0);          -- Port A RAM input data
        dinb  : in std_logic_vector(RAM_WIDTH-1 downto 0);          -- Port B RAM input data
        clka  : in std_logic;                                       -- Port A Clock
        clkb  : in std_logic;                                       -- Port B Clock
        wea   : in std_logic;                                       -- Port A Write enable
        web   : in std_logic;                                       -- Port B Write enable
        ena   : in std_logic;                                       -- Port A RAM Enable
        enb   : in std_logic;                                       -- Port B RAM Enable
        rsta  : in std_logic;                                       -- Port A Output reset
        rstb  : in std_logic;                                       -- Port B Output reset
        regcea: in std_logic;                                       -- Port A Output register enable
        regceb: in std_logic;                                       -- Port B Output register enable
        douta : out std_logic_vector(RAM_WIDTH-1 downto 0);         -- Port A RAM output data
        doutb : out std_logic_vector(RAM_WIDTH-1 downto 0)          -- Port B RAM output data
    );

end efx_true_dual_port_read_first_2_clk_ram;

architecture rtl of efx_true_dual_port_read_first_2_clk_ram is

    constant C_RAM_WIDTH : integer := RAM_WIDTH;
    constant C_RAM_DEPTH : integer := RAM_DEPTH;
    constant C_OUTREG : boolean    := OUTREG;
    constant C_INIT_FILE : string  := INIT_FILE;

    signal douta_reg : std_logic_vector(C_RAM_WIDTH-1 downto 0) := (others => '0');
    signal doutb_reg : std_logic_vector(C_RAM_WIDTH-1 downto 0) := (others => '0');

    type ram_type is array (C_RAM_DEPTH-1 downto 0) of std_logic_vector (C_RAM_WIDTH-1 downto 0);         

    signal ram_data_a : std_logic_vector(C_RAM_WIDTH-1 downto 0) ;
    signal ram_data_b : std_logic_vector(C_RAM_WIDTH-1 downto 0) ;

    function init_ram_frm_file (ramfilename : in string) return ram_type is
        file ramfile	: text open read_mode is ramfilename;
        variable ramfileline : line;
        variable ram_name	: ram_type;
        variable temp_bitvec : bit_vector(C_RAM_WIDTH-1 downto 0);
    begin
        for i in ram_type'reverse_range loop
            readline (ramfile, ramfileline);
            read (ramfileline, temp_bitvec);
            ram_name(i) := to_stdlogicvector(temp_bitvec);
        end loop;
        return ram_name;
    end function;

    function init_from_sel(ramfile : string) return ram_type is
    begin
        if ramfile = "" then
            return (others => (others => '0'));
        else 
            return init_ram_frm_file(ramfile) ;
        end if;
    end;


    shared variable ram_name : ram_type := init_from_sel(C_INIT_FILE);

begin

    process(clka)
    begin
        if(rising_edge(clka)) then
            if(ena = '1') then
                ram_data_a <= ram_name(to_integer(unsigned(addra)));
                if(wea = '1') then
                    ram_name(to_integer(unsigned(addra))) := dina;
                end if;
            end if;
      end if;
    end process;

    process(clkb)
    begin
        if(rising_edge(clkb)) then
            if(enb = '1') then
                ram_data_b <= ram_name(to_integer(unsigned(addrb)));
                if(web = '1') then
                    ram_name(to_integer(unsigned(addrb))) := dinb;
                end if;
            end if;
        end if;
    end process;


    no_outreg : if not C_OUTREG  generate
        douta <= ram_data_a;
        doutb <= ram_data_b;
    end generate;


    yes_outreg : if C_OUTREG  generate
        process(clka)
        begin
            if(rising_edge(clka)) then
                if(rsta = '1') then
                    douta_reg <= (others => '0');
                elsif(regcea = '1') then
                    douta_reg <= ram_data_a;
                end if;
            end if;
        end process;
        douta <= douta_reg;

        process(clkb)
        begin
            if(rising_edge(clkb)) then
                if(rstb = '1') then
                    doutb_reg <= (others => '0');
                elsif(regceb = '1') then
                    doutb_reg <= ram_data_b;
                end if;
            end if;
        end process;
        doutb <= doutb_reg;
    end generate;
end rtl;
