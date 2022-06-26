library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

package ram_read_port_pkg is

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

    constant init_ram_data_with_indices : integer_array(0 to lookup_table_bits-1) := calculate_ram_initial_values(lookup_table_bits,16); 

    type ram_read_port_record is record
        read_address             : address_integer;
        read_requested_with_1    : std_logic;
        data_is_ready_to_be_read : boolean;
        data                     : lut_integer;
    end record;

    constant init_ram_read_port : ram_read_port_record := (0, '0', false, 0);

------------------------------------------------------------------------
    procedure create_ram_read_port (
        signal ram_read_object : inout ram_read_port_record;
        ram_memory : integer_array);
------------------------------------------------------------------------
    procedure request_data_from_ram_and_increment (
        signal ram_read_counter : inout integer;
        signal ram_read_object : out ram_read_port_record;
        address : integer);
------------------------------------------------------------------------
    function ram_read_is_ready ( ram_read_object : ram_read_port_record)
        return boolean;
------------------------------------------------------------------------
    function get_ram_data ( ram_read_object : ram_read_port_record)
        return integer;
------------------------------------------------------------------------
    procedure request_data_from_ram (
        signal ram_read_object : out ram_read_port_record;
        address : integer);
------------------------------------------------------------------------
end package ram_read_port_pkg;

------------------------------------------------------------------------
package body ram_read_port_pkg is

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
            sine_lut(i) := i;
        end loop;
        return sine_lut;

    end calculate_ram_initial_values;
------------------------------------------------------------------------
    procedure create_ram_read_port
    (
        signal ram_read_object : inout ram_read_port_record;
        ram_memory : integer_array
    ) is
    begin

        ram_read_object.read_requested_with_1 <= '0';
        ram_read_object.data_is_ready_to_be_read <= false;

        if ram_read_object.read_requested_with_1 = '1' then
            ram_read_object.data <= ram_memory(ram_read_object.read_address);
            ram_read_object.data_is_ready_to_be_read <= ram_read_object.read_requested_with_1 = '1';
        end if;

    end create_ram_read_port;
------------------------------------------------------------------------
    procedure request_data_from_ram
    (
        signal ram_read_object : out ram_read_port_record;
        address : integer
    ) is
    begin
        ram_read_object.read_requested_with_1 <= '1';
        ram_read_object.read_address <= address;
    end request_data_from_ram;
------------------------------------------------------------------------
    procedure request_data_from_ram_and_increment
    (
        signal ram_read_counter : inout integer;
        signal ram_read_object : out ram_read_port_record;
        address : integer
    ) is
    begin
        ram_read_counter <= ram_read_counter + 1;
        ram_read_object.read_requested_with_1 <= '1';
        ram_read_object.read_address <= address;
    end request_data_from_ram_and_increment;
------------------------------------------------------------------------
    function ram_read_is_ready
    (
        ram_read_object : ram_read_port_record
    )
    return boolean
    is
    begin
        return ram_read_object.data_is_ready_to_be_read;
    end ram_read_is_ready;
------------------------------------------------------------------------
    function get_ram_data
    (
        ram_read_object : ram_read_port_record
    )
    return integer
    is
    begin
        return ram_read_object.data;
    end get_ram_data;
------------------------------------------------------------------------
end package body ram_read_port_pkg;
