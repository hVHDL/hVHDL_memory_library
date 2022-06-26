library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

    use work.ram_read_port_pkg.all;

package ram_write_port_pkg is

    type ram_write_port_record is record
        write_address             : address_integer;
        write_is_requested_with_1 : std_logic;
        write_is_ready            : boolean;
        write_buffer              : lut_integer;
    end record;

    constant init_ram_write_port : ram_write_port_record := (0, '0', false, 0);
------------------------------------------------------------------------
    procedure create_ram_write_port (
        signal ram_object : inout ram_write_port_record;
        signal ram_memory : inout integer_array);

------------------------------------------------------------------------
    procedure write_data_to_ram (
        signal ram_object : inout ram_write_port_record;
        address           : in integer;
        data              : in integer);
------------------------------------------------------------------------
end package ram_write_port_pkg;

package body ram_write_port_pkg is
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
------------------------------
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
