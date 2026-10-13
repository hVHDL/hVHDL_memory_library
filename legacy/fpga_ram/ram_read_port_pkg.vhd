library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

    use work.ram_configuration_pkg.all;

package ram_read_port_pkg is

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
    function get_read_pointer ( self : ram_read_port_record)
        return integer;
------------------------------------------------------------------------
    function read_is_requested ( self : ram_read_port_record)
        return boolean;
------------------------------------------------------------------------
end package ram_read_port_pkg;

------------------------------------------------------------------------
package body ram_read_port_pkg is

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
    function read_is_requested
    (
        self : ram_read_port_record
    )
    return boolean is
    begin
        return self.read_requested_with_1 = '1';
    end read_is_requested;
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
    function get_read_pointer
    (
        self : ram_read_port_record
    )
    return integer
    is
    begin
        return self.read_address;
    end get_read_pointer;
------------------------------------------------------------------------
end package body ram_read_port_pkg;
