library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

package fpga_dual_port_ram_pkg is

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

    function sine_table_entries return integer_array;

    type ram_read_port_record is record
        read_address             : address_integer;
        read_requested_with_1    : std_logic;
        data_is_ready_to_be_read : boolean;
        data                     : lut_integer;
    end record;

    constant init_ram_read : ram_read_port_record := (0, '0', false, 0);

    type ram_write_port_record is record
        write_address          : address_integer;
        write_requested_with_1 : std_logic_vector(1 downto 0);
        write_buffer           : integer;
    end record;

    constant init_ram_write_port : ram_write_port_record := (0, "00", 0);

    type ram_record is record
        ram_read_port  : ram_read_port_record;
        ram_write_port : ram_write_port_record;
        ram_memory     : integer_array(0 to lookup_table_bits-1);
    end record;

    function init_dual_port_ram return ram_record;

------------------------------------------------------------------------
    procedure create_dual_port_ram (
        signal ram_object : inout ram_record);
------------------------------------------------------------------------
    procedure request_data_from_ram (
        signal ram_object : out ram_record;
        address : integer);

    procedure request_data_from_ram_and_increment (
        signal ram_read_counter : inout integer;
        signal ram_object : out ram_record;
        address : integer);
------------------------------------------------------------------------
    function get_ram_data ( ram_object : ram_record)
        return integer;
------------------------------------------------------------------------
    function ram_is_ready ( ram_object : ram_record)
        return boolean;
------------------------------------------------------------------------
    procedure write_data_to_ram (
        signal ram_object : inout ram_record;
        address : in integer;
        data    : in integer);

    procedure write_data_to_ram (
        signal counter_to_be_incremented_at_write : inout integer;
        signal ram_object : inout ram_record;
        address : in integer;
        data    : in integer);
------------------------------------------------------------------------

------------------------------------------------------------------------
end package fpga_dual_port_ram_pkg;

------------------------------------------------------------------------
package body fpga_dual_port_ram_pkg is

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
    procedure create_dual_port_ram
    (
        signal ram_object : inout ram_record
    ) is
    begin

        ram_object.ram_read_port.read_requested_with_1 <= '0';
        ram_object.ram_read_port.data_is_ready_to_be_read <= ram_object.ram_read_port.read_requested_with_1 = '1';

        if ram_object.ram_read_port.read_requested_with_1 = '1' then
            ram_object.ram_read_port.data <= ram_object.ram_memory(ram_object.ram_read_port.read_address);
        end if;

        ram_object.ram_write_port.write_requested_with_1 <= ram_object.ram_write_port.write_requested_with_1(0) & '0';
        if ram_object.ram_write_port.write_requested_with_1(1) = '1' then
            ram_object.ram_memory(ram_object.ram_write_port.write_address) <= ram_object.ram_write_port.write_buffer;
        end if;

    end create_dual_port_ram;
------------------------------------------------------------------------
    procedure request_data_from_ram
    (
        signal ram_object : out ram_record;
        address : integer
    ) is
    begin
        ram_object.ram_read_port.read_requested_with_1 <= '1';
        ram_object.ram_read_port.read_address <= address;
    end request_data_from_ram;
------------------------------------------------------------------------
    procedure request_data_from_ram_and_increment
    (
        signal ram_read_counter : inout integer;
        signal ram_object : out ram_record;
        address : integer
    ) is
    begin
        ram_read_counter <= ram_read_counter + 1;
        ram_object.ram_read_port.read_requested_with_1 <= '1';
        ram_object.ram_read_port.read_address <= address;
    end request_data_from_ram_and_increment;
------------------------------------------------------------------------
    function ram_is_ready
    (
        ram_object : ram_record
    )
    return boolean
    is
    begin
        return ram_object.ram_read_port.data_is_ready_to_be_read;
    end ram_is_ready;
------------------------------------------------------------------------
    function get_ram_data
    (
        ram_object : ram_record
    )
    return integer
    is
    begin
        return ram_object.ram_read_port.data;
    end get_ram_data;
------------------------------------------------------------------------
------------------------------------------------------------------------
    procedure write_data_to_ram
    (
        signal ram_object : inout ram_record;
        address : in integer;
        data    : in integer
    ) is
    begin
        ram_object.ram_write_port.write_requested_with_1(0) <= '1';
        ram_object.ram_write_port.write_buffer <= data;
        ram_object.ram_write_port.write_address <= address;
        
    end write_data_to_ram;

    procedure write_data_to_ram
    (
        signal counter_to_be_incremented_at_write : inout integer;
        signal ram_object : inout ram_record;
        address : in integer;
        data    : in integer
    ) is
    begin
        counter_to_be_incremented_at_write <= counter_to_be_incremented_at_write + 1;
        write_data_to_ram(ram_object, address, data);
        
    end write_data_to_ram;
------------------------------------------------------------------------
    function sine_table_entries
    return integer_array
    is
    begin
        return calculate_ram_initial_values(lookup_table_bits,16);
        
    end sine_table_entries;
------------------------------------------------------------------------
    function init_dual_port_ram return ram_record
    is
    begin
        return ( init_ram_read, init_ram_write_port, sine_table_entries);
        
    end init_dual_port_ram;
end package body fpga_dual_port_ram_pkg;
