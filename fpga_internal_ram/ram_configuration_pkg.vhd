library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package ram_configuration_pkg is

    -- make visible when using ram_read
    constant ram_bit_width : natural := 20;
    constant ram_depth     : natural := 2**7;

    subtype address_integer is natural range 0 to ram_depth-1;
    subtype t_ram_data      is std_logic_vector(ram_bit_width-1 downto 0);

end package ram_configuration_pkg;
------------------------------------------------------------------------
