library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

    use work.ram_configuration_pkg.ram_bit_width;
    use work.ram_configuration_pkg.ram_depth;
    use work.ram_configuration_pkg.address_integer;
    use work.ram_configuration_pkg.t_ram_data;

package ram_read_pkg is

    alias ram_bit_width is ram_bit_width;
    alias ram_depth is ram_depth;

    alias address_integer is address_integer;
    alias t_ram_data is t_ram_data;

    type ram_array is array (integer range 0 to ram_depth-1) of t_ram_data;

    type ram_read_port_record is record
        read_address   : address_integer;
        ready_pipeline : std_logic_vector(1 downto 0);
        data           : t_ram_data;
    end record;

    constant init_ram_read_port : ram_read_port_record := (0, (others => '0'), (others => '0'));

------------------------------------------------------------------------
    procedure create_ram_read_port (
        signal self : inout ram_read_port_record);
------------------------------------------------------------------------
    procedure request_data_from_ram_and_increment (
        signal ram_read_counter : inout integer;
        signal self : out ram_read_port_record;
        address : integer);
------------------------------------------------------------------------
    function ram_read_is_ready ( self : ram_read_port_record)
        return boolean;

    function last_read_ready ( self : ram_read_port_record)
        return boolean;
------------------------------------------------------------------------
    function get_ram_data ( ram_read_object : ram_read_port_record)
        return std_logic_vector;
------------------------------------------------------------------------
    procedure request_data_from_ram (
        signal self : out ram_read_port_record;
        address : integer);
------------------------------------------------------------------------
    function get_ram_address ( self : ram_read_port_record)
        return integer;
------------------------------------------------------------------------
    function read_is_requested ( self : ram_read_port_record)
        return boolean;
------------------------------------------------------------------------
end package ram_read_pkg;

------------------------------------------------------------------------
package body ram_read_pkg is

------------------------------------------------------------------------
    procedure create_ram_read_port
    (
        signal self : inout ram_read_port_record
    ) is
    begin
        self.ready_pipeline <= self.ready_pipeline(self.ready_pipeline'left -1 downto 0) & '0';

    end create_ram_read_port;
------------------------------------------------------------------------
    function read_is_requested
    (
        self : ram_read_port_record
    )
    return boolean is
    begin
        return self.ready_pipeline(0) = '1';
    end read_is_requested;
------------------------------------------------------------------------
    procedure request_data_from_ram
    (
        signal self : out ram_read_port_record;
        address : integer
    ) is
    begin
        self.ready_pipeline(0) <= '1';
        self.read_address <= address;
    end request_data_from_ram;
------------------------------------------------------------------------
    procedure request_data_from_ram_and_increment
    (
        signal ram_read_counter : inout integer;
        signal self : out ram_read_port_record;
        address : integer
    ) is
    begin
        ram_read_counter <= ram_read_counter + 1;
        self.ready_pipeline(1) <= '1';
        self.read_address <= address;
    end request_data_from_ram_and_increment;
------------------------------------------------------------------------
    function ram_read_is_ready
    (
        self : ram_read_port_record
    )
    return boolean
    is
    begin
        return self.ready_pipeline(self.ready_pipeline'left) = '1';
    end ram_read_is_ready;
------------------------------------------------------------------------
    function get_ram_data
    (
        ram_read_object : ram_read_port_record
    )
    return std_logic_vector
    is
    begin
        return ram_read_object.data;
    end get_ram_data;
------------------------------------------------------------------------
    function get_ram_address
    (
        self : ram_read_port_record
    )
    return integer
    is
    begin
        return self.read_address;
    end get_ram_address;
------------------------------------------------------------------------
    function last_read_ready
    (
        self : ram_read_port_record
    )
    return boolean
    is
    begin
        return self.ready_pipeline(self.ready_pipeline'left downto self.ready_pipeline'left-1) = "10";
    end last_read_ready;
------------------------------------------------------------------------
end package body ram_read_pkg;
------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

    use work.ram_configuration_pkg.all;

package ram_write_pkg is

    -- make visible when using ram_write_pkg
    alias address_integer is address_integer;
    alias t_ram_data is t_ram_data;

    type ram_write_port_record is record
        write_address             : address_integer;
        write_is_requested_with_1 : std_logic_vector(1 downto 0);
        write_is_ready            : boolean;
        write_buffer              : t_ram_data;
    end record;

    constant init_ram_write_port : ram_write_port_record := (0, (others => '0'), false, (others => '0'));
------------------------------------------------------------------------
    procedure create_ram_write_port (
        signal self : inout ram_write_port_record);

------------------------------------------------------------------------
    procedure write_data_to_ram (
        signal self : inout ram_write_port_record;
        address           : in integer;
        data              : in integer);

    procedure write_data_to_ram (
        signal self : inout ram_write_port_record;
        address : in integer;
        data    : in std_logic_vector);
------------------------------------------------------------------------
    function write_is_requested ( self : ram_write_port_record)
        return boolean;
------------------------------------------------------------------------
    function write_is_ready ( self : ram_write_port_record)
        return boolean;
------------------------------------------------------------------------
    function get_write_address ( self : ram_write_port_record)
        return integer;
------------------------------------------------------------------------
end package ram_write_pkg;

package body ram_write_pkg is
------------------------------------------------------------------------
    procedure create_ram_write_port
    (
        signal self : inout ram_write_port_record
    ) is
    begin

        self.write_is_requested_with_1 <= self.write_is_requested_with_1(0) & '0';
        -- this needs to be external to this procedure
        -- if self.write_is_requested_with_1 = '1' then
        --     ram_memory(self.write_address) <= self.write_buffer;
        -- end if;

    end create_ram_write_port;
------------------------------------------------------------------------
    procedure write_data_to_ram
    (
        signal self : inout ram_write_port_record;
        address : in integer;
        data    : in std_logic_vector
    ) is
    begin
        self.write_is_requested_with_1(0) <= '1';
        self.write_buffer <= data;
        self.write_address <= address;
        
    end write_data_to_ram;
------------------------------
    procedure write_data_to_ram
    (
        signal self : inout ram_write_port_record;
        address : in integer;
        data    : in integer
    ) is
    begin
        self.write_is_requested_with_1(0) <= '1';
        self.write_buffer <= std_logic_vector(to_signed(data,t_ram_data'length));
        self.write_address <= address;
        
    end write_data_to_ram;
------------------------------
    procedure write_data_to_ram
    (
        signal to_increment : inout integer;
        signal self : inout ram_write_port_record;
        address : in integer;
        data    : in integer
    ) is
    begin
        to_increment <= to_increment + 1;
        write_data_to_ram(self, address, data);
        
    end write_data_to_ram;
------------------------------------------------------------------------
    function write_is_requested
    (
        self : ram_write_port_record
    )
    return boolean
    is
    begin
        return self.write_is_requested_with_1(0) = '1';
    end write_is_requested;
------------------------------------------------------------------------
    function write_is_ready
    (
        self : ram_write_port_record
    )
    return boolean
    is
    begin
        return self.write_is_requested_with_1(1) = '1';
    end write_is_ready;
------------------------------------------------------------------------
    function get_ram_address
    (
        self : ram_write_port_record
    )
    return integer
    is
    begin
        return self.write_address;
    end get_ram_address;
------------------------------------------------------------------------
    function get_write_address
    (
        self : ram_write_port_record
    )
    return integer
    is
    begin
        return self.write_address;
    end get_write_address;
------------------------------------------------------------------------
end package body ram_write_pkg;
