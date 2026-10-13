library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.ram_configuration_pkg.all;

package ram_port_pkg is

    -- move these to separate package
    subtype ramtype     is std_logic_vector(ram_bit_width-1 downto 0);
    subtype ram_address is natural range 0 to ram_depth-1;
    subtype ram_array   is work.ram_configuration_pkg.ram_array;

    type ram_in_record is record
        address           : ram_address;
        read_is_requested : std_logic;
        data              : std_logic_vector(ramtype'range);
        write_requested   : std_logic;
    end record;


    type ram_out_record is record
        data          : std_logic_vector(ramtype'range);
        data_is_ready : std_logic;
    end record;

    type ram_in_array is array (natural range <>) of ram_in_record;
    type ram_out_array is array (natural range <>) of ram_out_record;

    procedure init_ram (
        signal self_in : out ram_in_record);

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

end package ram_port_pkg;

package body ram_port_pkg is

------------------------------------------------------------------------
    procedure init_ram
    (
        signal self_in : out ram_in_record
    ) is
    begin
        self_in.read_is_requested <= '0';
        self_in.write_requested   <= '0';
    end init_ram;

------------------------------
    procedure request_data_from_ram
    (
        signal self_in : out ram_in_record;
        address : in natural
    ) is
    begin
        self_in.address <= address;
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
        self_in.address <= address;
        self_in.data    <= data;
        self_in.write_requested <= '1';
    end write_data_to_ram;
------------------------------------------------------------------------
end package body ram_port_pkg;
------------------------------------------------------------------------
------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.ram_port_pkg.all;

entity dual_port_ram is
    generic(initial_values : ram_array := (others => (others => '1')));
    port (
        clock          : in std_logic;
        ram_a_in  : in ram_in_record;
        ram_a_out : out ram_out_record;
        --------------------
        ram_b_in  : in ram_in_record;
        ram_b_out : out ram_out_record
    );
end entity dual_port_ram;

