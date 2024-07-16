
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.ram_configuration_pkg.all;

package multi_port_ram_pkg is

    -- move these to separate package
    subtype ramtype     is std_logic_vector(ram_bit_width-1 downto 0);
    subtype ram_address is natural range 0 to ram_depth-1;
    subtype ram_array   is work.ram_configuration_pkg.ram_array;

    type ram_read_in_record is record
        address : ram_address;
        read_is_requested : std_logic;
    end record;

    type ram_read_out_record is record
        data          : std_logic_vector(ramtype'range);
        data_is_ready : std_logic;
    end record;

    type ram_write_in_record is record
        address         : ram_address;
        data            : std_logic_vector(ramtype'range);
        write_requested : std_logic;
    end record;

    type ram_read_in_array  is array (natural range <>) of ram_read_in_record;
    type ram_read_out_array is array (natural range <>) of ram_read_out_record;

    procedure init_ram_read (
        signal self_read_in : out ram_read_in_record);

    procedure init_ram_read (
        signal self_read_in : out ram_read_in_array);

    procedure init_ram (
        signal self_read_in1 : out ram_read_in_record;
        signal self_read_in2 : out ram_read_in_record;
        signal self_write_in : out ram_write_in_record);

    procedure request_data_from_ram (
        signal self_read_in : out ram_read_in_record;
        address : in natural);

    function ram_read_is_ready ( self_read_out : ram_read_out_record)
        return boolean;

    function get_ram_data ( self_read_out : ram_read_out_record)
        return std_logic_vector;

    function get_uint_ram_data ( self_read_out : ram_read_out_record)
        return integer;
------------------------------------------------------------------------
------------------------------------------------------------------------
    procedure write_data_to_ram (
        signal self_write_in : out ram_write_in_record;
        address : in natural;

        data    : in std_logic_vector);
------------------------------------------------------------------------
end package multi_port_ram_pkg;

package body multi_port_ram_pkg is

    procedure init_ram_read
    (
        signal self_read_in : out ram_read_in_record
    ) is
    begin
        self_read_in.read_is_requested <= '0';
    end init_ram_read;

    procedure init_ram_read
    (
        signal self_read_in : out ram_read_in_array
    ) is
    begin
        for i in self_read_in'range loop
            self_read_in(i).read_is_requested <= '0';
        end loop;
    end init_ram_read;
------------------------------------------------------------------------
    procedure init_ram
    (
        signal self_read_in1 : out ram_read_in_record;
        signal self_read_in2 : out ram_read_in_record;
        signal self_write_in : out ram_write_in_record
    ) is
    begin
        self_read_in1.read_is_requested <= '0';
        self_read_in2.read_is_requested <= '0';
        self_write_in.write_requested  <= '0';
    end init_ram;
------------------------------
------------------------------
    procedure request_data_from_ram
    (
        signal self_read_in : out ram_read_in_record;
        address : in natural
    ) is
    begin
        self_read_in.address <= address;
        self_read_in.read_is_requested <= '1';
    end request_data_from_ram;
------------------------------
    function ram_read_is_ready
    (
        self_read_out : ram_read_out_record
    )
    return boolean
    is
    begin
        return self_read_out.data_is_ready = '1';
        
    end ram_read_is_ready;
------------------------------
    function get_ram_data
    (
        self_read_out : ram_read_out_record
    )
    return std_logic_vector 
    is
    begin
        return self_read_out.data;
    end get_ram_data;
------------------------------------------------------------------------
    function get_uint_ram_data
    (
        self_read_out : ram_read_out_record
    )
    return integer
    is
    begin
        return to_integer(unsigned(self_read_out.data));
    end get_uint_ram_data;
------------------------------------------------------------------------
------------------------------------------------------------------------
    procedure write_data_to_ram
    (
        signal self_write_in : out ram_write_in_record;
        address : in natural;
        data : in std_logic_vector
    ) is
    begin
        self_write_in.address <= address;
        self_write_in.data <= data;
        self_write_in.write_requested <= '1';
    end write_data_to_ram;
------------------------------------------------------------------------
end package body multi_port_ram_pkg;
