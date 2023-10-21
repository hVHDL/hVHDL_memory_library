-------------------------------------------------------------------------------
--
-- Copyright (C) 2013-2019 Efinix Inc. All rights reserved.
-- 
-- True Dual Port RAM with 1 clock and no change mode. 
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
    USE std.textio.all;

    use work.ram_port_pkg.all;
    use work.ram_pkg.all;

entity efx_true_dual_port_no_change_1_clk_ram is
generic (
    OUTREG          : boolean := true;             -- Set outreg true/false
    INIT_RAM_VALUES : ram_array
    );

port (
        addra : in std_logic_vector((logb2(ram_array'length)-1) downto 0); -- Port A Address bus, calculated from RAM_DEPTH
        addrb : in std_logic_vector((logb2(ram_array'length)-1) downto 0); -- Port B Address bus, calculated from RAM_DEPTH
        dina  : in ramtype;                                                -- Port A RAM input data
        dinb  : in ramtype;                                                -- Port B RAM input data
        clka  : in std_logic;                                              -- Clock
        wea   : in std_logic;                                              -- Port A Write enable
        web   : in std_logic;                                              -- Port B Write enable
        ena   : in std_logic;                                              -- Port A RAM Enable
        enb   : in std_logic;                                              -- Port B RAM Enable
        rsta  : in std_logic;                                              -- Port A Output reset
        rstb  : in std_logic;                                              -- Port B Output reset
        douta : out ramtype;                                               -- Port A RAM output data
        doutb : out ramtype                                                -- Port B RAM output data
    );

end efx_true_dual_port_no_change_1_clk_ram;

architecture RTL of efx_true_dual_port_no_change_1_clk_ram is

constant C_OUTREG    : boolean := OUTREG;

    signal douta_reg : ramtype := (others => '0');
    signal doutb_reg : ramtype := (others => '0');

    signal ram_data_a : ramtype ;
    signal ram_data_b : ramtype ;

    shared variable ram_name : ram_array := INIT_RAM_VALUES;

begin

------------------------------------------------------------------------
    process(clka)
    begin
        if(rising_edge(clka)) then
            --if(ena = '1') then
                if(wea = '1') then
                    ram_name(to_integer(unsigned(addra))) := dina;
                else
                    ram_data_a <= ram_name(to_integer(unsigned(addra)));
                end if;
            --end if;
        end if;
    end process;

------------------------------------------------------------------------
    process(clka)
    begin
        if(rising_edge(clka)) then
            --if(ena = '1') then
                if(web = '1') then
                    ram_name(to_integer(unsigned(addrb))) := dinb;
                else
                    ram_data_b <= ram_name(to_integer(unsigned(addrb)));
                end if;
            --end if;
        end if;
    end process;

------------------------------------------------------------------------
    no_outreg : if not C_OUTREG  generate
        douta <= ram_data_a;
        doutb <= ram_data_b;
    end generate;
            
------------------------------------------------------------------------
    yes_outreg : if C_OUTREG  generate
        process(clka)
        begin
            if(rising_edge(clka)) then
                if(rsta = '1') then
                    douta_reg <= (others => '0');
                else
                    douta_reg <= ram_data_a;
                end if;
            end if;
        end process;
        douta <= douta_reg;
        ----
        process(clka)
        begin
            if(rising_edge(clka)) then
                if(rstb = '1') then
                    doutb_reg <= (others => '0');
                else
                    doutb_reg <= ram_data_b;
                end if;
            end if;
        end process;
        doutb <= doutb_reg;
    end generate;

end RTL;
