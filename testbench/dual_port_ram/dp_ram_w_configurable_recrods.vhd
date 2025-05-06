
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package dual_port_ram_pkg is

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

-- move to separate source file once it works
architecture sim of dual_port_ram is

    subtype inst_ram_array is g_ram_init_values'subtype;

------------------------------------------------------------------------
    -- impure function init_ram
    -- (
    --     ram_init_values : g_ram_init_values'subtype
    -- )
    -- return g_ram_init_values'subtype
    -- is
    --     variable retval : g_ram_init_values'subtype := (others => (others => '0'));
    -- begin
    --
    --     for i in ram_init_values'range loop
    --         retval(i) := ram_init_values(i);
    --     end loop;
    --
    --     return retval;
    --
    -- end init_ram;

    type dp_ram is protected

    ------------------------------
        procedure write_ram(
            address : in natural;
            data :    in std_logic_vector);
    ------------------------------
        impure function read_data(address : natural)
            return std_logic_vector;
    ------------------------------
        impure function get_ram_array return inst_ram_array;
    ------------------------------

    end protected dp_ram;

------------------------------------------------------------------------
------------------------------------------------------------------------
    type dp_ram is protected body
    ------------------------------

        variable ram_contents : inst_ram_array /*:= init_ram(g_ram_init_values) */;

    ------------------------------
        impure function get_ram_array return inst_ram_array
        is
        begin
            return ram_contents;
        end get_ram_array;
    ------------------------------
        impure function read_data
        (
            address : natural
        )
        return std_logic_vector 
        is
        begin
            return ram_contents(address);
        end read_data;

    ------------------------------
        procedure write_ram
        (
            address : in natural;
            data    : in std_logic_vector
        ) is
        begin
            ram_contents(address) := data;
        end write_ram;


    ------------------------------
    end protected body;
------------------------------------------------------------------------

    shared variable dual_port_ram_array : dp_ram;

    signal read_a_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_a_buffer : std_logic_vector(ram_a_out.data'range);

    signal read_b_pipeline : std_logic_vector(1 downto 0) := (others => '0');
    signal output_b_buffer : std_logic_vector(ram_b_out.data'range);
    -- signal debug_ram_contents : inst_ram_array := init_ram(initial_values);

begin
    ram_a_out.data_is_ready <= read_a_pipeline(read_a_pipeline'left);
    ram_b_out.data_is_ready <= read_b_pipeline(read_a_pipeline'left);

    create_ram_a_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_a_pipeline <= read_a_pipeline(read_a_pipeline'left-1 downto 0) & ram_a_in.read_is_requested;
            ram_a_out.data <= output_a_buffer;
            if (ram_a_in.read_is_requested = '1') or (ram_a_in.write_requested = '1') then
                output_a_buffer <= dual_port_ram_array.read_data(to_integer(ram_a_in.address));
                if ram_a_in.write_requested = '1' then
                    dual_port_ram_array.write_ram(to_integer(ram_a_in.address), ram_a_in.data);
                end if;
            end if;
            -- debug_ram_contents <= dual_port_ram_array.get_ram_array;
        end if;
    end process;

    create_ram_b_port : process(clock)
    begin
        if(rising_edge(clock)) then
            read_b_pipeline <= read_b_pipeline(read_b_pipeline'left-1 downto 0) & ram_b_in.read_is_requested;
            ram_b_out.data <= output_b_buffer;
            if (ram_b_in.read_is_requested = '1') or (ram_b_in.write_requested = '1') then
                output_b_buffer <= dual_port_ram_array.read_data(to_integer(ram_b_in.address));
                if ram_b_in.write_requested = '1' then
                    dual_port_ram_array.write_ram(to_integer(ram_b_in.address), ram_b_in.data);
                end if;
            end if;
        end if;
    end process;

end sim;

-------------------------------------------------------------
LIBRARY ieee  ; 
    USE ieee.NUMERIC_STD.all  ; 
    USE ieee.std_logic_1164.all  ; 
    use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity configurable_dual_port_ram_tb is
  generic (runner_cfg : string);
end;

architecture vunit_simulation of configurable_dual_port_ram_tb is

    constant clock_period      : time    := 1 ns;
    constant simtime_in_clocks : integer := 1500;
    
    signal simulator_clock     : std_logic := '0';
    signal simulation_counter  : natural   := 0;
    -----------------------------------
    -- simulation specific signals ----
    use work.dual_port_ram_pkg.all;

    constant init_values : ram_array(0 to 1023)(15 downto 0) := (others => (others => '0'));

    signal ram_a_in  : ram_in_record(address(0 to 9), data(15 downto 0));
    signal ram_a_out : ram_out_record(data(15 downto 0));
    --------------------
    signal ram_b_in  : ram_a_in'subtype;
    signal ram_b_out : ram_a_out'subtype;

    signal read_counter : natural := 512;
    signal ready_counter : natural := 0;

    signal ram_was_read : boolean := false;

    signal test_output : std_logic_vector(ram_a_out.data'range) := (others => '0');

    signal output_is_correct : boolean := false;
    signal last_ram_index_was_read : boolean := false;

begin

------------------------------------------------------------------------
    simtime : process
    begin
        test_runner_setup(runner, runner_cfg);
        wait for simtime_in_clocks*clock_period;
        check(ram_was_read);
        check(last_ram_index_was_read, "last index was not read");
        test_runner_cleanup(runner); -- Simulation ends here
        wait;
    end process simtime;	

    simulator_clock <= not simulator_clock after clock_period/2.0;

------------------------------------------------------------------------

    stimulus : process(simulator_clock)
    begin
        if rising_edge(simulator_clock) then
            simulation_counter <= simulation_counter + 1;
            init_ram(ram_a_in);
            init_ram(ram_b_in);

            if simulation_counter < init_values'length/2 then
                write_data_to_ram(ram_a_in, simulation_counter*2, std_logic_vector(to_unsigned(simulation_counter*2, ram_a_in.data'length)));
                write_data_to_ram(ram_b_in, simulation_counter*2+1, std_logic_vector(to_unsigned(simulation_counter*2+1, ram_a_in.data'length)));
            end if;

            if simulation_counter = init_values'length/2 then
                read_counter <= 0;
            end if;

            if read_counter < init_values'length/2 then
                read_counter <= read_counter + 1;
                request_data_from_ram(ram_a_in, read_counter*2);
                request_data_from_ram(ram_b_in, read_counter*2+1);
            end if;

            if ram_read_is_ready(ram_a_out) then
                ready_counter           <= ready_counter + 1;
                test_output             <= get_ram_data(ram_a_out);
                output_is_correct       <= (get_ram_data(ram_a_out) = std_logic_vector(to_unsigned(ready_counter*2, ram_a_out.data'length)));
                last_ram_index_was_read <= to_integer(unsigned(get_ram_data(ram_b_out))) = init_values'high;

                check(get_ram_data(ram_a_out) = std_logic_vector(to_unsigned(ready_counter*2   , ram_a_out.data'length)));
                check(get_ram_data(ram_b_out) = std_logic_vector(to_unsigned(ready_counter*2+1 , ram_b_out.data'length)));
            end if;
            ram_was_read <= ram_was_read or ram_read_is_ready(ram_a_out);

        end if; -- rising_edge
    end process stimulus;	
------------------------------------------------------------------------
    u_dpram : entity work.dual_port_ram
    generic map(init_values)
    port map(
    simulator_clock ,
    ram_a_in   ,
    ram_a_out  ,
    --------------
    ram_b_in  ,
    ram_b_out);
    
------------------------------------------------------------------------
end vunit_simulation;
