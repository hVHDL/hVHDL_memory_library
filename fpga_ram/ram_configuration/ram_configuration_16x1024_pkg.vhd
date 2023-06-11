library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    -- 16 bit 1024 entry ram
package ram_configuration_pkg is

    constant lookup_table_size : integer := 2**10;

    subtype address_integer is integer range 0 to lookup_table_size-1;
    subtype lut_integer     is integer range -2**16 to 2**16-1;

    type integer_array      is array (integer range <>) of lut_integer;
------------------------------------------------------------------------
    function calculate_ram_initial_values ( number_of_entries : natural)
        return integer_array;
------------------------------------------------------------------------
    function init_ram_data_with_indices return integer_array;
    constant init_ram_data : integer_array(0 to lookup_table_size-1) := (others => 0);
------------------------------------------------------------------------
end package ram_configuration_pkg;

package body ram_configuration_pkg is
------------------------------------------------------------------------
    function calculate_ram_initial_values
    (
        number_of_entries : natural
    )
    return integer_array
    is
        variable sine_lut : integer_array(0 to number_of_entries-1);
    begin
        for i in 0 to number_of_entries-1 loop
            sine_lut(i) := i;
        end loop;
        return sine_lut;

    end calculate_ram_initial_values;
------------------------------------------------------------------------
    function init_ram_data_with_indices
    return integer_array
    is
    begin
        return calculate_ram_initial_values(lookup_table_size);
        
    end init_ram_data_with_indices;
end package body ram_configuration_pkg;
