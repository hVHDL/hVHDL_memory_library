library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package multi_port_ram_pkg is

    type ram_read_in_record is record
        address        : unsigned;
        read_requested : std_logic;
    end record;

    type ram_read_out_record is record
        data          : std_logic_vector;
        data_is_ready : std_logic;
    end record;

    type ram_write_in_record is record
        address         : unsigned;
        data            : std_logic_vector;
        write_requested : std_logic;
    end record;

    type ram_read_in_array  is array (natural range <>) of ram_read_in_record;
    type ram_read_out_array is array (natural range <>) of ram_read_out_record;
    type ram_write_in_array is array (natural range <>) of ram_write_in_record;
    
    type ram_read_in_array_of_arrays  is array (natural range <>) of ram_read_in_array;
    type ram_read_out_array_of_arrays is array (natural range <>) of ram_read_in_array;

    ----- used for instantiating subtypes -----
    type subtype_ref_record is record
        ram_read_in  : ram_read_in_array;
        ram_read_out : ram_read_out_array;
        ram_write_in : ram_write_in_record;
        address      : std_logic_vector;
        data         : std_logic_vector;
    end record;

    function create_ref_subtypes(readports : natural := 4 ; datawidth : natural := 16 ; addresswidth : natural := 10) return subtype_ref_record;
    -------------------------------------------

    -- constant init_read_in : ram_read_in_record := ((others => '0'), '0');
    -- constant init_write_in : ram_write_in_record := ((others => '0'), (others => '0'), '0');

     function combine(
         a : ram_read_in_array_of_arrays
         ; address_range_ref : std_logic_vector
         ; no_map_range_low : integer := 0
         ; no_map_range_hi : integer := 0
         ) return ram_read_in_array;

    function combine(a : ram_write_in_array) return ram_write_in_record;

    function "and" (left, right : ram_read_in_record) return ram_read_in_record;
    function "and" (left, right : ram_read_in_array) return ram_read_in_array;

    function "and" (left, right : ram_write_in_record) return ram_write_in_record;

    procedure init_mp_ram_read (
        signal self_read_in : out ram_read_in_record);

    procedure init_mp_ram_read (
        signal self_read_in : out ram_read_in_array);

    procedure init_mp_ram (
        signal self_read_in : out ram_read_in_array;
        signal self_write_in : out ram_write_in_record);

    procedure init_mp_write(signal self_write_in : out ram_write_in_record);

    procedure request_data_from_ram (
        signal self_read_in : out ram_read_in_record;
        address : in natural);

    function ram_read_is_ready ( self_read_out : ram_read_out_record)
        return boolean;

    function get_ram_data ( self_read_out : ram_read_out_record)
        return std_logic_vector;

    function read_requested(ram_read_in : ram_read_in_record) return boolean;
    function read_requested(ram_read_in : ram_read_in_record; address : natural) return boolean;

------------------------------------------------------------------------
------------------------------------------------------------------------
    procedure write_data_to_ram (
        signal self_write_in : out ram_write_in_record;
        address : in natural;
        data    : in std_logic_vector);

    function write_requested(ram_write_in : ram_write_in_record) return boolean;
    function write_requested(ram_write_in : ram_write_in_record; address : natural) return boolean;
    function get_address(ram_write_in : ram_write_in_record) return natural;
    function get_data(ram_write_in : ram_write_in_record) return std_logic_vector;
    --
    function uint_to_slv(a : integer; slv : std_logic_vector) return std_logic_vector;
    function slv_to_uint(a : std_logic_vector) return natural;
------------------------------------------------------------------------
end package multi_port_ram_pkg;

package body multi_port_ram_pkg is

-----------------------------------
    function create_ref_subtypes(
        readports    : natural := 4;
        datawidth    : natural := 16;
        addresswidth : natural := 10
    ) return subtype_ref_record is
        constant retval : subtype_ref_record := (
            ram_read_in => (
                0 to readports - 1 => (
                    address        => (0 to addresswidth - 1 => '0'),
                    read_requested => '0'
                )
            )

            ,ram_read_out => (
                0 to readports - 1 => (
                    data          => (datawidth - 1 downto 0 => '0'),
                    data_is_ready => '0'
                )
            )

            ,ram_write_in => (
                address          => (0 to addresswidth - 1 => '0'),
                data             => (datawidth - 1 downto 0 => '0'),
                write_requested  => '0'
            )

            ,address => (addresswidth - 1 downto 0 => '0')
            ,data    => (datawidth - 1 downto 0    => '0')
        );
    begin
        return retval;
    end create_ref_subtypes;
-----------------------------------

    procedure init_mp_ram_read
    (
        signal self_read_in : out ram_read_in_record
    ) is
    begin
        self_read_in.address <= (self_read_in.address'range => '0');
        self_read_in.read_requested <= '0';
    end init_mp_ram_read;

    procedure init_mp_ram_read
    (
        signal self_read_in : out ram_read_in_array
    ) is
    begin
        for i in self_read_in'range loop
            self_read_in(i).address <= (self_read_in(self_read_in'low).address'range => '0');
            self_read_in(i).read_requested <= '0';
        end loop;
    end init_mp_ram_read;
------------------------------------------------------------------------
    procedure init_mp_ram
    (
        signal self_read_in : out ram_read_in_array;
        signal self_write_in : out ram_write_in_record
    ) is
    begin
        init_mp_ram_read(self_read_in);
        self_write_in.write_requested <= '0';
        self_write_in.address         <= (self_write_in.address'range => '0');
        self_write_in.data            <= (self_write_in.data'range => '0');
    end init_mp_ram;
------------------------------
    procedure init_mp_write(signal self_write_in : out ram_write_in_record) is
    begin
        self_write_in.write_requested <= '0';
        self_write_in.address         <= (self_write_in.address'range => '0');
        self_write_in.data            <= (self_write_in.data'range => '0');
    end init_mp_write;
------------------------------
    procedure request_data_from_ram
    (
        signal self_read_in : out ram_read_in_record;
        address : in natural
    ) is
    begin
        self_read_in.address <= to_unsigned(address, self_read_in.address'length);
        self_read_in.read_requested <= '1';
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
    function read_requested(ram_read_in : ram_read_in_record) return boolean is
    begin
        return (ram_read_in.read_requested = '1');
    end read_requested;
------------------------------------------------------------------------
    function read_requested(ram_read_in : ram_read_in_record; address : natural) return boolean is
    begin
        return (ram_read_in.read_requested = '1') and (ram_read_in.address = address);
    end read_requested;
------------------------------------------------------------------------
------------------------------------------------------------------------
    procedure write_data_to_ram
    (
        signal self_write_in : out ram_write_in_record;
        address : in natural;
        data : in std_logic_vector
    ) is
    begin
        self_write_in.address <= to_unsigned(address, self_write_in.address'length);
        self_write_in.data    <= data;
        self_write_in.write_requested <= '1';
    end write_data_to_ram;
------------------------------------------------------------------------
    function write_requested(ram_write_in : ram_write_in_record) return boolean is
    begin
        return (ram_write_in.write_requested = '1');
    end write_requested;
------------------------------------------------------------------------
    function write_requested(ram_write_in : ram_write_in_record; address : natural) return boolean is
    begin
        return (ram_write_in.write_requested = '1') and (ram_write_in.address = address);
    end write_requested;
------------------------------------------------------------------------
    function get_address(ram_write_in : ram_write_in_record) return natural is
    begin
        return to_integer(ram_write_in.address);
    end get_address;

    function get_data(ram_write_in : ram_write_in_record) return std_logic_vector is
    begin
        return ram_write_in.data;
    end get_data;
------------------------------------------------------------------------
    function uint_to_slv(a : integer; slv : std_logic_vector) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(a, slv'length));
    end uint_to_slv;
------------------------------------------------------------------------
    function slv_to_uint(a : std_logic_vector) return natural is
    begin
        return to_integer(unsigned(a));
    end slv_to_uint;
------------------------------------------------------------------------
------------------------------------------------------------------------
    function "and" (left, right : ram_read_in_record) return ram_read_in_record is
        variable retval : left'subtype;
    begin
        retval.address        := left.address or right.address;
        retval.read_requested := left.read_requested or right.read_requested;

         return retval;
     end function;
------------------------------------------
    function "and" (left, right : ram_read_in_array) return ram_read_in_array is
        variable retval : ram_read_in_array(left'range)(address(left(left'low).address'range));
    begin

        for i in left'range loop
            retval(i) := left(i) and right(i);
        end loop;

        return retval;
    end function;
------------------------------------------
    function "and" (left, right : ram_write_in_record) return ram_write_in_record is
        variable retval : left'subtype;
    begin
        retval.address := left.address or right.address;
        retval.data := left.data or right.data;
        retval.write_requested := left.write_requested or right.write_requested;

        return retval;
    end function;
------------------------------------------------------------------------
     function combine(a : ram_write_in_array) return ram_write_in_record is
         variable retval : ram_write_in_record(address(a(a'low).address'range), data(a(a'low).data'range)) := ((others => '0'), (others => '0'),'0');
     begin
         for i in a'range loop
             retval := retval and a(i);
         end loop;

         return retval;
     end combine;
------------------------------------------------------------------------
     function combine(
         a : ram_read_in_array_of_arrays
         ; address_range_ref : std_logic_vector
         ; no_map_range_low : integer := 0
         ; no_map_range_hi : integer := 0
         ) return ram_read_in_array is

         variable retval : ram_read_in_array(
                            a(a'low)'range
                        )(
                            address(address_range_ref'range)
                        ) := (others => ((others => '0'),'0'));

     begin
         for i in a'range loop
             retval := retval and a(i);
         end loop;

         for i in retval'range loop
             if retval(i).address >= no_map_range_low
                and retval(i).address <= no_map_range_hi
             then
                 retval(i).read_requested := '0';
             end if;
         end loop;

         return retval;
     end combine;

------------------------------------------------------------------------
end package body multi_port_ram_pkg;
------------------------------------------------------------------------
------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

    use work.multi_port_ram_pkg.all;
    use work.dual_port_ram_pkg.all;

entity multi_port_ram is
    generic(initial_values : work.dual_port_ram_pkg.ram_array);
    port (
        clock         : in std_logic
        ;ram_read_in  : in work.multi_port_ram_pkg.ram_read_in_array
        ;ram_read_out : out work.multi_port_ram_pkg.ram_read_out_array
        --------------------
        ;ram_write_in : in work.multi_port_ram_pkg.ram_write_in_record
    );
end entity multi_port_ram;
---
architecture single_write of multi_port_ram is

    -- constant ram_bit_width = ram_read_out(ram_read_out'left).data'length

    -- helper constant to be used for constraining address with 'range 
    constant address_range_ref : unsigned(ram_read_in(ram_read_in'low).address'range) := (others => '0');

    signal ram_a_in  : ram_in_array(ram_read_in'range)(address(address_range_ref'range), data(initial_values(0)'range));
    signal ram_a_out : ram_out_array(ram_read_in'range)(data(initial_values(0)'range));
    signal ram_b_in  : ram_a_in'subtype;
    signal dummy_ram_b_out : ram_a_out'subtype;

begin

    create_rams :
    for i in ram_read_in'range generate
        u_dpram : entity work.dual_port_ram
        generic map(initial_values)
        port map(
        clock        
        ,ram_a_in(i)  
        ,ram_a_out(i) 
        --------------
        ,ram_b_in(i)
        
        ,dummy_ram_b_out(i)); -- not connected to anything

        ram_a_in(i) <= (
            address            => ram_read_in(i).address
            ,read_is_requested => ram_read_in(i).read_requested
            ,data              => (others => '0')
            ,write_requested   => '0');

        ram_read_out(i) <= (
            data => ram_a_out(i).data
            ,data_is_ready => ram_a_out(i).data_is_ready);

        ram_b_in(i) <= (
            address            => ram_write_in.address
            ,read_is_requested => '0'
            ,data              => ram_write_in.data
            ,write_requested   => ram_write_in.write_requested);
    end generate;

end single_write;
