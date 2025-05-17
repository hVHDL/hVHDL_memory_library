
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package dual_port_ram_pkg is

    constant read_pipeline_delay : natural := 2;
    type ram_array is array (natural range <>) of std_logic_vector;

    type ram_in_record is record
        address           : unsigned;
        read_is_requested : std_logic;
        data              : std_logic_vector;
        write_requested   : std_logic;
    end record;

    type ram_out_record is record
        data          : std_logic_vector;
        data_is_ready : std_logic;
    end record;

    type ram_in_array is array (natural range <>) of ram_in_record;
    type ram_out_array is array (natural range <>) of ram_out_record;

    procedure init_ram (
        signal self_in : out ram_in_record);

    procedure init_ram (
        signal self_in : inout ram_in_array);

    procedure request_data_from_ram (
        signal self_in : out ram_in_record;
        address : in natural);

    function ram_read_is_ready ( self_read_out : ram_out_record)
        return boolean;

    function get_ram_data ( self_read_out : ram_out_record)
        return std_logic_vector;

    function get_uint_ram_data ( self_read_out : ram_out_record)
        return integer;
------------------------------------------------------------------------
------------------------------------------------------------------------
    procedure write_data_to_ram (
        signal self_in : out ram_in_record;
        address : in natural;
        data    : in std_logic_vector);

end package dual_port_ram_pkg;

package body dual_port_ram_pkg is

------------------------------------------------------------------------
    procedure init_ram
    (
        signal self_in : out ram_in_record
    ) is
    begin
        self_in.read_is_requested <= '0';
        self_in.write_requested   <= '0';
    end init_ram;

    procedure init_ram
    (
        signal self_in : inout ram_in_array
    ) is
    begin
        for i in self_in'range loop
            self_in(i).read_is_requested <= '0';
            self_in(i).write_requested <= '0';
        end loop;
    end init_ram;

------------------------------
    procedure request_data_from_ram
    (
        signal self_in : out ram_in_record;
        address : in natural
    ) is
    begin

        self_in.address <= to_unsigned(address, self_in.address'length);
        self_in.read_is_requested <= '1';

    end request_data_from_ram;
------------------------------
    function ram_read_is_ready
    (
        self_read_out : ram_out_record
    )
    return boolean
    is
    begin
        return self_read_out.data_is_ready = '1';
        
    end ram_read_is_ready;
------------------------------
    function get_ram_data
    (
        self_read_out : ram_out_record
    )
    return std_logic_vector 
    is
    begin
        return self_read_out.data;
    end get_ram_data;
------------------------------------------------------------------------
    function get_uint_ram_data
    (
        self_read_out : ram_out_record
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
        signal self_in : out ram_in_record;
        address : in natural;
        data : in std_logic_vector
    ) is
    begin
        self_in.address <= to_unsigned(address, self_in.address'length);
        self_in.data    <= data;
        self_in.write_requested <= '1';
    end write_data_to_ram;
------------------------------------------------------------------------
end package body dual_port_ram_pkg;
------------------------------------------------------------------------
------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.dual_port_ram_pkg.all;

entity dual_port_ram is
    generic(g_ram_init_values : work.dual_port_ram_pkg.ram_array);
    port (
        clock     : in std_logic;
        ram_a_in  : in work.dual_port_ram_pkg.ram_in_record;
        ram_a_out : out work.dual_port_ram_pkg.ram_out_record;
        --------------------
        ram_b_in  : in work.dual_port_ram_pkg.ram_in_record;
        ram_b_out : out work.dual_port_ram_pkg.ram_out_record
    );
end entity dual_port_ram;
