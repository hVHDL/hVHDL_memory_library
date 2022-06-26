library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

package ram_write_port_pkg is

    constant lookup_table_bits : integer := 2**10;
    subtype address_integer is integer range 0 to 2**10-1;
    subtype lut_integer is integer range -2**16 to 2**16-1;

    type integer_array is array (integer range <>) of lut_integer;
------------------------------------------------------------------------
    function calculate_ram_initial_values (
        number_of_entries : natural;
        number_of_bits    : natural range 8 to 32)
    return integer_array;
------------------------------------------------------------------------

    constant sine_table_entries : integer_array(0 to lookup_table_bits-1) := calculate_ram_initial_values(lookup_table_bits,16); 

    type ram_write_port_record is record
        write_address             : address_integer;
        write_is_requested_with_1 : std_logic;
        write_is_ready            : boolean;
        write_buffer              : lut_integer;
    end record;

    constant init_ram_write_port : ram_write_port_record := (0, '0', false, 0);

------------------------------------------------------------------------
end package ram_write_port_pkg;

------------------------------------------------------------------------
package body ram_write_port_pkg is

------------------------------------------------------------------------
    function calculate_ram_initial_values
    (
        number_of_entries : natural;
        number_of_bits : natural range 8 to 32
    )
    return integer_array
    is
        variable sine_lut : integer_array(0 to number_of_entries-1);
    begin
        for i in 0 to number_of_entries-1 loop
            sine_lut(i) := 44252 + i;
        end loop;
        return sine_lut;

    end calculate_ram_initial_values;
------------------------------------------------------------------------
    procedure create_ram_write_port
    (
        signal ram_object : inout ram_write_port_record;
        signal ram_memory : inout integer_array
    ) is
    begin

        ram_object.write_is_requested_with_1 <= '0';
        if ram_object.write_is_requested_with_1 = '1' then
            ram_memory(ram_object.write_address) <= ram_object.write_buffer;
        end if;

    end create_ram_write_port;
------------------------------------------------------------------------
    procedure write_data_to_ram
    (
        signal ram_object : inout ram_write_port_record;
        address : in integer;
        data    : in integer
    ) is
    begin
        ram_object.write_is_requested_with_1 <= '1';
        ram_object.write_buffer <= data;
        ram_object.write_address <= address;
        
    end write_data_to_ram;

    procedure write_data_to_ram
    (
        signal counter_to_be_incremented_at_write : inout integer;
        signal ram_object : inout ram_write_port_record;
        address : in integer;
        data    : in integer
    ) is
    begin
        counter_to_be_incremented_at_write <= counter_to_be_incremented_at_write + 1;
        write_data_to_ram(ram_object, address, data);
        
    end write_data_to_ram;
------------------------------------------------------------------------
end package body ram_write_port_pkg;
